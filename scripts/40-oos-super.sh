#!/usr/bin/env bash
# Phase 4.5: rebuild super for OxygenOS from LineageOS recovery's fastbootd.
# OnePlus Virtual A/B layout (factory super_def.json): <name>_a at full size and flashed, <name>_b empty (0 bytes).
# _a sizes come from super_def.json when present (see lib.sh), else from the image.
# Unslotted names or -cow leftovers are a broken state (sideload then fails with "not enough space").
source "$(dirname "$0")/lib.sh"
need_fastbootd
[[ -f lineage/super_empty.img ]] || die "lineage/super_empty.img missing; run scripts/50-lineage-download.sh"
for p in $LOGICAL; do logical_img "$p" >/dev/null || die "no image for $p (oos/ or backup/cn-stock/)"; done
if def=$(super_def); then
  echo "sizes from $def"
  total=0; for p in $LOGICAL; do total=$((total + $(logical_size "$p"))); done
  max=$(jq -r '.groups[] | select(.name == "qti_dynamic_partitions_a") | .maximum_size' "$def")
  (( total <= max )) || die "slot a needs $total bytes, group max is $max"
else
  echo "no super_def.json found; sizing _a from image files (wrong for sparse images)"
fi

fastboot getvar all 2>&1 | grep -E 'is-logical|has-slot|current-slot|snapshot-update-status' | sort > logs/super-before.txt
echo "current layout saved to logs/super-before.txt:"; grep -c 'is-logical:.*:yes' logs/super-before.txt
confirm "Wipe super and recreate the OxygenOS logical partitions?"

fastboot snapshot-update cancel || true
fastboot create-logical-partition probe_a 4096 && fastboot delete-logical-partition probe_a ||
  die "this fastbootd can't create partitions; use LineageOS recovery's fastbootd"
fastboot wipe-super lineage/super_empty.img
[[ $(fastboot getvar all 2>&1 | grep -c 'is-logical:.*:yes') == 0 ]] || die "super not empty after wipe-super"

for p in $LOGICAL; do
  img=$(logical_img "$p")
  fastboot create-logical-partition "${p}_a" "$(logical_size "$p")"
  fastboot create-logical-partition "${p}_b" 0
  fastboot flash "${p}_a" "$img"   # my_product/my_stock print 'Invalid sparse file format' - harmless
done 2>&1 | tee logs/oos-super.log
grep -Ei 'FAILED|error:' logs/oos-super.log && die "logical flash errors"

cat <<'EOF'
logical OK. Now:
  1. LineageOS recovery: Factory Reset -> Format data   (fastboot -w does not format here)
  2. Bootloader: fastboot --set-active=a ; fastboot reboot
  3. Check *#06#, then scripts/60-checks.sh
EOF
