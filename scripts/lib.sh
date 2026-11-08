# Shared helpers. Source from the other scripts; run them from the repo root with bash.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="$PWD/tools/platform-tools:$PWD/tools:$PATH"
mkdir -p logs

# Logical partitions OxygenOS needs in super. The OOS payload ships 15; my_company/my_preload only exist in the CN package.
LOGICAL="my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_stock odm product system system_dlkm system_ext vendor vendor_dlkm"

die() { echo "ERROR: $*" >&2; exit 1; }
confirm() { read -r -p "$* [y/N] " a; [[ $a == [yY] ]] || die "aborted"; }
step() { printf '\n== %s\n' "$*"; }

in_fastbootd() { [[ $(fastboot getvar is-userspace 2>&1) == *"is-userspace: yes"* ]]; }
need_fastbootd() { in_fastbootd || die "not in fastbootd. LineageOS recovery -> Advanced -> Enter fastboot (or: fastboot reboot fastboot)"; }
need_bootloader() { fastboot getvar is-userspace 2>&1 | grep -q 'is-userspace: no' || die "not in the bootloader (fastboot getvar is-userspace must say no)"; }

# Physical partitions with _a/_b slots on this phone, from the Task 3 partition list.
slotted() {
  [[ -s logs/partitions.txt ]] || die "logs/partitions.txt missing; run scripts/10-backup-device.sh first"
  sed -n 's/_a$//p' logs/partitions.txt
}

# Image for a logical partition: OOS payload first, CN package for my_company/my_preload.
logical_img() {
  local f
  for f in "oos/$1.img" "backup/cn-stock/$1.img"; do [[ -f $f ]] && { echo "$f"; return; }; done
  return 1
}

# Factory packages ship META/super_def.<nv_id>.json; the nv_id variants differ only in nv_id.
# SUPER_DEF overrides the lookup.
super_def() {
  local f
  for f in ${SUPER_DEF:-} oos/META/super_def.*.json oos/super_def.*.json backup/cn-stock/META/super_def.*.json; do
    [[ -f $f ]] && { echo "$f"; return; }
  done
  return 1
}

# Size for <name>_a: super_def's size (the raw size, right even for sparse images), else the image size.
logical_size() {
  local def s
  if def=$(super_def); then
    s=$(jq -r --arg n "${1}_a" '.partitions[] | select(.name == $n) | .size // empty' "$def")
    [[ -n $s ]] && { echo "$s"; return; }
  fi
  stat -c %s "$(logical_img "$1")"
}

