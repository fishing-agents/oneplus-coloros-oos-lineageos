# OnePlus 11 (salami): CN ColorOS → OxygenOS → LineageOS

Do these in order. Each step says what to run and what you should see. Stop and ask if a check doesn't match — don't push through an error on this device. There is a public EDL (9008) rescue route for this device (OPLUS EDL Tool / `bkerler/edl` + a matching firehose package), but it needs opening the phone or an EDL cable/test-point entry and the exact firehose file for PHB110 — treat it as a last resort you'd have to research mid-emergency, not a safety net. The backups in this guide are the real protection.

Host tools: `scripts/00-host-tools.sh` downloads `adb`/`fastboot` (platform-tools ≥ 35) and `payload-dumper-go` into `tools/` (gitignored). The scripts put `tools/platform-tools` on `PATH` themselves; for hand-typed commands, add it yourself or prefix `tools/platform-tools/`.

**Run every command block in `bash`, not zsh.** zsh doesn't word-split unquoted variables, so loops like `for p in $logical` run once over the whole string and silently flash nothing. If your login shell is zsh, type `bash` first.

**Hard rules for the whole procedure:**
- Never run `fastboot flashing lock`, ever, on this phone.
- Never flash OOS firmware older (lower Android version or earlier security-patch date) than what's currently on the phone. EDL rescue exists for this device but is nontrivial (cable/test-point + exact firehose package) — don't rely on it as the fallback for a bad flash.
- Keep battery above 60%, direct USB port, no hub.


**Scripts** (`scripts/`, run from the repo root with bash; each one prints what it will do and stops on errors):

| Script | Step | Mode |
|---|---|---|
| `00-host-tools.sh` | host setup | host |
| `10-backup-device.sh` | 3.3: dump every partition + SHA256SUMS, checks the irreplaceable ones (`oplusstanvbk_a/_b`, EFS, `persist`) | Android, rooted adb |
| `20-extract.sh <cn.zip> <oos.zip>` | 3.1 + 3.4: extract both OTAs; refuses OOS older than CN or than 16.0.5.1301 | host |
| `50-lineage-download.sh` | 5.1: newest build + `super_empty.img`, verified against the official API hashes | host |
| `30-oos-firmware.sh` | 4.3: slotted firmware from `oos/` to both slots; keeps CN `oplusstanvbk`, own `modem`, LineageOS `recovery` | bootloader, or LineageOS-recovery fastbootd |
| `40-oos-super.sh` | 4.5: wipe `super`, recreate `<name>_a` (super_def size) + `<name>_b` (0 bytes), flash | LineageOS-recovery fastbootd |
| `45-restore-stanvbk.sh` | put the CN `oplusstanvbk` back (after an OOS OTA or full-firmware flash) | fastbootd |
| `55-lineage-install.sh` | 5.2–5.7: boot images one per bootloader session, recovery, sideload | bootloader → recovery |
| `60-checks.sh` | IMEI-related checks: `qsf_init` crash count, `oplusstanvbk` still CN | Android |
| `70-network.sh` | captive-portal probes + NTP that work in China and abroad (section 7) | Android |
| `80-perf-diag.sh` | UI-lag diagnostics (section 7) | LineageOS, rooted debugging |
| `85-driver-check.sh` | GPU/display driver and vendor HAL health (section 7) | LineageOS; root for dmesg |
| `90-oplus-camera-module.sh` | OnePlus camera as an APatch/Magisk module, built from `oos/` (section 7) | host |

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

**Note on what backs up what:** step 1 below extracts the downloaded CN **zip** — it never touches the phone, it's just the stock images as reference/restore material. Step 3 is the real phone backup: it `dd`s every partition straight off the live, rooted device. If the phone's current state differs from stock (previous mods, OEM A/B drift, etc.), step 3 is what actually captures that — step 1 only gives you a generic "known good CN build" to fall back to.

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
3. This is the actual device backup — capture the partition list, then dump everything except `userdata`/`super` and the whole-disk `sda`–`sdf` entries straight off the live phone. Safe to rerun: partitions already dumped at full size are skipped, partial dumps are redone.
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
   **Check:** no `MISSING:` lines; every `backup/device/*.img` is non-empty (`persist.img` should be tens of MB). Copy the whole `backup/` folder to a second disk before continuing.
   - **`super` is excluded above deliberately** — it's ~12–16 GB and normally reconstructable from `backup/cn-stock/*.img` (step 1). **Required instead whenever you don't have an exact-build-match `backup/cn-stock/`** (so it isn't a true match for this phone's current `system`/`vendor`) — which is the likely case given CN ColorOS archival is thin: `adb exec-out "su -c 'dd if=/dev/block/by-name/super bs=4M 2>/dev/null'" > backup/device/super.img`. Restore later via fastbootd: `fastboot flash super backup/device/super.img`.
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
- **Slotted physical** (the phone has `<name>_a`) → `--slot=all`, in the bootloader (4.3). OTAs replace these, so overwriting them is expected. **Exception: `oplusstanvbk`** stays CN on PHB110. It has to match the unslotted CN `ocdt`, and the OOS copy crash-loops the modem (see "PHB110 modem crash loop" below).
- **Unslotted** (no `_a`/`_b` on the phone) → **never flashed**. On this phone that's the per-device state: EFS/IMEI (`persist`, `modemst1`, `modemst2`, `fsg`, `fsc`), NV backups (`oplusdycnvbk`, `oplusreserve1`–`5`, `mdm1oemnvbktmp`), board/calibration (`cdt`, `ocdt`, `ddr`, `dinfo`, `param`), security/keys (`devinfo`, `secdata`, `storsec`, `keystore`, `spunvm`, `qmcs`, `tzsc`, `uefivarstore`, `frp`, `apdp*`), and the rest. If one turns up in the payload, it's reported and left alone.

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
- **Ruled out by testing:** the modem image (CN modem, hash-identical to the dump, still crashed with the OOS `oplusstanvbk`), `engineering_cdt` (CN and OOS copies both fine; keep the OOS one to match the installed build), and the modem storage (`modemst1`/`modemst2`/`fsg`/`fsc` hashes matched the dump; swapping `modemst2` changed nothing).
- **Keep OOS automatic updates off.** An OTA rewrites `oplusstanvbk`, and the crash comes back.

**Notes for root work on this phone:**
- Multi-command root scripts go to `su` on stdin: `adb shell -T su <<'EOF' … EOF`. With `adb shell su -c '…; …'` the quotes are lost on the way through adb, the device's `sh` splits the commands, and only the first one runs as root.
- OPLUS keeps physical partitions read-only at the block layer. For a root `dd` restore, run `blockdev --setrw <dev>` first and `blockdev --setro <dev>` after. Fastboot flashes aren't affected.
- Never `dd` boot-chain or anti-rollback-relevant partitions (`xbl*`, `abl`, `tz`, `hyp`, `aop*`, `devcfg`, `keymaster`, `uefi*`, `shrm`, `cpucp`, `qupfw`, `featenabler`).
- Keep `backup/device/` exactly as dumped in Task 3. Put test snapshots in `backup/scratch/`, because the `*.img` globs in the Task 3 dump loop and in the restore row of the risks table would otherwise pick them up.

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
- If it bootloops: redo this whole section pointing at `backup/cn-stock/` instead of `oos/` to get back to a known-good state, then figure out what went wrong before retrying. (`fastboot set_active other` won't help — both slots already got the same firmware.) **Anti-rollback risk:** this flashes older CN `xbl`/`abl`/`tz`. If the OOS boot chain already raised the fused rollback counter, that hard-bricks the phone. Use it only for a bootloop right after 4.3, never as a diagnostic step once OOS has booted.

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
   def=$(ls oos/META/super_def.*.json backup/cn-stock/META/super_def.*.json 2>/dev/null | head -1)   # empty: image sizes
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
1. **`my_company` / `my_preload` recreated.** They're factory-only — no OTA (global or CN) ships them — and they had been deleted. Source: a PHB110 factory/9008 package (e.g. daxiaamu's OnePlus 11 folder), not an OTA. Create `_a` at its super_def size + `_b` at 0 bytes, flash `_a`.
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

**OnePlus camera (experimental).** `scripts/90-oplus-camera-module.sh` builds `build/oplus-camera/OplusCamera-module.zip` from `oos/` (OplusCamera + OplusAppPlatform as priv-apps, ~35 OPLUS libs plus whatever they link against from `my_product`, OPLUS framework jars declared as shared libraries, a priv-app permission whitelist). Reads only the needed files from the images (needs erofs-utils ≥ 1.7). Install in APatch → Modules. Expect partial function: even built into crDroid, portrait and night mode were broken ([XDA](https://xdaforums.com/t/oplus-camera-and-custom-roms.4657206/)). The script warns about missing files, a platform `sharedUserId` or unresolved `<uses-library>`, each of which stops the app installing. Fallback: a GCam port ([XDA OnePlus 11 GCam](https://xdaforums.com/t/gcam-for-op-11.4553669/)).

---

## Why these specific risks matter

| Risk | Where it's handled |
|---|---|
| Firmware downgrade CN→OOS | Step 3.4's go/no-go on Android major + security-patch date — the real gate; EDL rescue exists for this device but needs an EDL cable/test-point entry and the exact firehose package, so don't treat it as a routine fallback |
| `super` out of space in fastbootd | Step 4 deletes `-cow` snapshots up front; "not enough space" on a logical flash → delete the inactive slot's copy, retry |
| Slots diverge → bootloop | `--slot=all` on every slotted physical partition in step 4 |
| Payload overwrites per-device state | Step 4 only flashes partitions this phone has as `_a`/`_b`; unslotted ones (EFS, NV backups, calibration, keys) are never written. Exception handled explicitly: slotted `oplusstanvbk` is kept CN (`KEEP-CN`) |
| Modem crash loop / no IMEI on OOS | OOS `oplusstanvbk` doesn't match CN `ocdt`. Restore CN `oplusstanvbk_a`/`_b` from `backup/device/` (4.3), and keep OOS OTAs off |
| IMEI/EFS lost | Restore from `backup/device/*.img` via `dd` under root — this is the live-device backup, not the zip extraction |
| VoLTE/VoWiFi never provisioned | Checked on CN stock in step 2.1, re-checked on OOS in step 4 |
| Relocking the bootloader | Never do it |
| FRP lock after LineageOS install | Google account removed from OOS in step 4 |
