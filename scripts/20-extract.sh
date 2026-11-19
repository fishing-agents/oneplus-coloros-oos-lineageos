#!/usr/bin/env bash
# Tasks 3.1 + 3.4: extract the CN and OOS full OTAs, then gate on anti-rollback (ARB).
# The fuse can't be read, but it is never above the ARB index of the firmware the phone runs now. So OOS is
# safe to flash when its xbl_config ARB index is >= the running one (this phone's backup, else the CN zip).
# Android version and security patch are checked too, but only the ARB index decides.
# usage: scripts/20-extract.sh <ColorOS_CN_full.zip> <OxygenOS_full.zip>
source "$(dirname "$0")/lib.sh"
cn=${1:?CN zip}; oos=${2:?OOS zip}

meta() { unzip -p "$1" META-INF/com/android/metadata | grep -E '^(post-build|post-sdk-level|post-security-patch-level|version_name)='; }
meta "$cn"  | tee logs/cn-build.txt
meta "$oos" | tee logs/oos-build.txt

val() { sed -n "s/^$1=//p" "$2"; }
cn_sdk=$(val post-sdk-level logs/cn-build.txt);  oos_sdk=$(val post-sdk-level logs/oos-build.txt)
cn_spl=$(val post-security-patch-level logs/cn-build.txt); oos_spl=$(val post-security-patch-level logs/oos-build.txt)
(( oos_sdk >= cn_sdk )) || die "OOS Android (sdk $oos_sdk) older than CN (sdk $cn_sdk); get a newer OOS OTA"
[[ ! $oos_spl < $cn_spl ]] || echo "note: OOS patch $oos_spl is older than CN $cn_spl; the ARB check below decides"
# LineageOS 24.0 bundles CPH2449 16.0.5.1301 firmware: an older OOS here means a later sideload changes firmware
# versions across slots, and going back to OOS after LineageOS would be a downgrade.
LOS_FW=${LOS_FW-16.0.5.1301}
oos_ver=$(grep -oE '1[0-9]\.[0-9]+\.[0-9]+\.[0-9]+' logs/oos-build.txt | head -1)
[[ -n $oos_ver ]] || die "can't read the OOS version (16.x.y.z) from the zip metadata"
if [[ -n $LOS_FW ]]; then
  [[ $(printf '%s\n' "$LOS_FW" "$oos_ver" | sort -V | head -1) == "$LOS_FW" ]] ||
    die "OOS $oos_ver is older than $LOS_FW (LineageOS's bundled firmware); get a newer full OTA (LOS_FW= to skip)"
  echo "go: OOS $oos_ver >= $LOS_FW"
fi

step "extract"
mkdir -p backup/cn-stock oos
payload-dumper-go -o backup/cn-stock "$cn"
payload-dumper-go -o oos "$oos"
(cd backup/cn-stock && sha256sum -- *.img > SHA256SUMS)
(cd oos && sha256sum -- *.img > SHA256SUMS)

step "anti-rollback"
ref=$(ls backup/device/xbl_config_a.img backup/device/xbl_config.img backup/cn-stock/xbl_config.img 2>/dev/null | head -1)
[[ -n $ref ]] || die "no xbl_config image to compare against"
now=$(python3 scripts/arb.py "$ref") || die "can't read ARB from $ref"
new=$(python3 scripts/arb.py oos/xbl_config.img) || die "can't read ARB from oos/xbl_config.img"
echo "ARB: running $now ($ref), OOS $new" | tee logs/arb.txt
(( new >= now )) || die "OOS ARB $new < running $now: flashing it hard-bricks the phone"
(( new == now )) || echo "note: OOS raises ARB to $new; after it boots, firmware with ARB < $new can never be flashed again"
echo "go: ARB $new >= $now"
