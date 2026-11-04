<#
OnePlus 11 (PHB110 / CPH2447 / CPH2449 / CPH2451) stock restore over fastboot, for Windows.
Rebuilds `super` from scratch, so it also fixes a phone whose logical partitions were deleted.

  flash-stock.bat <firmware.zip | folder of .img>  [-Recovery <recovery.img>] [-SkipPhysical]

Accepts: a full OTA zip (payload.bin), a zip or folder of loose .img files, or a package with super.img.
Not accepted: .ops/.ofp (MSM/EDL packages; those need the OPLUS download tool, not fastboot).

Phases:
  1. bootloader : every physical image to both slots (--slot=all). Failures are retried in fastbootd.
  2. fastbootd  : delete every logical partition still in super, create <name>_a + <name>_b, flash _a.
                  If the package has super.img, it is flashed whole in the bootloader instead.
  3. slot a active, then you Format data on the phone.
#>
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Firmware,
  [string]$Recovery,        # recovery to flash instead of the package's (if stock fastbootd can't create partitions)
  [switch]$SkipPhysical     # rerun only the super rebuild
)
$ErrorActionPreference = 'Stop'
$Root  = $PSScriptRoot
$Tools = Join-Path $Root 'tools'
$Work  = Join-Path $Root 'work'
$Log   = Join-Path $Root ("flash-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
New-Item -ItemType Directory -Force $Tools, $Work | Out-Null

function Say($m)  { Write-Host $m; Add-Content $Log $m }
function Die($m)  { Say "ERROR: $m"; Say "Log: $Log"; Read-Host 'Press Enter to exit'; exit 1 }
function Ask($m)  { if ((Read-Host "$m [y/N]") -notmatch '^[yY]') { Die 'aborted' } }

# Logical partitions OnePlus/OPLUS put in super. Anything else is physical.
$LogicalNames = 'system','system_ext','system_dlkm','system_dlkm_oki','system_dlkm_gki','product','vendor','vendor_dlkm',
                'odm','odm_dlkm','my_bigball','my_carrier','my_company','my_engineering','my_heytap','my_manifest',
                'my_preload','my_product','my_region','my_stock','my_custom','my_version'
# Never flashed: whole-super images handled separately, and our own scratch files.
$NeverFlash = 'super','super_empty'

# ---------- tools (downloaded on this PC, not bundled) ----------
$fb = Join-Path $Tools 'platform-tools\fastboot.exe'
if (-not (Test-Path $fb)) {
  Say 'Downloading Android platform-tools...'
  $z = Join-Path $Tools 'pt.zip'
  Invoke-WebRequest 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $z -UseBasicParsing
  Expand-Archive $z $Tools -Force; Remove-Item $z
}
$pdg = Join-Path $Tools 'payload-dumper-go.exe'
function Get-PayloadDumper {
  if (Test-Path $pdg) { return }
  Say 'Downloading payload-dumper-go...'
  $rel = Invoke-RestMethod 'https://api.github.com/repos/ssut/payload-dumper-go/releases/latest'
  $a = $rel.assets | Where-Object { $_.name -match 'windows_amd64\.tar\.gz$' } | Select-Object -First 1
  $t = Join-Path $Tools 'pdg.tar.gz'
  Invoke-WebRequest $a.browser_download_url -OutFile $t -UseBasicParsing
  tar -xzf $t -C $Tools; Remove-Item $t
  if (-not (Test-Path $pdg)) { Die 'payload-dumper-go.exe not found after extract' }
}

# fastboot writes to stderr; run through cmd so PowerShell doesn't turn that into errors.
function FB {
  $line = '"' + $fb + '" ' + ($args -join ' ')
  $out = cmd /c "$line 2>&1"
  $code = $LASTEXITCODE
  Add-Content $Log "> fastboot $($args -join ' ')"; Add-Content $Log ($out -join "`n")
  return [pscustomobject]@{ Ok = ($code -eq 0); Out = ($out -join "`n") }
}
function Show($r) { Write-Host $r.Out }

function Mode {
  $r = FB getvar is-userspace
  if ($r.Out -match 'is-userspace:\s*yes') { 'fastbootd' }
  elseif ($r.Out -match 'is-userspace:\s*no') { 'bootloader' }
  else { $null }
}
function Wait-Mode($want, $secs = 120) {
  for ($i = 0; $i -lt $secs; $i += 3) { if ((Mode) -eq $want) { return }; Start-Sleep 3 }
  Die "phone did not show up in $want within $secs s (check the USB driver in Device Manager)"
}

# ---------- 1. unpack firmware ----------
$fw = (Resolve-Path $Firmware).Path
$img = Join-Path $Work ([IO.Path]::GetFileNameWithoutExtension($fw))
if (Test-Path $fw -PathType Container) { $img = $fw }
elseif (-not (Test-Path (Join-Path $img '*.img'))) {
  New-Item -ItemType Directory -Force $img | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($fw)
  $names = $zip.Entries | ForEach-Object FullName
  $meta = $zip.Entries | Where-Object FullName -eq 'META-INF/com/android/metadata'
  if ($meta) {
    $sr = New-Object IO.StreamReader($meta.Open()); $m = $sr.ReadToEnd(); $sr.Close()
    Say '--- package metadata ---'
    $m -split "`n" | Where-Object { $_ -match '^(post-build|post-sdk-level|post-security-patch-level|version_name|pre-device)=' } | ForEach-Object { Say $_ }
  }
  $zip.Dispose()
  if ($names -match '\.(ops|ofp)$') { Die 'this is an MSM/EDL package (.ops/.ofp); fastboot cannot flash it. Use an OTA zip or a zip of .img files.' }
  if ($names -contains 'payload.bin') {
    Get-PayloadDumper
    Say "Extracting payload (several minutes)..."
    & $pdg -o $img $fw
    if ($LASTEXITCODE -ne 0) { Die 'payload extraction failed' }
  } elseif ($names -match '\.img$') {
    Say 'Unzipping images...'
    [IO.Compression.ZipFile]::ExtractToDirectory($fw, $img)
  } else { Die 'no payload.bin and no .img files in this zip' }
}
# images may sit in a subfolder (e.g. IMAGES/)
$all = Get-ChildItem $img -Recurse -Filter *.img
if (-not $all) { Die "no .img files under $img" }

# Slotted physical partitions on a OnePlus 11 (logs/partitions.txt). Only these get flashed, which keeps
# ddr, persist, static_nvbk, oplusreserve*, apdp and other unslotted or calibration data untouched.
$Slotted = 'abl','aop','aop_config','bluetooth','boot','cpucp','devcfg','dsp','dtbo','engineering_cdt','featenabler',
           'hyp','imagefv','init_boot','keymaster','mdtp','mdtpsecapp','modem','multiimgoem','multiimgqti','oplus_sec',
           'oplusstanvbk','qupfw','qweslicstore','recovery','rticmpdata','shrm','splash','tz','uefi','uefisecapp',
           'vbmeta','vbmeta_system','vbmeta_vendor','vendor_boot','vm-bootsys','xbl','xbl_config','xbl_ramdump'
$Alias = @{ 'logo' = 'splash' }   # factory RADIO/ names

$byName = @{}; $skipped = @()
# Physical: factory packages keep partition images in RADIO/ (prefer it), the rest at any level.
$phys = @($all | Where-Object { $_.Directory.Name -eq 'RADIO' }) + @($all | Where-Object { $_.Directory.Name -ne 'RADIO' })
foreach ($f in $phys) {
  $n = $f.BaseName; if ($Alias[$n]) { $n = $Alias[$n] }
  if ($Slotted -contains $n) { if (-not $byName[$n]) { $byName[$n] = $f.FullName } }
  elseif (($LogicalNames -notcontains ($f.BaseName -split '\.')[0]) -and ($NeverFlash -notcontains $n)) { $skipped += $f.BaseName }
}
# Logical: factory packages have tiny pointer stubs (my_stock.img = 30 bytes) plus the real image in a subfolder
# (my_stock/my_stock.20961727.img). Take the largest file per partition name; ignore anything under 4 KiB.
foreach ($p in $LogicalNames) {
  $c = $all | Where-Object { (($_.BaseName -split '\.')[0] -eq $p) -and $_.Length -ge 4096 } | Sort-Object Length -Descending | Select-Object -First 1
  if ($c) { $byName[$p] = $c.FullName }
}
foreach ($s in 'super') { $c = $all | Where-Object BaseName -eq $s | Select-Object -First 1; if ($c) { $byName[$s] = $c.FullName } }
if ($skipped) { Say "not flashed (unslotted/calibration/duplicates): $(($skipped | Sort-Object -Unique) -join ' ')" }

# my_company / my_preload exist only in factory packages; OTAs lack them. Fall back to koaaN/Universal_Flasher's copies.
foreach ($p in 'my_company','my_preload') {
  if (-not $byName[$p]) {
    $dst = Join-Path $Tools "$p.img"
    if (-not (Test-Path $dst)) {
      Say "$p.img not in package; using koaaN/Universal_Flasher's copy"
      Invoke-WebRequest "https://raw.githubusercontent.com/koaaN/Universal_Flasher/main/OTA_FILES_HERE/$p.img" -OutFile $dst -UseBasicParsing
    }
    $byName[$p] = $dst
  }
}
if ($Recovery) { $byName['recovery'] = (Resolve-Path $Recovery).Path }

$logical  = $byName.Keys | Where-Object { $LogicalNames -contains $_ } | Sort-Object
$physical = $byName.Keys | Where-Object { ($LogicalNames -notcontains $_) -and ($NeverFlash -notcontains $_) } | Sort-Object
$superImg = $byName['super']
Say "physical ($($physical.Count)): $($physical -join ' ')"
if ($superImg) { Say "super.img present: will flash it whole" } else { Say "logical ($($logical.Count)): $($logical -join ' ')" }
foreach ($need in 'system','vendor','product','odm','boot','vbmeta') {
  if (-not $byName[$need] -and -not ($superImg -and $LogicalNames -contains $need)) { Die "package has no $need.img; not a full firmware" }
}

# ---------- 2. device ----------
Say "`nPut the phone in the bootloader (Power + Vol Down, 'FASTBOOT MODE') and connect USB."
Wait-Mode 'bootloader' 300
$r = FB getvar product;  Say $r.Out
$r = FB getvar unlocked; Say $r.Out
if ($r.Out -notmatch 'unlocked:\s*yes') { Die 'bootloader is locked; fastboot cannot flash' }
$r = FB getvar current-slot; Say $r.Out
Say "`nThis flashes every image above to BOTH slots, deletes all logical partitions in super and recreates them."
Say 'Downgrading Android needs a data format at the end (all data is lost).'
Ask 'Continue?'

# ---------- 3. physical, bootloader ----------
$failed = @()
if (-not $SkipPhysical) {
  Say "`n== bootloader: physical partitions"
  foreach ($p in $physical) {
    $r = FB flash --slot=all $p "`"$($byName[$p])`""
    if ($r.Ok) { Say "OK    $p" } else { Say "RETRY $p  ($(($r.Out -split "`n" | Select-String 'FAILED|error' | Select-Object -First 1)))"; $failed += $p }
  }
  if ($superImg) {
    Say 'flashing super.img (large, takes a while)...'
    $r = FB flash super "`"$superImg`""; Show $r
    if (-not $r.Ok) { Die 'super.img flash failed' }
  }
}

# ---------- 4. fastbootd ----------
Say "`n== rebooting to fastbootd (choose English on the phone if asked)"
FB reboot fastboot | Out-Null
Wait-Mode 'fastbootd' 180

$still = @()
foreach ($p in $failed) {
  $r = FB flash --slot=all $p "`"$($byName[$p])`""
  if (-not $r.Ok) { $r = FB flash $p "`"$($byName[$p])`"" }   # unslotted partition
  if ($r.Ok) { Say "OK    $p (fastbootd)" } else { Say "FAIL  $p"; $still += $p }
}

if (-not $superImg) {
  Say "`n== fastbootd: rebuild super"
  FB snapshot-update cancel | Out-Null
  $r = FB create-logical-partition probe_a 4096
  if ($r.Ok) { $r = FB delete-logical-partition probe_a }
  if (-not $r.Ok) {
    Show $r
    Die "this fastbootd can't create logical partitions. Rerun with a LineageOS recovery: flash-stock.bat `"$Firmware`" -Recovery recovery.img -SkipPhysical (after flashing it: fastboot flash recovery recovery.img)"
  }
  # Clean slate: delete everything currently logical, including stray unslotted names and -cow leftovers.
  $vars = (FB getvar all).Out
  $existing = [regex]::Matches($vars, 'is-logical:([^:\s]+):yes') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
  foreach ($e in $existing) { FB delete-logical-partition $e | Out-Null; Say "deleted $e" }
  $left = [regex]::Matches((FB getvar all).Out, 'is-logical:([^:\s]+):yes').Count
  if ($left -ne 0) { Die "$left logical partitions still present after delete" }

  # OnePlus Virtual A/B layout: <name>_a full, <name>_b 1-byte placeholder (koaaN/Universal_Flasher, PHB110 tested).
  foreach ($p in $logical) {
    $a = FB create-logical-partition "${p}_a" 1
    $b = FB create-logical-partition "${p}_b" 1
    $f = FB flash "${p}_a" "`"$($byName[$p])`""
    if ($a.Ok -and $b.Ok -and $f.Ok) { Say "OK    $p" }
    elseif ($f.Ok -and $f.Out -match 'Invalid sparse file format') { Say "OK    $p (sparse warning is harmless)" }
    else { Say "FAIL  $p"; Write-Host $f.Out; $still += $p }
  }
  $n = [regex]::Matches((FB getvar all).Out, 'is-logical:[^:\s]+_a:yes').Count
  Say "logical _a partitions now: $n (expected $($logical.Count))"
  if ($n -lt $logical.Count) { $still += 'super-layout' }
}

FB --set-active=a | Out-Null
Say "`n== summary"
if ($still) {
  Say "FAILED: $($still -join ' ')"
  Say 'Do NOT boot Android. Send the log; rerun with -SkipPhysical after fixing.'
  Say "Log: $Log"; Read-Host 'Press Enter to exit'; exit 1
}
Say 'All partitions written, slot a active.'
Say 'Now on the phone (still fastbootd/recovery screen): Format data -> confirm. It reboots into Android afterwards.'
Say "Log: $Log"
Read-Host 'Press Enter to exit'
