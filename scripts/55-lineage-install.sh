#!/usr/bin/env bash
# Task 5 steps 2-5: flash LineageOS boot images + recovery, then sideload.
# Precondition: OxygenOS (>= 16.0.5.1301, the firmware LineageOS bundles) boots with IMEI, Google accounts removed,
# super in the _a/_b layout (scripts/40-oos-super.sh). Flashes one image per bootloader session, which also
# works when fastboot is in a broken state (README, section 4).
source "$(dirname "$0")/lib.sh"
(cd lineage && sha256sum -c --quiet SHA256SUMS) || die "lineage/ incomplete; run scripts/50-lineage-download.sh"
zip=$(ls lineage/lineage-*-"$DEVICE"-signed.zip)

adb reboot bootloader 2>/dev/null || true
fastboot wait-for-device 2>/dev/null || sleep 10
need_bootloader
for p in boot dtbo init_boot vbmeta vendor_boot recovery; do
  fastboot flash "$p" "lineage/$p.img" || die "$p failed. If the screen is black: hold Power+Vol Down 15 s, rerun"
  fastboot reboot bootloader; sleep 8
done

cat <<'EOF'
On the phone: bootloader menu -> Recovery (LineageOS logo).
  Factory Reset -> Format data/factory reset, back to main menu.
  Apply update -> Apply from ADB.
EOF
adb wait-for-sideload
adb -d sideload "$zip" || true   # 'failed to read command: Success' at 47% is normal
cat <<'EOF'
Optional: sideload GApps now (Apply from ADB again; answer Yes at signature warning).
Then: Reboot system now. First boot up to 15 min. Afterwards: scripts/60-checks.sh
EOF
