# OnePlus 11 (salami): CN ColorOS → OxygenOS → LineageOS

These are experimental migration notes, not a guaranteed recovery procedure. Stop if a check does not match. A partition backup is evidence, not permission to restore it: replaying per-device secure state can be unsafe even on the same phone. Public EDL (9008) rescue routes require the correct PHB110 package and suitable access/tooling; do not treat them as a safety net.

Host tools: `scripts/00-host-tools.sh` downloads `adb`/`fastboot` (platform-tools ≥ 35) and `payload-dumper-go` into `tools/` (gitignored). The scripts put `tools/platform-tools` on `PATH` themselves; for hand-typed commands, add it yourself or prefix `tools/platform-tools/`.

**Run every command block in `bash`, not zsh.** zsh doesn't word-split unquoted variables, so loops like `for p in $logical` run once over the whole string and silently flash nothing. If your login shell is zsh, type `bash` first.

**Hard rules for the whole procedure:**
- Never run `fastboot flashing lock`, ever, on this phone.
- **NEVER restore, erase, format, or flash per-device/security-state partitions**, including `persist`, `keystore`, `secdata`, `tzsc`, `storsec`, `spunvm`, `qmcs`, `devinfo`, `uefivarstore`, `apdp*` (including `apdp_full`), `ssd`, `vm-persist`, `vm-data`, `qweslicstore_a/_b`, EFS (`modemst1`, `modemst2`, `fsg`, `fsc`), board/calibration state (`ocdt`, `cdt`, `dinfo`, `param`), or RPMB. This includes this phone's own old backups. Never run a whole-backup restore loop.
- Keep those images in a separate local **`backup/per-device-DO-NOT-RESTORE/`** archive, outside every flashing input folder. Never upload their contents, including to an LLM/model provider. The narrowly documented `oplusstanvbk_a/_b` modem fix is not authorization to restore other per-device state.
- Never flash OOS firmware older (lower Android version or earlier security-patch date) than what's currently on the phone. EDL rescue exists for this device but is nontrivial (cable/test-point + exact firehose package) — don't rely on it as the fallback for a bad flash.
- Keep battery above 60%, direct USB port, no hub.


**Scripts** (`scripts/`, run from the repo root with bash; each one prints what it will do and stops on errors):

| Script | Step | Mode |
|---|---|---|
| `00-host-tools.sh` | host setup | host |
| `10-backup-device.sh` | 3.3: collect flat backups and checksums; **manual per-device quarantine is mandatory afterward** | Android, rooted adb |
| `20-extract.sh <cn.zip> <oos.zip>` | 3.1 + 3.4: extract both OTAs; refuses OOS older than CN or than 16.0.5.1301 | host |
| `50-lineage-download.sh` | 5.1: newest build + `super_empty.img`, verified against the official API hashes | host |
| `30-oos-firmware.sh [-n]` | 4.3: conversion set (droidwin list + `init_boot`) from `oos/` (`FW_SRC=backup/cn-stock` for ColorOS), every other slotted partition plus `oplusstanvbk`/`modem` from `backup/device/`; keeps LineageOS `recovery`. `-n` prints the plan only | bootloader, or LineageOS-recovery fastbootd |
| `40-oos-super.sh [-n]` | 4.5: wipe `super`, recreate `<name>_a` (super_def size) + `<name>_b` (0 bytes), flash. `-n` prints the layout and commands only, no device | LineageOS-recovery fastbootd |
| `45-restore-stanvbk.sh` | put the CN `oplusstanvbk` back (after an OOS OTA or full-firmware flash) | fastbootd |
| `55-lineage-install.sh` | 5.2–5.7: boot images one per bootloader session, recovery, sideload | bootloader → recovery |
| `60-checks.sh` | IMEI-related checks: `qsf_init` crash count, `oplusstanvbk` still CN | Android |
| `70-network.sh` | captive-portal probes + NTP that work in China and abroad (section 7) | Android |
| `80-perf-diag.sh` | UI-lag diagnostics (section 7) | LineageOS, rooted debugging |
| `85-driver-check.sh` | GPU/display driver and vendor HAL health (section 7) | LineageOS; root for dmesg |
| `90-oplus-camera-module.sh` | Experimental OnePlus camera KernelSU ZIP built from `oos/` (section 7) | host |

**Path that worked on a PHB110:** `10` → `20` → `50` → bootloader: `fastboot flash recovery lineage/recovery.img`, boot Recovery → Advanced → Enter fastboot → `30` → `40` → recovery: Format data → bootloader: `fastboot --set-active=a` → `45` → OxygenOS boots with IMEI → `55` → LineageOS 24.0 works. The earlier failed attempt (sideload straight after `wipe-super`, then "drops to bootloader") was never root-caused.

---

## 1. Get the firmware files

1. Settings → About device → note the exact model (should be `PHB110`) and the current ColorOS build number.
2. Download the **full** (not incremental) CN ColorOS OTA matching that exact build. Check https://yun.daxiaamu.com/OnePlus_Roms/ (OnePlus 11 folder) first — it's known to list PHB110 ColorOS 16 packages directly, e.g. `16.0.1.300(CN01)` and `16.0.5.701(CN01)`. If it's moved or missing your build, also try: the XDA thread [ROM][OTA] Repository of OxygenOS & ColorOS FULL OTA's [OxygenOS 15 & 16][ColorOS 15 & 16] (https://xdaforums.com/t/rom-ota-repository-of-oxygenos-coloros-full-otas-oxygenos-15-16-coloros-15-16.4718692/), `https://github.com/chlink2025/oplusrom`, `https://github.com/JerryTse-OSS/OPlus-Tracker`, or search the exact build string directly. Match the build number **exactly** against Settings → About — a close-but-different ColorOS 16 sub-build is not safe to treat as this phone's own backup/restore source.
   - **Exception, needed either way:** step 3.2 needs *some* `init_boot.img` to Magisk-patch for root, with no other safe source on this device. On a GKI device `init_boot` is just the generic ramdisk, essentially identical across ColorOS 16 sub-builds — so a near-match PHB110 ColorOS 16 package (even not your exact build) is an acceptable **`init_boot.img` patch source only**: it's flashed to the current slot temporarily and gets overwritten again in step 4 anyway. It is **not** an acceptable source for the rest of `backup/cn-stock/` (restore/compare purposes) if it's not your exact build — see the `super.img` requirement in step 3.3.
3. Download a **full** CPH2449 (EU or GLO) OxygenOS OTA on **Android 16**, latest security patch — same sources. If `spike0en/oneplus_archive` has no `salami`/CPH2449 listing (it currently only lists newer devices, OnePlus 12 and up), use https://github.com/oxygen-updater/oxygen-updater/releases/latest (the Oxygen Updater app/tool) instead.
4. Verify each zip's SHA256 against the source's published hash.
5. `mkdir -p backup/cn-stock backup/device oos logs`

**Check:** both full OTA zips downloaded, hashes verified, four directories exist.

---

## 2. Confirm stock works, capture IMEI, then unlock

1. On current CN stock: send/receive an SMS, make a call over LTE, and over WiFi calling if you have it set up. If any of these don't work now, fix that first — they won't magically work after LineageOS either.
2. Dial `*#06#`, photograph both IMEIs, save the numbers into `logs/imei-before.txt` by hand. There's no software readout of this before you're rooted, and it's the only way you'll notice later if EFS got corrupted.
3. Settings → About → tap Build number 7 times → Developer options appears.
4. Developer options → enable **OEM unlocking** and **USB debugging**.
   - If OEM unlocking stays greyed out: some CN builds gate it behind an "in-depth test" app or require the phone to be online. Resolve that before continuing — nothing downstream works without this.
5. Plug in USB. `adb devices -l` — accept the RSA prompt on the phone, then confirm the serial shows up.
6. Now that adb actually works, back up anything you care about off the phone: `adb pull /sdcard/DCIM ./userbackup/`, etc. — unlocking wipes `userdata` next.
7. `adb -d reboot bootloader`
8. `fastboot devices` — must print the serial.
9. `fastboot getvar all > logs/getvar-before.txt 2>&1`
10. `fastboot flashing unlock` — confirm on-screen with volume/power.

**Check:** `fastboot getvar unlocked` → `unlocked: yes`. Orange unlock warning on boot. After the wipe-reboot, redo steps 3–4 (Developer options and USB debugging get reset).

---

## 3. Back up everything before touching firmware

**What the backups mean:** step 1 extracts firmware from a downloaded CN **zip**. Step 3 captures this phone's live partitions. Neither is a generic rollback or full-restore source. Per-device images are retained only for private, read-only investigation or assessment by authorized service; quarantine them as described below. A byte-identical backup does not prove that replaying it remains compatible with protected state elsewhere.

1. `tools/payload-dumper-go -o backup/cn-stock/ <ColorOS_CN_full.zip>` (point it at the zip, or the `payload.bin` inside it).
   **Check:** `backup/cn-stock/` contains `init_boot.img boot.img vendor_boot.img xbl_config.img modem.img system.img` and others.
   `(cd backup/cn-stock && sha256sum -- *.img > SHA256SUMS)`
2. Root temporarily, just to pull EFS:
   ```
   adb install Magisk-v*.apk
   adb push backup/cn-stock/init_boot.img /sdcard/Download/
   ```
   - On-device, open Magisk → Install → Select and Patch a File → pick `/sdcard/Download/init_boot.img` → Let It Rip.
   ```
   patched=$(adb shell ls /sdcard/Download/magisk_patched-*.img | tr -d '\r')
   adb pull "$patched" ./magisk_patched.img
   adb reboot bootloader
   fastboot flash init_boot_$(fastboot getvar current-slot 2>&1 | awk '/current-slot/{print $2}') magisk_patched.img
   fastboot reboot
   ```
   (`adb pull` doesn't expand remote wildcards itself — `adb shell ls` resolves the exact filename on-device first.)
   - Phone boots into Android. Open the Magisk app, grant root to the adb shell when prompted (or add it manually under Magisk → Superuser).
3. Capture the partition list, then dump everything except `userdata`/`super` and the whole-disk `sda`–`sdf` entries. **`backup/device/` is a temporary collection folder, not a restore set.** The loop and `scripts/10-backup-device.sh` skip complete dumps and redo partial ones; after collection, the mandatory separation below must happen before flashing. Do not rerun the backup script as a recovery operation or mix snapshots from different dates.
```
adb shell -T su -c id   # must print uid=0
adb shell -T su -c 'ls -1 /dev/block/by-name' | tr -d '\r' > logs/partitions.txt
while read -r p; do
  case $p in userdata|super|sd[a-z]|sd[a-z][0-9]*|'') continue ;; esac
  out="backup/device/$p.img"
  want=$(adb shell -T su -c "blockdev --getsize64 /dev/block/by-name/$p" </dev/null | tr -d '\r')
  [[ $want =~ ^[0-9]+$ ]] || want=""
  if [[ -s $out ]]; then
    if [[ -z $want ]]; then echo "skip $p (exists, size unknown)"; continue; fi
    [[ $(stat -c %s "$out") == "$want" ]] && { echo "skip $p (complete)"; continue; }
  fi
  echo ">> $p (${want:-unknown} bytes)"
  adb exec-out "su -c 'dd if=/dev/block/by-name/$p bs=4M 2>/dev/null'" </dev/null > "$out"
  [[ -z $want || $(stat -c %s "$out") == "$want" ]] || echo "SIZE MISMATCH: $p"
done < logs/partitions.txt
(cd backup/device && sha256sum -- *.img > SHA256SUMS)
for p in persist modemst1 modemst2 fsg fsc; do [[ -s backup/device/$p.img ]] || echo "MISSING: $p"; done
```
   (`</dev/null` on the adb calls matters: without it adb reads the loop's stdin and silently eats the rest of the partition list.)
   **Check before separation:** no `MISSING:` lines; every captured image is non-empty (`persist.img` should be tens of MB). Keep the original checksum manifest as a record of this snapshot. Copy the archive to a second private disk; do not upload it.
   - **`super` is excluded above deliberately** — it's ~12–16 GB. If the original logical images are unavailable, retain a private snapshot for offline reference: `adb exec-out "su -c 'dd if=/dev/block/by-name/super bs=4M 2>/dev/null'" > backup/device/super.img`. This captures the current logical layout and contents; it is **not** a restore recipe. Do not flash it back as a generic recovery step or include it in a whole-backup restore.

   **Mandatory backup separation before flashing:**
   - Resolve source folders before moving anything: in the existing workstation backup, `backup/device` is a symlink to `backup/cn-stock`. They are one source, not independent copies. Resolve and deduplicate aliases locally, record the relationship, and operate on each real source directory only once.
   - Move **every protected per-device image** listed in the hard rules and section 4.1—including the slotted `qweslicstore_a/_b` images—into a private `backup/per-device-DO-NOT-RESTORE/<source-snapshot>/` archive. Its real directory must be separate from all resolved flashing-input directories, not another alias of them. Preserve original filenames and manifests; never overwrite an existing archived snapshot.
   - If genuinely separate copies exist in `backup/cn-stock/`, `oos/`, or another flashing input folder, quarantine each source separately. Preserve provenance rather than inferring it from folder names or treating symlink aliases as independent backups.
   - Leave the explicitly documented CN `oplusstanvbk_a.img` and `oplusstanvbk_b.img` modem-fix inputs at their existing `backup/device/` paths. This narrow exception does not apply to EFS/security/calibration images. Do not move protected images back to satisfy a tool or recovery recipe.
   - Keep checksum manifests alongside each archived snapshot and update path records locally after moving files. If collection is rerun, repeat this separation; the existing backup script writes to the flat collection folder.
   - Separation reduces accidental wildcard flashing; it does **not** make all remaining firmware safe to restore. Never pass the archive to `fastboot`, `dd`, a full-restore script, or a third-party flasher.

   **Why even this phone's own backup is not a safe reset:** Qualcomm SFS protects object/index versions and integrity state through RPMB. If that protected state advanced after a backup, replaying older filesystem objects can fail authentication. This is stale secure-state rejection, not RPMB itself "breaking"; booting once does **not** automatically cause it. We have **not proved** it caused this phone's attestation failure. See [Qualcomm storage security](https://docs.qualcomm.com/doc/80-70014-11/topic/secure-file-system.html) and its [secure-storage whitepaper, SFS rollback protection](https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/documents/guard_your_data_with_the_qualcomm_snapdragon_mobile_platform2.pdf).

   **Runtime state is not factory provisioning:** some TA-owned runtime data may be recreated through a supported reset workflow. That does not recreate factory attestation keys/certificates or prove an opaque secure-store directory is disposable. Do not delete secure-store files as an experiment.

   **Never attempt RPMB erase or reprovisioning**, including QFIL/EDL/firehose erase options, OEM RPMB commands, or third-party unbrick-tool features. Qualcomm documents RPMB key provisioning as one-time and non-overwritable; these are not identity-reset procedures and can destroy access to protected data. No verified local factory-attestation repair has been established for this phone.

   **RPMB is not in this dump:** the backup loop reads ordinary `/dev/block/by-name` partitions, not the separately accessed authenticated RPMB storage. Replaying these `.img` files cannot directly restore or reset RPMB. Filesystem-backed secure state can nevertheless be stale relative to its RPMB-protected integrity state.

   **Attestation failure does not establish damaged identity:** the standalone tests show working ordinary hardware crypto but failing default attestation. A [OnePlus 13/15 experiment](https://wuxianlin.com/2025/11/12/oneplus-13-15-attestation-rkp-test/) reports similar unlock-state-dependent unavailability. That is a credible hypothesis, **not a confirmed PHB110 diagnosis**; restore damage and physical damage remain unproved. Do not authorize a mainboard replacement based on `-49` alone, and never test by relocking or writing attestation/provisioning state. See the [current measured findings](LineageOS_KSUN_SUSFS/docs/play-integrity-debug.md#what-we-verified-2026-10-22).
4. Firmware-downgrade check — this is the actual go/no-go, since Qualcomm's fuse anti-rollback counter isn't readable by any tool here. Extract the OOS payload first, since the secondary check below needs its `vbmeta.img`:
   ```
   tools/payload-dumper-go -o oos/ <OxygenOS_full.zip>
   unzip -p <ColorOS_CN_full.zip> META-INF/com/android/metadata | grep -E 'post-(security-patch-level|sdk-level|build)' | tee logs/cn-build.txt   # skip this line if you have no CN zip at all
   unzip -p <OxygenOS_full.zip> META-INF/com/android/metadata | grep -E 'post-(security-patch-level|sdk-level|build)' | tee logs/oos-build.txt
   ```
   **Go/no-go:** OOS `post-sdk-level` ≥ CN's, and OOS `post-security-patch-level` ≥ CN's. If either is lower, stop — find a newer OOS build instead.
   No CN zip at all? Read the live device's own build info instead — same comparison, no zip required: `adb shell 'getprop ro.build.version.security_patch; getprop ro.build.version.sdk' | tee logs/cn-build.txt` (two separate `getprop` calls — its second argument is a *default value*, not a second property name, so one call can't read both). Since this phone is already on ColorOS 16, the Android-major side of the go/no-go is already satisfied by definition; only the security-patch-date comparison still matters.
   - Optional secondary sanity check (AVB rollback index, not the real fuse ARB, and not enforced while unlocked): `python3 tools/avbtool.py info_image --image oos/vbmeta.img | grep "Rollback Index"`, compare to the CN build's `vbmeta.img`.

---

## 4. Flash OxygenOS

Two modes are involved: **fastbootd** (userspace, `is-userspace: yes`) is the only mode that can see and write the logical partitions inside `super`; the **bootloader** (`is-userspace: no`, plain "FASTBOOT MODE" screen) is the only one that can write all physical firmware — fastbootd refuses some of it (on PHB110, `modem_a` fails with `Operation not permitted`). So: read the partition layout in fastbootd, flash physical in the bootloader, then go back to fastbootd for logical.

**4.1 — fastbootd: read the layout.** The phone is currently booted into Android (from step 3.2), so:

```
adb reboot fastboot
```
If that's not supported on your current build, fall back to `adb reboot bootloader` then `fastboot reboot fastboot`.

```
[[ $(fastboot getvar is-userspace 2>&1) == *"is-userspace: yes"* ]] || echo "NOT IN FASTBOOTD — run: fastboot reboot fastboot, then rerun this block"
for cow in $(fastboot getvar all 2>&1 | grep -o 'is-logical:[^:]*-cow' | cut -d: -f2 | sort -u); do
  fastboot delete-logical-partition "$cow"
done
logical=$(fastboot getvar all 2>&1 |
  grep -o 'is-logical:[^:]*_a:yes' |
  sed -e 's/is-logical://' -e 's/_a:yes//' |
  sort -u | xargs)
echo "[$logical]"   # expect: system system_ext product vendor odm vendor_dlkm system_dlkm my_* ..., one line
[[ -n $logical ]] || echo "EMPTY LOGICAL SET — do not run the flash loops below"
slot=$(fastboot getvar current-slot 2>&1 | awk '/current-slot/{print $2}')
echo "slot=$slot logical-in-slot=$(fastboot getvar all 2>&1 | grep -c "is-logical:[^:]*_${slot}:yes")"   # count must equal the number of names above
```
If the count is lower than the number of names (the current slot is missing logical partitions), `fastboot set_active a` and rerun this block.

Flash rule, derived from this phone's own partition list (`logs/partitions.txt` from step 3.3) instead of a hand-kept skip list:
- **Logical** (in `$logical`) → current slot, in fastbootd (4.4).
- **Slotted physical** (the phone has `<name>_a`) → only eligible firmware from a compatible package may be flashed to both slots. A slot suffix does **not** override the protected-state list: never flash `qweslicstore_a/_b`. **Exception: `oplusstanvbk`** stays CN on PHB110 and has only the narrow documented modem repair. Its CN copy must match the unslotted CN `ocdt`; the OOS copy caused the recorded modem crash loop.
- **Unslotted** (no `_a`/`_b` on the phone) → **NEVER flash, restore, erase, or format per-device state**. On this phone these include EFS/IMEI (`persist`, `modemst1`, `modemst2`, `fsg`, `fsc`), NV backups (`oplusdycnvbk`, `oplusreserve1`–`5`, `mdm1oemnvbktmp`), board/calibration (`cdt`, `ocdt`, `ddr`, `dinfo`, `param`), security/keys (`devinfo`, `secdata`, `storsec`, `keystore`, `spunvm`, `qmcs`, `tzsc`, `uefivarstore`, `frp`, `apdp*`, `ssd`), and VM state (`vm-persist`, `vm-data`). Quarantine their backups under `backup/per-device-DO-NOT-RESTORE/`; if a payload contains them, leave the phone's copies untouched. RPMB must not be reset or reprovisioned as an experiment either.

**4.2 — dry run.** Prints the exact commands, touches nothing:

```
slotted=" $(sed -n 's/_a$//p' logs/partitions.txt | tr '\n' ' ') "
n_phys=0; n_log=0
for img in oos/*.img; do
  p=$(basename "$img" .img)
  [[ " $logical " == *" $p "* ]] && continue
  [[ $slotted == *" $p "* ]] || { echo "SKIP $p"; continue; }
  [[ $p == oplusstanvbk ]] && { echo "KEEP-CN $p"; continue; }
  echo "fastboot flash --slot=all $p $img"; ((n_phys++))
done
for p in $logical; do
  if [[ -f "oos/$p.img" ]]; then echo "fastboot flash $p oos/$p.img"; ((n_log++))
  else echo "kept (not in OOS payload): $p"; fi
done
echo "physical=$n_phys logical=$n_log"
```
For PHB110 with this OOS payload: `physical=31 logical=15`, one `KEEP-CN oplusstanvbk`, no `SKIP`, `kept` only for `my_company` and `my_preload`. If a `SKIP` appears for something you expected to be flashed, stop and check.

Logical partitions this phone has but the OOS payload doesn't ship (`my_company`, `my_preload`) are **kept**, not deleted: deleting them can stop OxygenOS booting if its first-stage fstab mounts them without `nofail`, while keeping them at worst leaves some ColorOS preload content. The authoritative check is the fstab in `oos/vendor_boot.img`'s ramdisk (unpack with `magiskboot unpack` or AOSP `unpack_bootimg`) — optional, since keeping is the safe default.

**4.3 — bootloader: physical, both slots.** Output goes to the screen and a log, so you can watch progress:

```
fastboot reboot bootloader
fastboot getvar is-userspace        # must say: no
for img in oos/*.img; do
  p=$(basename "$img" .img)
  [[ " $logical " == *" $p "* ]] && continue
  [[ $slotted == *" $p "* ]] || { echo "SKIP $p"; continue; }
  [[ $p == oplusstanvbk ]] && { echo "KEEP-CN $p"; continue; }
  fastboot flash --slot=all "$p" "$img"
done 2>&1 | tee logs/flash-physical.log
grep -Ei 'FAILED|error|SKIP' logs/flash-physical.log || echo "all physical flashes OK"
```
Continue only on `all physical flashes OK`. Don't reboot to Android if anything failed — firmware is now mixed; rerun the loop (rewriting is harmless) or ask.

**Known on PHB110:** `modem` is refused by both the bootloader and stock (OOS) fastbootd (`Writing 'modem_a' FAILED (remote: 'Operation not permitted')`), and `--slot=all` stops there so `modem_b` isn't attempted; every other physical partition writes fine. The phone keeps its CN modem, which works on OOS once `oplusstanvbk` is CN (below). Continue to 4.4.

**PHB110 modem crash loop: cause and fix (confirmed on a PHB110).**
- **Symptom:** OOS boots, but dmesg repeats every ~5 s `fatal error received: rflm_diag_error.cc:373:RFLM@sdmqlnkseq.cpp:1691 … Qlink(0) qsf_init failed at first bootup`. No IMEI, no signal.
- **Cause:** the OOS `oplusstanvbk` (OnePlus static NV backup) doesn't match the CN `ocdt`. `oplusstanvbk` has `_a`/`_b` slots and ships in the OOS payload, so a plain 4.3 flash replaces it. `ocdt` has no slots and is never flashed. The modem reads `oplusstanvbk` through remote storage while it starts ([linux-msm/rmtfs#33](https://github.com/linux-msm/rmtfs/pull/33)). OnePlus 11 converters found that `oplusstanvbk` and `ocdt` must come from the same variant ([XDA 4583321](https://xdaforums.com/t/maybe-a-proper-way-to-fix-issues-after-converting-color-to-oxygen.4583321/), read via `r.jina.ai` because XDA returns 403). The same fix is used for CN OnePlus 13/13T ([K58/fix-signal-oneplus13](https://github.com/K58/fix-signal-oneplus13)).
- **Fix:** keep the CN `oplusstanvbk`. The 4.2/4.3 loops skip it (`KEEP-CN`). If anything rewrites it (an OOS OTA, a full-firmware flash), restore it from the Task 3 dump, each slot from its own file:
  ```
  adb reboot fastboot
  fastboot flash oplusstanvbk_a backup/device/oplusstanvbk_a.img
  fastboot flash oplusstanvbk_b backup/device/oplusstanvbk_b.img
  fastboot reboot
  ```
  This brings the IMEIs back. Check: `adb shell su -c 'dmesg' | grep -c 'qsf_init failed'` prints 0.
- **Historical experiments, not instructions:** changing the modem image, `engineering_cdt`, and `modemst2` did not fix that recorded crash. The successful repair was the specific CN `oplusstanvbk` restoration. Do not repeat the `modemst2` experiment or restore EFS/security state.
- **Keep OOS automatic updates off.** An OTA rewrites `oplusstanvbk`, and the crash comes back.

**Notes for root work on this phone:**
- Multi-command root scripts go to `su` on stdin: `adb shell -T su <<'EOF' … EOF`. With `adb shell su -c '…; …'` the quotes are lost on the way through adb, the device's `sh` splits the commands, and only the first one runs as root.
- Do not bypass a partition's block-layer write protection to restore per-device/security-state images. Neither `dd` nor fastboot is an exception to the hard rules.
- Never `dd` boot-chain or anti-rollback-relevant partitions (`xbl*`, `abl`, `tz`, `hyp`, `aop*`, `devcfg`, `keymaster`, `uefi*`, `shrm`, `cpucp`, `qupfw`, `featenabler`).
- Keep per-device images in `backup/per-device-DO-NOT-RESTORE/`, separate from `backup/device/`, `backup/cn-stock/`, and `oos/`. Preserve dated snapshots; put disposable test outputs in `backup/scratch/`. Never use a `*.img` glob as a restore selection.

**4.4 — fastbootd: logical, current slot, then wipe.** Logical partitions go to the current slot only, unlike physical: they share `super`, which on this Virtual A/B phone holds one full set (~9.8 GB of OOS images) plus snapshot space, not two; a stock OTA also writes only one slot; and the LineageOS sideload in step 5 replaces the inactive slot's logical layout anyway.

```
fastboot reboot fastboot
fastboot getvar is-userspace        # must say: yes
for p in $logical; do
  if [[ -f "oos/$p.img" ]]; then fastboot flash "$p" "oos/$p.img"
  else echo "kept (not in OOS payload): $p"; fi
done 2>&1 | tee logs/flash-logical.log
grep -Ei 'FAILED|error' logs/flash-logical.log || echo "logical flashes OK"
```
Only after `logical flashes OK`:
```
fastboot -w
fastboot reboot
```

If a logical flash fails with "not enough space": `fastboot delete-logical-partition <name>_<the inactive slot letter>`, then rerun just that one `fastboot flash` line.

**Check:**
- Phone boots OxygenOS. Settings → About shows CPH2449 / Android 16.
- `*#06#` IMEIs still match `logs/imei-before.txt`. Place a call, send an SMS, confirm mobile data and WiFi.
- `adb shell getprop ro.build.display.id > logs/oos.txt`
- Remove any Google account now (clears FRP before you wipe into LineageOS).
- If it bootloops: **stop; do not reflash the entire ColorOS backup or replay section 4 against `backup/cn-stock/`.** Identify the failed partition and establish a compatible recovery set first. Never restore the protected per-device archive. Older boot-chain firmware can violate rollback requirements after newer firmware has booted; changing slots is not a guaranteed fallback when both slots were overwritten.

### 4.5 — Recovery: reset `super` and reinstall OxygenOS logical partitions

Use this when OxygenOS won't boot after a LineageOS attempt, or when `super` holds a broken layout. The `backup/device/` dump can't supply the layout — it excludes `super`, where all logical partitions live. Firmware and boot images must already be complete (4.3 log: ~63 `Writing … OKAY`, only `modem_a` refused).

**Correct layout on PHB110 / OOS 16** (from `fastboot getvar all` in fastbootd, and matching the OnePlus fastboot flasher `koaaN/Universal_Flasher`):
- Every logical partition is **slotted**: `<name>_a` / `<name>_b` (`has-slot:system:yes`, `is-logical:system_a:yes`). Snapshot leftovers are `<name>_a-cow` / `<name>_b-cow`. Never create unslotted names — first-stage init looks for `<name>_<slot>`.
- 17 names: `my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_stock odm product system system_dlkm system_ext vendor vendor_dlkm`. The OOS payload ships 15; `my_company`/`my_preload` only exist in the CN package.
- `super` is `0x3F1B6F000` (~15.8 GiB). One full OOS set on slot `a` is ~9.8 GB, so **two full sets don't fit**. The active slot gets full-size partitions; the other slot gets **empty (0-byte) entries**, exactly as the factory `META/super_def.*.json` defines them (Virtual A/B fills it later via snapshots, e.g. the LineageOS sideload). Each group (`qti_dynamic_partitions_a`/`_b`) may use all of `super` minus metadata (16936005632 bytes).

**Broken-layout signature:** `getvar all` showing full-size `_b` copies (e.g. `partition-size:my_product_b:0xACB50000`) and some `_b` names missing (`system_b`, `system_ext_b`, `vendor_b`, `vendor_dlkm_b`) means a dual-slot flash filled `super`. Missing `my_company_*`/`my_preload_*` on both slots means they weren't recreated.

1. **Use LineageOS recovery's fastbootd** (full AOSP fastbootd; stock OOS fastbootd may lack `create-logical-partition`). If `recovery` doesn't currently hold LineageOS recovery, flash it from the bootloader (one flash per session on this phone): `fastboot flash recovery recovery.img`. Then boot recovery → Advanced → **Enter fastboot**.
   ```
   fastboot getvar is-userspace            # MUST say: yes — stop otherwise
   fastboot getvar current-slot            # must say: a  (else: fastboot set_active a)
   fastboot snapshot-update cancel         # harmless if nothing is pending
   ```
2. **Probe** that this fastbootd can create and delete — if this fails, delete nothing and stop:
   ```
   fastboot create-logical-partition probe_a 4096 && fastboot delete-logical-partition probe_a && echo "create/delete OK"
   ```
3. **Check every image is present** (15 from `oos/`, `my_company`/`my_preload` from `backup/cn-stock/`):
   ```
   names="my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_stock odm product system system_dlkm system_ext vendor vendor_dlkm"
   for p in $names; do
     img="oos/$p.img"; [[ -f $img ]] || img="backup/cn-stock/$p.img"
     [[ -f $img ]] && echo "$p <- $img ($(stat -c %s "$img") bytes)" || echo "NO IMAGE: $p"
   done
   ```
   `NO IMAGE` for `my_company`/`my_preload` means they'll be left out (OxygenOS's payload doesn't ship them); any other `NO IMAGE` → stop.
4. **Delete** every logical partition on both slots, plus snapshot leftovers. Errors for ones that don't exist are expected:
   ```
   for p in $names; do for s in _a _b _a-cow _b-cow; do fastboot delete-logical-partition "$p$s"; done; done
   fastboot getvar all 2>&1 | grep -c 'is-logical:.*:yes'      # must be 0
   ```
5. **Recreate**: `_a` at its `super_def.*.json` size (raw size; a sparse image file is smaller) and flashed; `_b` at 0 bytes, never flashed. Create `_a` at the real size rather than growing an empty partition — host-side auto-grow depends on `is-logical`:
   ```
   def=$(ls oos/META/super_def.*.json backup/cn-stock/META/super_def.*.json layout/op11-super_def.json 2>/dev/null | head -1)
   for p in $names; do
     img="oos/$p.img"; [[ -f $img ]] || img="backup/cn-stock/$p.img"; [[ -f $img ]] || { echo "skip $p"; continue; }
     size=$([[ -n $def ]] && jq -r --arg n "${p}_a" '.partitions[] | select(.name == $n) | .size // empty' "$def")
     fastboot create-logical-partition "${p}_a" "${size:-$(stat -c %s "$img")}"
     fastboot create-logical-partition "${p}_b" 0
     fastboot flash "${p}_a" "$img"
   done 2>&1 | tee logs/flash-logical.log
   grep -Ei 'FAILED|error' logs/flash-logical.log || echo "logical flashes OK"
   fastboot getvar all 2>&1 | grep -E 'is-logical:.*:yes' | sort    # 15 _a + 15 _b (17 each with my_company/my_preload)
   ```
   `my_product` and `my_stock` print `Invalid sparse file format at header magic` — harmless: fastboot splits raw images bigger than `max-download-size` (`0x10000000`) itself. Check for `Writing … OKAY`.
6. Only on `logical flashes OK`:
   ```
   fastboot -w
   fastboot reboot
   ```
   Confirm OxygenOS boots and `*#06#` matches before starting Task 5. LineageOS recovery stays in `recovery`; OxygenOS doesn't need its own recovery to boot, and Task 5 needs LineageOS's anyway.

**What actually restored boot on PHB110** (after a failed LineageOS attempt; phone went straight to the bootloader every boot):
1. **`my_company` / `my_preload` recreated.** They're factory-only — no OTA (global or CN) ships them — and they had been deleted. Source: a PHB110 factory/9008 package (e.g. daxiaamu's OnePlus 11 folder), not an OTA. Create `_a` at image size + `_b` at 1 byte, flash `_a`.
2. **Physical partitions reflashed from LineageOS recovery's fastbootd**, skipping `recovery`. Slot `a` still had LineageOS's `boot`/`dtbo`/`init_boot`/`vbmeta`/`vendor_boot` from Task 5; an earlier reflash had written nothing (`Could not check if partition … has slot` = phone not answering). Verify with `grep -c '^Writing.*OKAY' logs/restore-physical.log` ≈ 62 before moving on.
3. **Data formatted in LineageOS recovery** (Factory Reset → Format data). `fastboot -w` in fastbootd only erases `userdata`/`metadata` (`not automatically formatting`).
4. `fastboot --set-active=a` from the bootloader (resets slot `a`'s retry/unbootable flags), then reboot.

---

## 5. Install LineageOS 24.0

Requires OOS to already be on Android 16 latest patch (done in step 4). Follow https://wiki.lineageos.org/devices/salami/install/ if anything here is unclear.

1. Download from https://download.lineageos.org/devices/salami: `boot.img`, `dtbo.img`, `init_boot.img`, `vbmeta.img`, `vendor_boot.img`, `recovery.img`, `super_empty.img`, `lineage-*-salami-signed.zip`, optionally a GApps arm64 zip. Before step 2, while still on OOS: place a call, send an SMS and use mobile data once (this provisions IMS, per wiki prerequisite 5), then remove all Google accounts.
2. `adb reboot bootloader`, then flash one image per bootloader session: during this step a flash only worked as the first command after a reboot to the bootloader. Later ones failed with `partition size: 0`, `Requested download size is more than max allowed` or `No such device`, and the phone crashed to a black screen (below). Wait for `OKAY` before each next line; if one fails, `fastboot reboot bootloader` and rerun just that flash.
   ```
   fastboot flash boot boot.img
   fastboot reboot bootloader
   fastboot flash dtbo dtbo.img
   fastboot reboot bootloader
   fastboot flash init_boot init_boot.img
   fastboot reboot bootloader
   fastboot flash vbmeta vbmeta.img
   fastboot reboot bootloader
   fastboot flash vendor_boot vendor_boot.img
   fastboot reboot bootloader
   fastboot flash recovery recovery.img
   ```
   **Black screen, nothing responds:** check `dmesg` on the host. `idVendor=05c6, idProduct=900e` (`QUSB_BULK_CID:…`, Qualcomm CDMA Technologies MSM) is Qualcomm crash-dump mode: the phone hit a fatal error and is waiting for a host to collect a RAM dump. Not a brick. Unplug USB, hold Power + Volume Down ~15 s until it restarts into the bootloader, then rerun the flash that failed. If it shows `05c6:9008` (EDL) instead, or keeps returning to `900e`, stop: that's the EDL last resort from the top of this guide.
3. Volume keys → "Recovery" in the bootloader menu. Confirm you see the LineageOS recovery logo — if not, you booted the wrong recovery, go back to step 2.
   - **Modem on LineageOS:** the sideload writes LineageOS's bundled OOS 16.0.5.1301 `modem` to its slot (see the correction below). Confirmed working on a PHB110 together with the CN `oplusstanvbk`: IMEI, calls and data all fine on LineageOS.
   - **Don't `wipe-super` right before sideloading.** That was tried once: `super` held unslotted names plus `-cow` leftovers and the sideload failed with "not enough space"; after `wipe-super` + sideload, the phone went straight to the bootloader every boot (cause not established). What worked: rebuild OxygenOS's `<name>_a`/`<name>_b` layout with 4.5 (`scripts/40-oos-super.sh`), boot OxygenOS once, then sideload. Unslotted logical names are a broken state on OnePlus ([Droidwin, OnePlus 8T](https://droidwin.com/how-to-delete-and-create-logical-partition-on-oneplus-8t/); [koaaN/Universal_Flasher](https://github.com/koaaN/Universal_Flasher) creates only `_a`/`_b`). `fastboot boot <img>` is not a usable test on this phone either: the OnePlus 11 bootloader refuses or ignores it.
4. In recovery: Factory Reset → Format data/factory reset.
5. Apply update → Apply from ADB → on the host: `adb -d sideload lineage-*.zip`.
   - The sideload installs to the **inactive** slot and switches to it. LineageOS's payload carries every boot-chain image (`boot dtbo init_boot recovery vbmeta vbmeta_system vbmeta_vendor vendor_boot`) and exactly **7 logical partitions** (`odm product system system_dlkm system_ext vendor vendor_dlkm`, per `BOARD_ONEPLUS_DYNAMIC_PARTITIONS_PARTITION_LIST` in `LineageOS/android_device_oneplus_sm8550-common`, branch `lineage-24.0`). The ten OxygenOS `my_*` partitions aren't part of LineageOS and don't exist on its slot.
   - The zip also ships the full firmware set (`abl aop aop_config bluetooth cpucp devcfg dsp engineering_cdt featenabler hyp imagefv keymaster modem oplus_sec qupfw shrm splash tz uefi uefisecapp xbl xbl_config xbl_ramdump`) from **CPH2449_16.0.5.1301(EX01)** (`android_device_oneplus_salami/proprietary-firmware.txt`), but **not** `oplusstanvbk`. Every sideload or LineageOS OTA rewrites those on the target slot; the CN `oplusstanvbk` stays.
   - Optional check: Advanced → Enter fastboot → `fastboot getvar current-slot` and `fastboot getvar all 2>&1 | grep -o "is-logical:[^:]*_$(fastboot getvar current-slot 2>&1 | awk '/current-slot/{print $2}'):yes"` → exactly those 7.
6. If installing GApps: still in recovery, Apply from ADB again, sideload the GApps zip (accept "signature verification failed" — expected, it's unsigned). Must happen before first boot.
7. Reboot system now.

**Check:**
- First boot finishes within ~15 minutes. Settings → About shows the LineageOS version.
- `*#06#` IMEIs still match `logs/imei-before.txt`.
- Calls, SMS, mobile data, WiFi, Bluetooth, camera, fingerprint all work.
- `adb shell getprop ro.lineage.version` returns a value.

---

## 6. (Later) Updating firmware after you're already on LineageOS

Usually not needed: every LineageOS update already rewrites the bundled CPH2449 firmware (incl. `modem`, `xbl`, `tz`) on the slot it installs to, so run `scripts/60-checks.sh` after each update. Flash manually only if the wiki's required baseline is newer than what LineageOS bundles. Per https://wiki.lineageos.org/devices/salami/fw_update/:

1. Get a newer **Android 16** full OOS OTA, extract with `payload-dumper-go`.
2. Boot into LineageOS recovery → Advanced → **Enter fastboot** (not "Reboot to bootloader" — must be this specific menu entry).
3. Flash the firmware-only partitions, all to both slots:
   ```
   fastboot flash --slot=all abl abl.img
   fastboot flash --slot=all aop_config aop_config.img
   fastboot flash --slot=all aop aop.img
   fastboot flash --slot=all bluetooth bluetooth.img
   fastboot flash --slot=all cpucp cpucp.img
   fastboot flash --slot=all devcfg devcfg.img
   fastboot flash --slot=all dsp dsp.img
   fastboot flash --slot=all engineering_cdt engineering_cdt.img
   fastboot flash --slot=all featenabler featenabler.img
   fastboot flash --slot=all hyp hyp.img
   fastboot flash --slot=all imagefv imagefv.img
   fastboot flash --slot=all keymaster keymaster.img
   fastboot flash --slot=all modem modem.img
   fastboot flash --slot=all oplus_sec oplus_sec.img
   # oplusstanvbk: NOT on PHB110. Keep the CN copy; the OOS one crash-loops the modem (see 4.3).
   fastboot flash --slot=all qupfw qupfw.img
   fastboot flash --slot=all shrm shrm.img
   fastboot flash --slot=all splash splash.img
   fastboot flash --slot=all tz tz.img
   fastboot flash --slot=all uefi uefi.img
   fastboot flash --slot=all uefisecapp uefisecapp.img
   fastboot flash --slot=all xbl_config xbl_config.img
   fastboot flash --slot=all xbl_ramdump xbl_ramdump.img
   fastboot flash --slot=all xbl xbl.img
   ```
4. The version shown in Settings on both stock and LineageOS won't reflect this update — that's expected per the wiki, not a sign it failed.

---

## 7. After LineageOS is running

**Network in China and abroad.** `scripts/70-network.sh` (plain adb, no root). It replaces Google's blocked probes with Huawei hicloud (primary) + Xiaomi (fallback) `generate_204`, both reachable in China and abroad, plus Cloudflare as a last-resort fallback for abroad, and sets NTP to `ntp.aliyun.com|pool.ntp.org`. Survives OTAs; redo after a factory reset.

**Chinese keyboard.** FOSS: [fcitx5-android](https://f-droid.org/packages/org.fcitx.fcitx5.android) (offline pinyin/shuangpin/wubi; Rime plugin available). Best prediction: iFlytek [srf.xunfei.cn](https://srf.xunfei.cn/) or Sogou, with cloud input off and network/contacts/mic permissions denied ([Citizen Lab](https://citizenlab.ca/research/vulnerabilities-across-keyboard-apps-reveal-keystrokes-to-network-eavesdroppers/) found keystroke leaks in cloud IMEs). Enable: Settings → System → Languages & input → On-screen keyboard.

**Updates without losing anything.**
- Nightlies: Settings → System → Updater. Keeps data and GApps. Each update rewrites the bundled firmware on the target slot, not `oplusstanvbk`. Run `scripts/60-checks.sh` afterwards.
- Next major version: `adb -d reboot sideload`, then `adb -d sideload <zip>` (no wipe; GApps zip again before first boot). See [wiki upgrade](https://wiki.lineageos.org/devices/salami/upgrade/).
- Firmware updates (section 6): never flash `oplusstanvbk`.
- Clean reinstall or new phone: Seedvault (Settings → System → Backup) plus in-app exports for Signal/WhatsApp, 2FA and password manager. Keystore-bound and banking apps need re-login.

**UI lag.** LineageOS builds its own `vendor`/`odm` from OOS 16.0.5.1301 blobs; no ColorOS partition is used, and keeping one wouldn't help. Run `scripts/80-perf-diag.sh` while it lags, then check, in order:
1. Nightly date: builds before ~2026-09-28 lack the perf-HAL boost fix ([commit](https://github.com/LineageOS/android_device_oneplus_sm8550-common/commit/8ac51aeef83a5083934de07772f907297a378c47)).
2. Settings → Display → Smooth display (120 Hz).
3. Freshly installed or updated: `adb shell cmd package bg-dexopt-job`, then leave it idle on the charger.
4. Thermal zones over ~45 °C during the lag = throttling.

**Root: APatch** (patches `boot`, never `init_boot`; runs Magisk-format modules). Install: APatch app → tap the "KernelPatch: not installed" card → Patch → select the installed build's stock `boot.img` → set the SuperKey (8–63 random chars; it's the password for kernel root, nothing generates it) → `fastboot flash boot apatch_patched_*.img` → open the app, enter the same SuperKey. Leave "embed KPM" empty. Each LineageOS update boots the other slot without root or modules: Updater → Install → reboot → patch the new build's `boot.img` → `fastboot flash boot <patched>` → reboot. Rescue from a bad module: `fastboot flash boot <the installed build's boot.img>` (unpatched). Less detectable alternative: KernelSU Next LKM + SUSFS (patches `init_boot`; untested on the LineageOS kernel). Play Integrity: BASIC is realistic. Never relock.

**OnePlus camera (experimental).** `scripts/90-oplus-camera-module.sh` builds `build/oplus-camera/OplusCamera-module.zip` from `oos/` (OplusCamera, native libraries and camera SDK jars). The OOS framework wrapper DEX is appended **only to the camera's optional SDK jar**, not LineageOS's boot classpath. `OplusAppPlatform` is omitted because its OEM-signed `android.uid.system` cannot join LineageOS's platform UID. Install through KernelSU Manager → Modules and reboot; a mount metamodule such as Hybrid Mount is required. In KernelSU's `com.oplus.camera` App Profile disable **Umount modules** without granting root: otherwise the process cannot read its mounted APK and crashes before app initialization. That per-app setting removed the first crash; the new SDK jar addresses a subsequent missing-class exception, but has not been runtime-tested. Further ColorOS framework dependencies may still crash, and portrait/night modes were broken even in a crDroid port ([XDA](https://xdaforums.com/t/oplus-camera-and-custom-roms.4657206/)). If unstable, disable the module and reboot; a GCam port is the fallback ([XDA OnePlus 11 GCam](https://xdaforums.com/t/gcam-for-op-11.4553669/)).

---

## 8. Optional return to PHB110 ColorOS with OplusEdlTool v2

**Not yet cleared to flash.** This is a conditional recovery path, not an attestation repair. If the bootloader and fastbootd work, a reviewed full PHB110 ColorOS 16 package avoids the Android 13 downgrade; do not run the OOS-specific scripts in section 4 unchanged against the CN package. The [open-source OplusEdlTool v2](https://github.com/salokrwhite/OplusEdlTool) supports selected partitions and assembling `super`. The [newer v3/v4 downloads](https://static-tcdn.anteasy.com/xasdun/upload-log/oet-upload.html) are not described by v2's source. Do not assume their selection or patch behavior matches.

### Before entering EDL: all gates must pass

1. Preserve user data separately: this route can require formatting `userdata`. Keep the existing private backup untouched and **outside** the flasher's input directory. `../oneplus/backup/device` aliases `../oneplus/backup/cn-stock`: they are not two backups, and neither is a restore set. Never feed either path to OplusEdlTool.
2. Use the **PHB110 domestic**, not CPH2449, package. The downloaded `/games/oneplus/PHB110domestic_11_A.29_2023101920110124.zip` is 9,832,603,307 bytes; its MD5 `e7c1df282cb26c9653d3b1aa3f391280` matches the [distributor's listing](https://androidfilehost.com/?fid=16385555061192796021), which does not establish authenticity. Its `IMAGES/` contains `prog_firehose_ddr.elf`, two `DigestsToSign_*.bin.mbn` files, `sign_client`, rawprogram XMLs and patch XMLs; no detached signature `.bin` was identified in the archive. OplusEdlTool v2 requires **programmer + matching digest + signature** to enter Firehose. The included `sign_client` does not prove a valid signature can be obtained. **Stop before entering EDL until this exact PHB110 loader triplet is independently verified**; do not substitute a programmer from another model.
3. Have the **PHB110 CN upgrade packages before downgrading**. A [ColorOS 16 full-package listing](https://yun.daxiaamu.com/OnePlus_Roms/%E4%B8%80%E5%8A%A0OnePlus%2011/ColorOS%20PHB110_16.0.5.701(CN01)%20H.11/) exists, but an accepted A.29→16 path has not been verified. Check each OTA's `META-INF/com/android/metadata`: `pre-device` must match the stock A.29 build's `ro.product.device` (which need not equal the PHB110 model name); an incremental package's `pre-build`/`pre-build-incremental` must match the installed build. Do not assume a direct jump to 16.
4. Audit **all** effective writes from this exact archive offline: rawprogram entries, GPT writes, `patch*.xml` sector edits and any tool-generated `super`. Whitelist only verified stock software/firmware and a complete compatible `super`; never use Select All or whole-LUN flashing. Exclude every per-device/security-state partition named in the hard rules above, including `persist`, EFS, `ocdt`, `keystore`, `secdata`, `tzsc`, `storsec`, `qweslicstore_a/_b`, and RPMB. Preserve this phone's CN `oplusstanvbk_a/_b` with its CN `ocdt`. A `persist` prompt and **Protect LUN5** do not protect the other LUNs. Never select Default NV, erase/reset secure storage, or restore images from the private backup.
5. **Critical v2 caveat:** `patch0.xml` and `patch5.xml` each contain 26 patch entries; their target sectors have not been audited. Both Start Flash and Write Selected can apply `patch*.xml` for the loaded rawprogram files *regardless of unchecked partition rows* ([v2 code](https://raw.githubusercontent.com/salokrwhite/OplusEdlTool/main/MainWindow.axaml.cs)). Do not press either button unless every patch is audited and cannot touch excluded state. Skipping all patches is not automatically safe either: the package might require a GPT/bootability patch. If the necessary patches cannot be constrained, **stop**; no verified safe click-through exists for this package yet.

### EDL entry and conditional flashing

With the tool, images and approved write plan ready, a booted phone can try `adb reboot edl`. Alternatively, power it off, disconnect USB, then hold **Volume Up + Volume Down + Power while plugging in USB**, as described in the [OP11 EDL thread](https://xdaforums.com/t/op11-edl-downloadtool-to-restore-your-device-to-oxygenos-coloros.4607995/). The screen stays black. Confirm **Qualcomm HS-USB QDLoader 9008** (`05c6:9008`); `05c6:900e` is crash-dump mode, not EDL. Entering 9008 does not itself flash anything.

On Windows, v2's documented flow is: select the matching programmer/digest/signature, enter Firehose, load the PHB110 ROM folder or OFP, select **None** rather than its default file-present rows, then select only the audited stock software entries and complete `super`. Cross-check the actual selected rows, LUNs, GPT and patch operations against the approved write plan **before** Start Flash/Write Selected. An unverified loader, unreviewed patch, automatic protected-state write, or unexpected tool output is a stop condition. There is no tested PHB110 write plan in this manual; do not treat this paragraph as authorization to click Start.

After a successful, reviewed stock-software flash, leave the bootloader **unlocked**. Boot ColorOS 13, perform its required userdata format if necessary, verify model/build, `super` layout, IMEIs, calls, data, Wi-Fi, fingerprint and camera. Then use the stock updater with signed **PHB110 CN** full/incremental OTAs accepted by the currently installed build, checking the next package's preconditions at each step. A [full OTA may bridge builds but an incremental OTA needs its exact source build](https://source.android.com/docs/core/ota/tools); online update availability is not guaranteed. Stop at the first rejected update rather than force an incompatible one. Reaching stock ColorOS 16 does not prove that default KeyMint attestation `-49` is fixed, and neither EDL nor OTA restores factory secure state.

## Why these specific risks matter

| Risk | Where it's handled |
|---|---|
| Firmware downgrade CN→OOS | Step 3.4's go/no-go on Android major + security-patch date — the real gate; EDL rescue exists for this device but needs an EDL cable/test-point entry and the exact firehose package, so don't treat it as a routine fallback |
| `super` out of space in fastbootd | Step 4 deletes `-cow` snapshots up front; "not enough space" on a logical flash → delete the inactive slot's copy, retry |
| Slots diverge → bootloop | `--slot=all` on every slotted physical partition in step 4 |
| Payload or full restore overwrites per-device state | Absolute no-write rule for unslotted EFS/security/calibration partitions and RPMB; quarantine images under `backup/per-device-DO-NOT-RESTORE/`. Only the specific slotted CN `oplusstanvbk` modem fix is documented here. |
| Modem crash loop / no IMEI on OOS | OOS `oplusstanvbk` doesn't match CN `ocdt`. Restore CN `oplusstanvbk_a`/`_b` from `backup/device/` (4.3), and keep OOS OTAs off |
| IMEI/EFS or attestation failure | Stop and collect read-only evidence. **Never restore any image from `backup/device/` except the documented CN `oplusstanvbk_a/_b` modem fix. Never restore protected per-device/security-state images or reset RPMB.** Retain private backups for authorized-service assessment; there is no verified local identity-reset procedure for this phone. |
| VoLTE/VoWiFi never provisioned | Checked on CN stock in step 2.1, re-checked on OOS in step 4 |
| Relocking the bootloader | Never do it |
| FRP lock after LineageOS install | Google account removed from OOS in step 4 |
