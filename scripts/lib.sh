# Shared helpers. Source from the other scripts; run them from the repo root with bash.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="$PWD/tools/platform-tools:$PWD/tools:$PATH"
mkdir -p logs

# LineageOS codename of the target device (salami = OnePlus 11).
DEVICE=${DEVICE:-salami}

die() { echo "ERROR: $*" >&2; exit 1; }
confirm() { [[ ${YES:-} == 1 ]] && return; read -r -p "$* [y/N] " a; [[ $a == [yY] ]] || die "aborted"; }
step() { printf '\n== %s\n' "$*"; }

in_fastbootd() { [[ $(fastboot getvar is-userspace 2>&1) == *"is-userspace: yes"* ]]; }
need_fastbootd() { in_fastbootd || die "not in fastbootd. LineageOS recovery -> Advanced -> Enter fastboot (or: fastboot reboot fastboot)"; }
need_bootloader() { fastboot getvar is-userspace 2>&1 | grep -q 'is-userspace: no' || die "not in the bootloader (fastboot getvar is-userspace must say no)"; }

# Physical partitions with _a/_b slots on this phone, from the Task 3 partition list.
slotted() {
  [[ -s logs/partitions.txt ]] || die "logs/partitions.txt missing; run scripts/10-backup-device.sh first"
  sed -n 's/_a$//p' logs/partitions.txt
}

# Image for a logical partition: OOS payload first, then the CN package and the EDL package
# (my_company/my_preload are only in factory packages).
logical_img() {
  local f
  for f in "oos/$1.img" "backup/cn-stock/$1.img" "edl/IMAGES/$1.img"; do [[ -f $f ]] && { echo "$f"; return; }; done
  return 1
}

# Factory (EDL) packages ship META/super_def.<nv_id>.json, the only source of the device's logical layout;
# OTA payloads don't contain it. The nv_id variants (e.g. 10010111, 00000000) differ only in nv_id.
# Lookup: SUPER_DEF, the EDL package, the OTA folders, then a bundled layout/<DEVICE>-super_def.json.
super_def() {
  local f
  for f in ${SUPER_DEF:-} edl/META/super_def.*.json oos/META/super_def.*.json backup/cn-stock/META/super_def.*.json \
    "layout/$DEVICE-super_def.json"; do
    [[ -f $f ]] && { echo "$f"; return; }
  done
  return 1
}

# Logical partitions to create: the slot-a names from super_def.
logical_list() {
  local def
  def=$(super_def) || die "no super_def.*.json: copy META/super_def.*.json from this device's EDL package to edl/META/ (or set SUPER_DEF)"
  jq -r '.partitions[].name | select(endswith("_a")) | sub("_a$"; "")' "$def"
}

# Unpacked size of an image: sparse header blk_sz * total_blks, else the file size.
image_raw_size() {
  local magic
  magic=$(od -An -tx4 -N4 "$1" | tr -d ' ')
  if [[ $magic == ed26ff3a ]]; then
    echo $(( $(od -An -tu4 -j12 -N4 "$1") * $(od -An -tu4 -j16 -N4 "$1") ))
  else
    stat -c %s "$1"
  fi
}

# Size for <name>_a: super_def's size, grown to the image's raw size if a newer build is bigger.
logical_size() {
  local s img raw=0
  img=$(logical_img "$1") && raw=$(image_raw_size "$img")
  s=$(jq -r --arg n "${1}_a" '.partitions[] | select(.name == $n) | .size // empty' "$(super_def)")
  [[ -n $s ]] && (( s >= raw )) && { echo "$s"; return; }
  echo "$raw"
}
