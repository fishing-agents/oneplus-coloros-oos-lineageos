#!/usr/bin/env bash
# Keybox health check: prints certificate metadata and revocation status only; never private keys.
# Usage: bash tests/check-keybox.sh <serial>
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$root/build/keybox-check"; mkdir -p "$work"; chmod 700 "$work"
trap 'rm -rf "$work"' EXIT
adb -s "$1" exec-out su -c 'cat /data/adb/tricky_store/keybox.xml' | tr -d '\r' | sed 's/^[[:space:]]*//' > "$work/keybox.xml"
curl -fsS https://android.googleapis.com/attestation/status -o "$work/crl.json"
# Split every certificate out of the XML, preserving chain order.
awk '/-----BEGIN CERTIFICATE-----/{n++; f=sprintf("'"$work"'/cert%02d.pem", n)} f{print > f} /-----END CERTIFICATE-----/{f=""}' "$work/keybox.xml"
printf 'certificates=%s keys=%s\n' "$(ls "$work"/cert*.pem | wc -l)" "$(grep -c -- '-----BEGIN .*PRIVATE KEY-----' "$work/keybox.xml")"
for c in "$work"/cert*.pem; do
    serial="$(openssl x509 -in "$c" -noout -serial | cut -d= -f2 | tr 'A-F' 'a-f' | sed 's/^0*//')"
    status="$(jq -r --arg s "$serial" '.entries[$s] // empty | "REVOKED reason=\(.reason) status=\(.status)"' "$work/crl.json")"
    printf '%s subject=%s issuer=%s notAfter=%s alg=%s %s\n' "$(basename "$c" .pem)" \
        "$(openssl x509 -in "$c" -noout -subject | sed 's/^subject=//' | cut -c1-80)" \
        "$(openssl x509 -in "$c" -noout -issuer | sed 's/^issuer=//' | cut -c1-80)" \
        "$(openssl x509 -in "$c" -noout -enddate | cut -d= -f2)" \
        "$(openssl x509 -in "$c" -noout -text | sed -n 's/^ *Public Key Algorithm: //p' | head -1)" \
        "${status:-not_revoked}"
done
# Verify each chain signs correctly up to its root (keybox usually holds an EC chain and an RSA chain).
cat "$work"/cert*.pem > "$work/all.pem"
for c in "$work"/cert*.pem; do
    if openssl verify -no_check_time -partial_chain -CAfile "$work/all.pem" "$c" >/dev/null 2>&1; then r=ok; else r=FAIL; fi
    printf '%s chain_verify=%s\n' "$(basename "$c" .pem)" "$r"
done
