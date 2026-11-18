#!/usr/bin/env bash
# Phase 4.5: flash the OxygenOS logical partitions into super from LineageOS recovery's fastbootd.
# Default: flash the existing <name>_a partitions in place; nothing is wiped or deleted.
# --rebuild (recovery step, destructive): wipe super and recreate the OnePlus Virtual A/B layout
# (factory super_def.json): <name>_a at full size and flashed, <name>_b empty (0 bytes). Use it only when
# the layout is broken: unslotted names, -cow leftovers, missing partitions (sideload "not enough space").
# usage: scripts/40-oos-super.sh [-n|--dry-run] [--rebuild]   (-n: print the layout and commands; no device needed)
source "$(dirname "$0")/lib.sh"
DRY=0 REBUILD=0
for a in "$@"; do
  case $a in -n|--dry-run) DRY=1 ;; --rebuild) REBUILD=1 ;; *) die "unknown option $a" ;; esac
done

# Layout that would be created, plus the slot-a total against the group maximum.
show_layout() {
  local def max total=0 p img s
  def=$(super_def) && echo "sizes from $def" || { def=; echo "no super_def.json found; sizing _a from image files"; }
  printf '%-20s %14s  %-6s %s\n' partition bytes slot source
  for p in $(logical_list); do
    img=$(logical_img "$p") || { img="(no image)"; (( DRY )) || die "no image for $p"; }
    s=$(logical_size "$p"); total=$((total + s))
    printf '%-20s %14s  %-6s %s\n' "${p}_a" "$s" a "$img" "${p}_b" 0 b "(empty)"
  done
  printf '%-20s %14s\n' "slot a total" "$total"
  if [[ -n $def ]]; then
    max=$(jq -r '[.groups[] | select(.name | endswith("_a"))][0].maximum_size' "$def")
    printf '%-20s %14s  free %s\n' "group max" "$max" "$((max - total))"
    (( total <= max )) || die "slot a needs $total bytes, group max is $max"
  fi
}

if (( DRY )); then
  show_layout
  echo; echo "commands (fastbootd):"
  if (( REBUILD )); then
    echo "fastboot snapshot-update cancel"
    echo "fastboot wipe-super lineage/super_empty.img"
    echo "fastboot delete-logical-partition <each partition super_empty.img left>"
  fi
  for p in $(logical_list); do
    if (( REBUILD )); then
      echo "fastboot create-logical-partition ${p}_a $(logical_size "$p")"
      echo "fastboot create-logical-partition ${p}_b 0"
    fi
    echo "fastboot flash ${p}_a $(logical_img "$p" || echo "<missing>")"
  done
  exit 0
fi

need_fastbootd
for p in $(logical_list); do logical_img "$p" >/dev/null || die "no image for $p (oos/, backup/cn-stock/ or edl/IMAGES/)"; done
show_layout
fastboot getvar all 2>&1 | grep -E 'is-logical|has-slot|current-slot|snapshot-update-status' | sort > logs/super-before.txt
echo "current layout saved to logs/super-before.txt:"; grep -c 'is-logical:.*:yes' logs/super-before.txt

if (( REBUILD )); then
  [[ -f lineage/super_empty.img ]] || die "lineage/super_empty.img missing; run scripts/50-lineage-download.sh"
  confirm "Wipe super and recreate the OxygenOS logical partitions?"
  fastboot snapshot-update cancel || true
  fastboot create-logical-partition probe_a 4096 && fastboot delete-logical-partition probe_a ||
    die "this fastbootd can't create partitions; use LineageOS recovery's fastbootd"
  fastboot wipe-super lineage/super_empty.img
  # LineageOS's super_empty.img still lists its own partitions at size 0; drop them before recreating.
  for p in $(fastboot getvar all 2>&1 | sed -n 's/.*is-logical:\([^:]*\):yes.*/\1/p' | sort -u); do
    fastboot delete-logical-partition "$p"
  done
  [[ $(fastboot getvar all 2>&1 | grep -c 'is-logical:.*:yes') == 0 ]] || die "logical partitions left after wipe-super"
else
  missing=$(for p in $(logical_list); do grep -q "is-logical:${p}_a:yes" logs/super-before.txt || echo "${p}_a"; done)
  [[ -z $missing ]] || die "missing in super: $(echo $missing). The layout is broken; rerun with --rebuild (wipes super)"
  confirm "Flash the OxygenOS logical partitions in place?"
fi

for p in $(logical_list); do
  img=$(logical_img "$p")
  if (( REBUILD )); then
    fastboot create-logical-partition "${p}_a" "$(logical_size "$p")"
    fastboot create-logical-partition "${p}_b" 0
  fi
  fastboot flash "${p}_a" "$img"   # my_product/my_stock print 'Invalid sparse file format' - harmless
done 2>&1 | tee logs/oos-super.log
grep -Ei 'FAILED|error:' logs/oos-super.log && die "logical flash errors (not enough space: rerun with --rebuild)"

cat <<'EOF'
logical OK. Now:
  1. LineageOS recovery: Factory Reset -> Format data   (fastboot -w does not format here)
  2. Bootloader: fastboot --set-active=a ; fastboot reboot
  3. Check *#06#, then scripts/60-checks.sh
EOF
