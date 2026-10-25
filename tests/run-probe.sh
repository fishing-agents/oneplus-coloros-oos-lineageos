#!/usr/bin/env bash
# Usage: bash tests/run-probe.sh <ProbeClass> [serial]   (ProbeClass = tests/<ProbeClass>.java)
# Requires adb, javac 17+, and Android SDK platform/build tools. Android 12+ device.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
android_jar=; d8=
for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk"; do
    [[ -n "$sdk" ]] || continue
    mapfile -t platforms < <(printf '%s\n' "$sdk"/platforms/android-*/android.jar | sort -V)
    mapfile -t compilers < <(printf '%s\n' "$sdk"/build-tools/*/d8 | sort -V)
    if [[ -f "${platforms[-1]}" && -x "${compilers[-1]}" ]]; then
        android_jar="${platforms[-1]}"; d8="${compilers[-1]}"; break
    fi
done
if [[ -z "$d8" ]]; then
    printf 'No Android SDK with platforms/android-*/android.jar and build-tools/*/d8 found; set ANDROID_HOME.\n' >&2
    exit 2
fi
if (( $# < 1 || $# > 2 )) || [[ ! -f "$root/tests/$1.java" ]]; then
    printf 'Usage: bash tests/run-probe.sh <ProbeClass> [serial]\n' >&2
    exit 2
fi
probe="$1"; shift
device=()
if (( $# == 1 )); then device=(-s "$1"); fi
# Always run as the shell user so results are comparable even when adbd runs as root.
uid="$(adb "${device[@]}" shell id -u)"
as_shell=()
if [[ "${uid//$'\r'/}" == 0 ]]; then as_shell=(su 2000 -c); fi
api="$(adb "${device[@]}" shell getprop ro.build.version.sdk)"
api="${api//$'\r'/}"
if [[ ! "$api" =~ ^[0-9]+$ ]] || (( api < 31 )); then
    printf 'Requires Android 12 / API 31 or later.\n' >&2
    exit 2
fi

build="$root/build/probe-test"
mkdir -p "$build"
javac --release 17 -cp "$android_jar" -d "$build" "$root/tests/$probe.java"
"$d8" --min-api 31 --lib "$android_jar" --output "$build/$probe.zip" "$build/$probe.class"
remote="/data/local/tmp/$probe.zip"
trap 'adb "${device[@]}" shell rm -f "$remote" || printf "Warning: device probe archive cleanup failed.\n" >&2' EXIT
adb "${device[@]}" push "$build/$probe.zip" "$remote"
adb "${device[@]}" shell "${as_shell[@]}" "CLASSPATH=$remote app_process /system/bin $probe"
