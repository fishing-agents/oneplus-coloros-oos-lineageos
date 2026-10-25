#!/usr/bin/env bash
# Build a systemless KernelSU module with the OnePlus camera from OOS images.
# Sources: this repo's oos/ images (CPH2449 OxygenOS, >= 16.0.5.1301 = the build LineageOS's camera HAL comes from).
# File list based on ehhhSenpai/proprietary_vendor_oplus_camera (OOS 14.0.0.401); files are looked up by name in
# the OOS 16 images, so moved files are still found. Nothing is extracted in full: only the needed files are read
# out of the images (dump.erofs --cat / debugfs dump), so it needs ~200 MB, not the size of the images.
# Experimental: on crDroid (OnePlus 11, Android 14) portrait and night mode were broken even when built in.
# Needs on the host: erofs-utils >= 1.7 (dump.erofs) for EROFS images, e2fsprogs (debugfs) for ext4, readelf, zip.
source "$(dirname "$0")/lib.sh"
W=build/oplus-camera; M=$W/module; rm -rf "$W"; mkdir -p "$M" "$W/tmp"

# --- tools
if [[ ! -x tools/aapt2 ]]; then
  v=$(curl -fsSL https://dl.google.com/android/maven2/com/android/tools/build/aapt2/maven-metadata.xml |
    grep -oE '<version>[^<]+</version>' | sed 's/<[^>]*>//g' | grep -vE 'alpha|beta|rc' | tail -1)
  curl -fsSL -o "$W/aapt2.jar" "https://dl.google.com/android/maven2/com/android/tools/build/aapt2/$v/aapt2-$v-linux.jar"
  unzip -o -q "$W/aapt2.jar" aapt2 -d tools && chmod +x tools/aapt2
fi
command -v readelf zip >/dev/null || die "need readelf (binutils) and zip"

# --- read single files out of an image without extracting it
fstype() { python3 - "$1" <<'EOF'
import sys
b = open(sys.argv[1], 'rb').read(2048)
print('erofs' if b[1024:1028] == bytes.fromhex('e2e1f5e0') else 'ext4' if b[1080:1082] == bytes.fromhex('53ef') else 'unknown')
EOF
}
declare -A T
for i in my_product system_ext system; do
  [[ -f oos/$i.img ]] || die "oos/$i.img missing (scripts/20-extract.sh)"
  T[$i]=$(fstype "oos/$i.img")
  case ${T[$i]} in
    erofs) command -v dump.erofs >/dev/null || die "install erofs-utils >= 1.7 (dump.erofs)";;
    ext4)  command -v debugfs >/dev/null || die "install e2fsprogs (debugfs)";;
    *)     die "oos/$i.img: unknown filesystem";;
  esac
done
# system.img is usually system-as-root (files under /system/); probe so a flat layout works too.
SYS_ROOT=/system
root() { [[ $1 == system ]] && echo "$SYS_ROOT" || echo ""; }
ls_dir() {  # <img> <dir> -> file names
  local d; d="$(root "$1")$2"
  if [[ ${T[$1]} == erofs ]]; then dump.erofs --ls --path="$d" "oos/$1.img" 2>/dev/null | awk 'NR>1{print $NF}'
  else debugfs -R "ls -p $d" "oos/$1.img" 2>/dev/null | awk -F/ 'NF>5{print $6}'; fi | grep -vxE '\.|\.\.' | grep -v '^$' || true
}
[[ -n $(ls_dir system /framework) ]] || SYS_ROOT=""
get() {  # <img> <path> <out>
  local p; p="$(root "$1")$2"; mkdir -p "$(dirname "$3")"
  if [[ ${T[$1]} == erofs ]]; then dump.erofs --cat --path="$p" "oos/$1.img" > "$3" 2>/dev/null
  else debugfs -R "dump $p $3" "oos/$1.img" >/dev/null 2>&1; fi
  [[ -s $3 ]] || { rm -f "$3"; return 1; }
}

# --- 1. app (privileged, systemless under /system_ext/priv-app)
missing=()
get my_product /app/OplusCamera/OplusCamera.apk "$M/system/system_ext/priv-app/OplusCamera/OplusCamera.apk" ||
  die "OplusCamera.apk not in oos/my_product.img /app/OplusCamera"

# --- 2. libraries: the known list, then everything they link against that only exists in my_product
mp_libs=$(ls_dir my_product /lib64); se_libs=$(ls_dir system_ext /lib64)
want=(libAPSClient-cmd-jni.so libAPSClient-jni.so libAncFilter_jni.so libAncHumBokeh-jni.so
  libAncHumanDoubleExposure-jni.so libAncHumanRetain-jni_v2.so libAncHumanSegFigureFusion-jni.so libAncHumanVideo-jni.so
  libApsFaceBeautyPreviewProductJni.so libAvatarEngineRender.so libAvatarEngineRenderNative.so libCombineLut.so
  libCombineLutJni.so libFileExtender-jni.so libOplusBlurPreviewJNI.so libSuperTextWrapper.so libXDocProcessSDK-jni.so
  libXDocProcessSDK.so libYTCommon.so libarcsoft_wideselfie.so libextendfile.so
  libjni_wideselfie.so libjnisingleblur_api.so libjnistblur_api.so libmpbase.so
  libsingle_camera_bokeh_native.so libst_mobile.so libst_sticker_jni.so
  libHeifEncoderWrapper.so libNativeWinBuffExchange.so liboplusheifwriter.so)
L=$M/system/system_ext/lib64
fetch_lib() {  # from my_product first, else system_ext
  [[ -f $L/$1 ]] && return 0
  grep -qx "$1" <<<"$mp_libs" && get my_product "/lib64/$1" "$L/$1" && return 0
  grep -qx "$1" <<<"$se_libs" && get system_ext "/lib64/$1" "$L/$1" && return 0
  return 1
}
for l in "${want[@]}"; do fetch_lib "$l" || missing+=("$l"); done
get system_ext /lib64/libpenguin.so "$M/system/vendor/lib64/libpenguin.so" || missing+=(libpenguin.so)
# Dependency closure: DT_NEEDED entries found in my_product (LineageOS has no my_product) that LineageOS doesn't
# already ship. Needs the phone on adb to know what LineageOS has; without it only the fixed list is packed.
los_libs=$(adb shell 'ls /system/lib64 /system_ext/lib64 /vendor/lib64 /product/lib64' 2>/dev/null | tr -d '\r' | grep '\.so' || true)
added=1
[[ -n $los_libs ]] || { added=0; echo "note: phone not on adb; skipping dependency closure (connect the phone and rerun)"; }
while ((added)); do
  added=0
  for f in "$L"/*.so; do
    for n in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
      [[ -f $L/$n ]] && continue
      grep -qx "$n" <<<"$los_libs" && continue   # LineageOS already has it: don't shadow
      grep -qx "$n" <<<"$mp_libs" && get my_product "/lib64/$n" "$L/$n" && { echo "  + dependency $n"; added=1; }
    done
  done
done

# --- 3. framework jars and permission XML
F=$M/system/system_ext/framework
for j in com.oplus.camera.unit.sdk.adapter com.oplus.camera.unit.sdk; do
  get my_product "/product_overlay/framework/$j.jar" "$F/$j.jar" || missing+=("$j.jar")
done
# The camera calls OOS framework wrappers absent from LineageOS. Add them only to
# its optional SDK library, not to the system boot classpath.
[[ -s $F/com.oplus.camera.unit.sdk.jar ]] || die "camera SDK jar missing"
get system /framework/oplus-framework.jar "$W/tmp/oplus-framework.jar" || die "OOS framework jar missing"
unzip -p "$W/tmp/oplus-framework.jar" classes.dex > "$W/tmp/classes2.dex"
unzip -p "$W/tmp/oplus-framework.jar" classes2.dex > "$W/tmp/classes3.dex"
[[ -s $W/tmp/classes2.dex && -s $W/tmp/classes3.dex ]] || die "OOS framework dex missing"
zip -q -j "$F/com.oplus.camera.unit.sdk.jar" "$W/tmp/classes2.dex" "$W/tmp/classes3.dex"

# Declare every jar as a shared library so <uses-library> resolves.
P=$M/system/system_ext/etc/permissions; mkdir -p "$P"
{ echo '<?xml version="1.0" encoding="utf-8"?>'; echo '<permissions>'
  for j in "$F"/*.jar; do [[ -f $j ]] && echo "    <library name=\"$(basename "$j" .jar)\" file=\"/system_ext/framework/$(basename "$j")\" />"; done
  echo '</permissions>'; } > "$P/oplus-camera-libraries.xml"

# Whitelist requested privileged permissions for the packaged camera app.
{ echo '<?xml version="1.0" encoding="utf-8"?>'; echo '<permissions>'
  for apk in "$M"/system/system_ext/priv-app/*/*.apk; do
    pkg=$(tools/aapt2 dump badging "$apk" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
    echo "    <privapp-permissions package=\"$pkg\">"
    tools/aapt2 dump permissions "$apk" | sed -n "s/^uses-permission: name='\([^']*\)'.*/        <permission name=\"\1\" \/>/p" | sort -u
    echo '    </privapp-permissions>'
  done
  echo '</permissions>'; } > "$P/privapp-permissions-oplus-camera.xml"

# --- 4. report what will not work
cam="$M/system/system_ext/priv-app/OplusCamera/OplusCamera.apk"
pkg=$(tools/aapt2 dump badging "$cam" | sed -n "s/^package: name='\([^']*\)' versionCode='\([^']*\)' versionName='\([^']*\)'.*/\1 \3/p")
echo "OplusCamera: $pkg"
suid=$(tools/aapt2 dump xmltree --file AndroidManifest.xml "$cam" | sed -n 's/.*sharedUserId.*="\([^"]*\)".*/\1/p')
[[ -z $suid ]] || die "OplusCamera requires sharedUserId=$suid, which cannot join LineageOS's platform UID"
for u in $(tools/aapt2 dump badging "$cam" | sed -n "s/^uses-library:'\([^']*\)'/\1/p"); do
  [[ -f $F/$u.jar ]] || echo "WARNING: required library '$u' not provided -> package install fails until it is added"
done
if ((${#missing[@]})); then echo "not found in the OOS images (may be renamed/dropped in OOS 16): ${missing[*]}"; fi

# --- 5. module metadata + zip (KernelSU Manager installs module.prop + system/ directly)
[[ $pkg == *' '* ]] || die "could not read OplusCamera package/version"
cat > "$M/module.prop" <<EOF
id=oplus_camera
name=OnePlus Camera (OplusCamera) for LineageOS
version=${pkg#* }-2
versionCode=60001
author=local build from oos/
description=Systemless OplusCamera, libraries and framework jars from CPH2449 OxygenOS. Experimental.
EOF
(cd "$M" && zip -qr9 ../OplusCamera-module.zip .)
echo "built $W/OplusCamera-module.zip ($(du -h "$W/OplusCamera-module.zip" | cut -f1))"
cat <<'EOF'
Install: KernelSU Manager -> Modules -> Install -> select build/oplus-camera/OplusCamera-module.zip -> reboot.
Requires a KernelSU system-mount metamodule (for example, meta-overlayfs).
In KernelSU's com.oplus.camera App Profile, turn off "Umount modules" without granting root;
otherwise Android sees the APK at boot, but the camera process cannot load it.
Remove: KernelSU Manager -> Modules -> disable/remove -> reboot.
EOF
