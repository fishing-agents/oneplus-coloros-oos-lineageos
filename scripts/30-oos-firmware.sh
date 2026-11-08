#!/usr/bin/env bash
# Phase 4.3 / 4.5 firmware half: flash every slotted physical partition to both slots.
# Sources:
#   FW list (OnePlus ColorOS<->OxygenOS conversion set, droidwin; + init_boot, which must match boot) -> $FW_SRC
#   oplusstanvbk and modem -> backup/device/<name>_a.img (this phone)
#   every other slotted partition -> kept: no OTA ships it, so the phone still has its own
#   recovery -> kept (LineageOS fastbootd)
# oplusstanvbk must stay this phone's CN copy, else the modem crash-loops.
# Run in LineageOS-recovery fastbootd, or the bootloader (modem is refused there, which is fine).
# usage: scripts/30-oos-firmware.sh [-n|--dry-run]      FW_SRC=backup/cn-stock for ColorOS firmware
source "$(dirname "$0")/lib.sh"
DRY=0; [[ ${1:-} == -n || ${1:-} == --dry-run ]] && DRY=1
FW_SRC=${FW_SRC:-oos}
FW=" abl aop aop_config bluetooth boot init_boot cpucp devcfg dsp dtbo engineering_cdt featenabler hyp imagefv keymaster
 oplus_sec qupfw shrm splash tz uefi uefisecapp vbmeta vbmeta_system vbmeta_vendor vendor_boot xbl xbl_config
 xbl_ramdump "
BOOTCHAIN=" xbl xbl_config abl tz hyp devcfg keymaster uefisecapp aop "
[[ -d $FW_SRC ]] || die "$FW_SRC/ missing; run scripts/20-extract.sh"
[[ -s logs/partitions.txt ]] || die "logs/partitions.txt missing; run scripts/10-backup-device.sh"

miss=()
: > logs/firmware-plan.txt
for p in $(sed -n 's/_a$//p' logs/partitions.txt | sort -u); do
  [[ $p == recovery ]] && { echo "KEEP  recovery"; continue; }
  if [[ $FW == *[[:space:]]$p[[:space:]]* ]]; then img=$FW_SRC/$p.img
  elif [[ $p == oplusstanvbk || $p == modem ]]; then img=backup/device/${p}_a.img
  else
    # Not in any OTA, so nothing replaced it: the phone still holds the backup's content.
    # fastbootd can't write several of these anyway (rticmpdata: size 0, "No such file or directory").
    echo "KEEP  $p (unchanged on the phone)"; continue
  fi
  [[ -s $img ]] || { miss+=("$img"); continue; }
  note=""; [[ $FW_SRC != oos && $BOOTCHAIN == *" $p "* ]] && note="   # boot chain from $FW_SRC: anti-rollback risk"
  echo "fastboot flash --slot=all $p $img$note" >> logs/firmware-plan.txt
done
cat logs/firmware-plan.txt
(( ${#miss[@]} == 0 )) || { printf 'MISSING %s\n' "${miss[@]}"; die "missing images"; }
(( DRY )) && exit 0

grep -q 'anti-rollback' logs/firmware-plan.txt &&
  echo "WARNING: a boot chain older than the phone's fused rollback level hard-bricks it (README 4.3)."
confirm "Flash the plan above?"
: > logs/firmware.log
while read -r cmd; do
  cmd=${cmd%%#*}
  $cmd 2>&1 | tee -a logs/firmware.log
  [[ ${PIPESTATUS[0]} == 0 ]] && continue
  [[ $cmd == *" modem "* ]] && { echo "modem refused here (bootloader does that); fine"; continue; }
  die "'$cmd' failed; don't reboot to Android, fix and rerun"
done < <(grep '^fastboot' logs/firmware-plan.txt)
echo "firmware OK: $(grep -c 'Writing.*OKAY' logs/firmware.log) writes"
