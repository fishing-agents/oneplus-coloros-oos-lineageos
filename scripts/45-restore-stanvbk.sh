#!/usr/bin/env bash
# Restore this phone's ColorOS oplusstanvbk to both slots (any CN phone converted to OxygenOS). Needed after anything rewrites it
# (an OxygenOS OTA, a full-firmware flash). Symptom when wrong: modem crash loop
# "Qlink(0) qsf_init failed at first bootup", no IMEI.
source "$(dirname "$0")/lib.sh"
need_fastbootd
for s in a b; do
  img=backup/device/oplusstanvbk_$s.img
  [[ -s $img ]] || die "$img missing"
  want=$(fastboot getvar partition-size:oplusstanvbk_$s 2>&1 | awk '/partition-size/{print $2}')
  (( want == $(stat -c %s "$img") )) || die "size mismatch for oplusstanvbk_$s ($want vs file)"
  fastboot flash oplusstanvbk_$s "$img"
done
echo "done: fastboot reboot"
