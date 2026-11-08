# Windows stock restore (fastboot)

Restores OnePlus 11 stock firmware over fastboot. Use it when EDL doesn't work. It rebuilds `super` from scratch, so it also fixes a phone whose logical partitions were deleted.

## Use
1. Install the [Google USB driver](https://developer.android.com/studio/run/win-usb). The phone needs to show up in both the bootloader and fastbootd.
2. Phone: Power + Vol Down until you see FASTBOOT MODE. Connect USB.
3. Drag the firmware zip onto `flash-stock.bat`, or run `flash-stock.bat PHB110domestic_11_A.29_2023101920110124.zip`.
4. When it finishes without `FAILED`, choose Format data on the phone.

On the first run it downloads platform-tools and payload-dumper-go into `windows\tools\`. Images get unpacked to `windows\work\` (~15 GB free needed). Every fastboot call goes into `flash-*.log`.

## What it does
- Reads the package: full OTA (`payload.bin`), a zip or folder of `.img` files, or a package that ships a full `super.img`. MSM/EDL packages (`.ops`/`.ofp`) are refused.
- **Bootloader:** writes every physical image to both slots. Anything the bootloader refuses (e.g. `modem`) is retried in fastbootd.
- **fastbootd:**
  - Deletes every logical partition still in `super`, including stray unslotted names and `-cow` leftovers.
  - Creates `<name>_a` and an empty (0-byte) `<name>_b` for each image, then flashes `_a`. `_a` sizes come from the package's `super_def.*.json` when present, else from the image file. This matches the factory super layout.
- If the package has no `my_company`/`my_preload` (OTAs don't), it uses the copies from koaaN/Universal_Flasher.
- Sets slot a active.

## If stock fastbootd can't create partitions
The script probes this first and stops before deleting anything. Flash a LineageOS `recovery.img` from the bootloader, then rerun the super step:

    fastboot flash recovery recovery.img
    flash-stock.bat <zip> -Recovery recovery.img -SkipPhysical

## Downgrades
Going to an older Android (e.g. ColorOS 13 A.29) needs Format data. The OnePlus 11 has no fused anti-rollback counter, but the script can't verify that for you.
