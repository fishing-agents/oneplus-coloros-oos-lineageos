#!/usr/bin/env bash
# Download the newest LineageOS build for $DEVICE and verify every file against the official API hashes.
source "$(dirname "$0")/lib.sh"
mkdir -p lineage
: > lineage/SHA256SUMS
curl -fsSL https://download.lineageos.org/api/v2/devices/$DEVICE/builds |
  jq -r --arg dev "$DEVICE" '.[0].files[] | select(.filename|test("\($dev)-signed.zip$|^(boot|dtbo|init_boot|vbmeta|vendor_boot|recovery|super_empty)\\.img$")) | "\(.url) \(.sha256) \(.filename)"' |
  while read -r url sum f; do
    [[ -f lineage/$f ]] && echo "$sum  $f" | (cd lineage && sha256sum -c --quiet) 2>/dev/null || curl -fL -o "lineage/$f" "$url"
    echo "$sum  $f" >> lineage/SHA256SUMS
  done
(cd lineage && sha256sum -c SHA256SUMS)
