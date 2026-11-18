# OP11 CN → EU OxygenOS: build-property differences

Documentation only. No properties were changed during this comparison. The only deliberately applied change on this unit is `persist.vendor.display.pxlw.iris_feature`, documented in `op11-display-debug.md`.

## Method

Compared `build.prop` in each partition of two full OTAs obtained with [`oplus-ota`](https://github.com/fishing-agents/oplus-ota) (the user's OPPO/OnePlus/realme OTA query/download tool):

- CN: `PHB110_16.0.5.1301(CN01)`, `PHB110_11.H.14_3140_202610122342`
- EU: `CPH2449_16.0.5.1301(EX01)`, `CPH2449_11.H.16_3160_202609101959`

Sources: `cos/` (CN `vendor`, `odm`, `my_product`, dlkm) plus CN `system`, `system_ext`, `product`, `my_manifest`, `my_region` extracted to `/games/oneplus/debug/cn-extract`. EU `system`/`system_ext`/`product`/`vendor`/`odm`/`my_product` come from `oos/` (verified byte-identical to the fresh EU OTA); EU `my_manifest` and `my_region` come from the fresh OTA extraction at `/games/oneplus/tool/oplus-ota/oos/` because the repo copies of those two are ROW, not EUEX.

Differing keys: `system` 15, `system_ext` 17, `product` 5, `my_manifest` 55, `my_region` 31, `vendor` 6, `odm` 36, `my_product` 65 (230 total). Full list: `/games/oneplus/debug/props-cn-vs-eu.diff`; generator: `/games/oneplus/debug/compare_props.py`.

The current phone runs EUEX 1301 on CN PHB110 hardware. Effective values can be checked read-only with `getprop <key>`; a key defined in several partitions is resolved by load order, so the table's partition tag matters.

## Do not change without separate approval

These are user-named or car/NFC/RSA-related. Values are shown CN | EU.

| Property | CN | EU | Why leave it |
|---|---|---|---|
| `ro.oplus.rsa` | `rsa4-non` | `rsa4-tier3` | Regional software-authentication tier; effect on provisioning/attestation unknown. Do not change. |
| `ro.oplus.nfc.secure_nfc` | absent | `sn100` | Selects NFC secure-element/controller config. Wrong value can break NFC/eSE and car keys. Confirm the actual controller first. |
| `ro.oplus.nfc.ccc_dck_support` | absent | `true` | CCC digital car key; car-related. Do not change. |
| `ro.oplus.nfc.ccc_bmw_hmi_support` | `true` | absent | BMW HMI car key; car-related. Do not change. |
| `persist.bluetooth.carkit_compability_control` | `true` | absent | Car-kit compatibility; car-related. Do not change. |
| `ro.oplus.nfc.smart_switch_card` | `true` | absent | NFC card feature. Do not change. |
| `ro.oplus.nfc.support.encryption_card` | `true` | absent | NFC encrypted card. Do not change. |
| `ro.oplus.nfc.support.supercard` | `true` | absent | NFC supercard. Do not change. |
| `ro.product.cuptsm` | `ONEPLUS\|ESE\|01\|02` | absent | eSE/TSM configuration; touches secure element. Do not change. |
| `ro.product.authentication` | `2022CP17679` | `0` | Provisioning/authentication marker. Do not change. |
| `ro.vendor.oplus.provision.pki` | `1` | absent | Provisioning PKI flag. Do not change. |

### `ro.oplus.rsa`: unresolved, not proven export control

Values are `rsa4-non` (CN) and `rsa4-tier3` (EU). The name and tiers suggest a regional software-authentication/export-tier tag, but that is inference. A `strings` scan of `oplus-framework.jar` found separate region-lock APIs (`OplusRegionLockState`, `REGION_LOCK_RESTRICTION_*`, `unlockRegionLock`) and a different key `ro.oplus.rsa3.support`; it found no consumer of `ro.oplus.rsa` and no evidence that it enforces export control. Treat the meaning as unknown. The EUEX build already carries the `tier3` value, so running the EU build outside China does not require changing it.

## Display

| Property | CN | EU | Status |
|---|---|---|---|
| `persist.vendor.display.pxlw.iris_feature` | `0x407f0780` | `0x400080` | Applied on this unit; see display doc. |
| `persist.oplus.display.pixelworks` | `1` | absent | Unverified; do not change yet. |
| `ro.display.brightness.skip_screen_on_animation` | `true` | absent | Behavior/cosmetic; do not change yet. |
| `debug.egl.sbc` | `0x80` | absent | EGL tuning; unknown effect. Do not change yet. |

## Audio

| Property | CN | EU |
|---|---|---|
| `ro.oplus.audio.support.mss` | `1` | absent |
| `ro.oplus.audio.support.meta_audio` | `0` | absent |
| `ro.oplus.audio.thermal_control` | `1` | absent |
| `ro.oplus.audio.spllimit.support` | `true` | absent |
| `ro.oplus.audio.assistantoutput.forced` | `true` | absent |
| `ro.oplus.audio.ringermodeinfo.feedback.support` | `1` | absent |

Audio HAL/feature flags. Unverified; only relevant if audio behavior is wrong.

## Sensors, charging, Wi-Fi/Bluetooth

| Property | CN | EU | Note |
|---|---|---|---|
| `persist.sys.oppo.proximity` | `true` | absent | Call-proximity behavior; unverified. |
| `persist.vendor.qvr.usb.type` | absent | `11ax` | Purpose unclear; leave. |
| `ro.oplus.wifi.smartant_band` | `2` | absent | Antenna tuning; unverified. |
| `ro.oplus.wifi.wsa` | `o` | absent | Antenna feature; unverified. |
| `ro.oplus.wifi.p2p.wowlan.enable` | `true` | absent | Wi-Fi P2P WoWLAN; unverified. |
| `ro.oplus.softap.switch.log.support` | `true` | absent | SoftAP logging; cosmetic. |
| `persist.bluetooth.support.sar` | `CN` | `IN\|EU\|FCC\|CE` | Regulatory SAR set; region-specific. |
| `persist.bluetooth.oplus.export.nv_overwrite_region` | absent | `true` | EU-only NV overwrite; leave. |
| `persist.sys.oplus.bt.qsh_ble_scan` | `true` | absent | BLE scan behavior; unverified. |

## Radio/telephony

CN-only keys include `ro.oplus.radio.global_regionlock.enabled=true`, `...regionlock.info=CN`, `...regionlockflag=6`, `ro.oplus.radio.hide_nr_switch=1`, `enable_cmcc_nitz=1`, `auto_nr_mode=3`, `dual_sim_coop_version=2`, `sub_slot_support_sa=1`, `wifi_data_power_mode=0`, `vonr_status=0`, `data_hongbao_ip`, `use_nitz_name=true`, plus a backoff/gamepaging config. EU-only or differing: `ro.oplus.radio.project=2`, `persist.vendor.entitlement_enabled=1`, `persist.vendor.radio.wait_for_pbm=0`, `w_oos_interval` 32000 vs 30000, `dual_nr_toggle_enabled` 1 vs true, `sub_slot_support_sa` 0 vs 1, `ro.telephony.default_network` 26,26 vs 27,26.

These are region/operator policy, not confirmed hardware requirements. The modem and `oplusstanvbk` pair is CN and deliberately preserved. Do not change without a telephony test plan.

In `my_region`, CN-only keys include `ro.oplus.radio.cn_ims_register`, `ro.vendor.oplus.radio.cn_nvbk`, `ro.vendor.oplus.radio.cn_use_3gpp2`, `ro.oplus.ltw.domestic`, `ro.oplus.bpf.region.support`, and `remote_provisioning.hostname` (CN server). EU-only/differing keys include `ro.vendor.oplus.radio.sar_regionmark=EUEX`, `ro.oem.key1=EUEX`, `ro.oplus.image.my_region.version_name=XEU0000`, `persist.vendor.rm_sensitive_data=1`, `ro.vendor.oplus.nwopt=true`, `ro.vendor.oplus.radio.always_send_plmn_name=true`, `ro.oplus.radio.user_nr_mode_by_sub=1`, and the region-specific time-sync URLs.

## Region identity (expected differences; do not "fix")

Model/name/device (`PHB110`/`PHB110`/`OP591BL1` vs `CPH2449`/`CPH2449EEA`/`OP594DL1`), all fingerprints, OTA/display IDs, image types (`22811` vs `22861`), `ro.oplus.pipeline_key` (`ALLNET` vs `EUEX`), `ro.oplus.pipeline.region` (`CN` vs `EUEX`), `ro.oplus.image.my_carrier.type` (`ALLNET_all` vs `empty`), preload type, market names, `ro.build.oplus_nv_id` (`10010111` vs `01000100`), `ro.vendor.oplus.regionmark` (`CN` vs `EUEX`), locale/timezone, build dates and incrementals, GMS client IDs, setup-wizard flags, and `ro.oplus.connectivity.oversea` (absent vs `true`).

`persist.sys.oplus.region` is CN vs US and is a user-facing region setting; change it through the UI if desired, not as a hardware fix.

## How these would be applied later (if approved)

- `persist.*`: `setprop persist.<key> <value>` then reboot. The value is stored in `/data/property/persistent_properties`.
- `ro.*`: read-only after property initialization. `setprop` cannot change them at runtime; a boot-time `resetprop` (KernelSU/Magisk-style) or an image edit/flash is required. Prefer no image edits.
- After any change, verify with `getprop` and re-check behavior; note that some keys exist in multiple partitions and effective precedence depends on load order.
