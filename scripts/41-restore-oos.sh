#!/usr/bin/env bash
# One command from the bootloader (fastboot mode): put back OxygenOS on a phone that has LineageOS recovery.
#   1. bootloader: flash lineage/recovery.img to both slots (keeps a fastbootd that can create partitions)
#   2. reboot to that recovery's fastbootd
#   3. 30-oos-firmware.sh: firmware (conversion set from $FW_SRC, rest from backup/device)
#   4. 40-oos-super.sh: wipe super, recreate the factory layout, flash logical _a
# LineageOS recovery stays installed throughout; OxygenOS boots with it (the OTA updater replaces it later).
# usage: scripts/41-restore-oos.sh [-n|--dry-run]
source "$(dirname "$0")/lib.sh"
DRY=0; [[ ${1:-} == -n || ${1:-} == --dry-run ]] && DRY=1
[[ -f lineage/recovery.img ]] || die "lineage/recovery.img missing; run scripts/50-lineage-download.sh"
[[ -f lineage/super_empty.img ]] || die "lineage/super_empty.img missing; run scripts/50-lineage-download.sh"

step "plan: firmware"; scripts/30-oos-firmware.sh -n
step "plan: super";    scripts/40-oos-super.sh -n
if (( DRY )); then
  printf '\nsequence: bootloader: fastboot flash --slot=all recovery lineage/recovery.img; fastboot reboot fastboot\n'
  echo "then in fastbootd: firmware, super (as above), fastboot --set-active=a"
  exit 0
fi

confirm "Flash LineageOS recovery, then the firmware and super plans above?"
if ! in_fastbootd; then
  need_bootloader
  fastboot flash --slot=all recovery lineage/recovery.img
  fastboot reboot fastboot
  for _ in $(seq 60); do in_fastbootd && break; sleep 2; done
  in_fastbootd || die "fastbootd didn't come up; select 'Enter fastboot' in LineageOS recovery, then rerun"
fi

YES=1 scripts/30-oos-firmware.sh
YES=1 scripts/40-oos-super.sh
fastboot --set-active=a
cat <<'EOF'
done. Now:
  1. LineageOS recovery: Factory Reset -> Format data
  2. Reboot system; check *#06#, then scripts/60-checks.sh
EOF
