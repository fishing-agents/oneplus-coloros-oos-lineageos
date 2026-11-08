#!/usr/bin/env bash
# Phase 4.5: rebuild super for OxygenOS from LineageOS recovery's fastbootd.
# OnePlus Virtual A/B layout (factory super_def.json): <name>_a at full size and flashed, <name>_b empty (0 bytes).
# _a sizes come from super_def.json when present (see lib.sh), else from the image.
# Unslotted names or -cow leftovers are a broken state (sideload then fails with "not enough space").
# usage: scripts/40-oos-super.sh [-n|--dry-run]   (-n: print the layout and commands; no device needed)
source "$(dirname "$0")/lib.sh"
DRY=0; [[ ${1:-} == -n || ${1:-} == --dry-run ]] && DRY=1

# Layout that would be created, plus the slot-a total against the group maximum.
show_layout() {
  local def max total=0 p img s
  def=$(super_def) && echo "sizes from $def" || { def=; echo "no super_def.json found; sizing _a from image files"; }
  printf '%-20s %14s  %-6s %s\n' partition bytes slot source
  for p in $LOGICAL; do
    img=$(logical_img "$p") || { img="(no image)"; (( DRY )) || die "no image for $p"; }
    s=$(logical_size "$p"); total=$((total + s))
    printf '%-20s %14s  %-6s %s\n' "${p}_a" "$s" a "$img" "${p}_b" 0 b "(empty)"
  done
  printf '%-20s %14s\n' "slot a total" "$total"
  if [[ -n $def ]]; then
    max=$(jq -r '.groups[] | select(.name == "qti_dynamic_partitions_a") | .maximum_size' "$def")
    printf '%-20s %14s  free %s\n' "group max" "$max" "$((max - total))"
    (( total <= max )) || die "slot a needs $total bytes, group max is $max"
  fi
}

if (( DRY )); then
  show_layout
  echo; echo "commands (fastbootd):"
  echo "fastboot snapshot-update cancel"
  echo "fastboot wipe-super lineage/super_empty.img"
  for p in $LOGICAL; do
    echo "fastboot create-logical-partition ${p}_a $(logical_size "$p")"
    echo "fastboot create-logical-partition ${p}_b 0"
    echo "fastboot flash ${p}_a $(logical_img "$p" || echo "<missing>")"
  done
  exit 0
fi

need_fastbootd
[[ -f lineage/super_empty.img ]] || die "lineage/super_empty.img missing; run scripts/50-lineage-download.sh"
for p in $LOGICAL; do logical_img "$p" >/dev/null || die "no image for $p (oos/ or backup/cn-stock/)"; done
show_layout

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
