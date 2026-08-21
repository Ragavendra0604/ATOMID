<#
.SYNOPSIS
    Builds Atomid Store release artifacts for Android and Windows and collects
    them into dist\.

.DESCRIPTION
    Runs the full release pipeline in one pass: dependency resolution, Hive
    code generation, then the platform builds. Every artifact is copied into
    dist\ under a versioned name with its SHA-256, so what you hand over is
    never ambiguous about which build it came from.

    Mobile is built before desktop, so an Android failure stops you before the
    much slower Windows build starts.

.EXAMPLE
    .\tools\build_release.ps1
    Android APK + Windows release build.

.EXAMPLE
    .\tools\build_release.ps1 -Aab -SplitAbi -Installer
    Everything: universal APK, per-ABI APKs, Play bundle, Windows build and
    an Inno Setup installer.

.EXAMPLE
    .\tools\build_release.ps1 -Target desktop -Installer
    Desktop only. Produces a single self-contained AtomidSetup .exe and
    nothing else.
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'mobile', 'desktop')]
    [string] $Target = 'all',

    # Android extras
    [switch] $Aab,              # Play Store app bundle
    [switch] $SplitAbi,         # per-ABI APKs (much smaller downloads)

    # Windows extras
    [switch] $Installer,        # Inno Setup -> AtomidSetup.exe (self-contained)
    [switch] $Msix,             # MSIX package
    [switch] $Portable,         # also emit a no-installer zip of the Release folder

    [switch] $Clean,            # flutter clean first
    [switch] $SkipCodegen,      # skip build_runner (only if adapters are current)

    # Explicit path to ISCC.exe, if auto-discovery cannot find your install.
    [string] $IsccPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$script:Started  = Get-Date
$script:Steps    = @()
$script:Artifacts = @()

# ----------------------------------------------------------------- helpers

function Write-Banner([string] $Text) {
    Write-Host ''
    Write-Host ('─' * 74) -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('─' * 74) -ForegroundColor DarkGray
}

function Write-Info([string] $Text)  { Write-Host "  $Text" -ForegroundColor Gray }
function Write-Good([string] $Text)  { Write-Host "  $Text" -ForegroundColor Green }
function Write-Warn2([string] $Text) { Write-Host "  ! $Text" -ForegroundColor Yellow }

function Invoke-Step {
    param(
        [Parameter(Mandatory)] [string]   $Name,
        [Parameter(Mandatory)] [scriptblock] $Body
    )
    Write-Banner $Name
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Body
    if ($LASTEXITCODE -ne 0) {
        $sw.Stop()
        $script:Steps += [pscustomobject]@{ Step = $Name; Result = 'FAILED'; Seconds = [math]::Round($sw.Elapsed.TotalSeconds) }
        Show-Summary
        throw "$Name failed with exit code $LASTEXITCODE. Nothing further was built."
    }
    $sw.Stop()
    $script:Steps += [pscustomobject]@{ Step = $Name; Result = 'ok'; Seconds = [math]::Round($sw.Elapsed.TotalSeconds) }
    Write-Good ("done in {0}s" -f [math]::Round($sw.Elapsed.TotalSeconds))
}

function Add-Artifact {
    param([string] $Path, [string] $As)

    if (-not (Test-Path $Path)) {
        Write-Warn2 "expected artifact missing: $Path"
        return
    }
    $dest = Join-Path $DistDir $As
    Copy-Item $Path $dest -Force
    $item = Get-Item $dest
    $script:Artifacts += [pscustomobject]@{
        Artifact = $As
        SizeMB   = [math]::Round($item.Length / 1MB, 2)
        SHA256   = (Get-FileHash $dest -Algorithm SHA256).Hash.Substring(0, 16) + '...'
    }
    Write-Good "collected  $As  ($([math]::Round($item.Length/1MB,2)) MB)"
}

function Find-Iscc {
    <#
      Inno Setup does not install to one predictable place: the version number
      is in the folder name, it may be 32- or 64-bit, and a per-user install
      lands under LOCALAPPDATA instead of Program Files. Checking two fixed
      paths misses most of those, so work outwards from cheapest to most
      thorough and stop at the first hit.
    #>
    param([string] $Explicit)

    if ($Explicit) {
        if (Test-Path $Explicit) { return (Resolve-Path $Explicit).Path }
        throw "-IsccPath was given but does not exist: $Explicit"
    }

    # 1. already on PATH
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # 2. the uninstall registry entry, which records the real install dir
    foreach ($hive in 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node', 'HKCU:\SOFTWARE') {
        $key = Join-Path $hive 'Microsoft\Windows\CurrentVersion\Uninstall'
        if (-not (Test-Path $key)) { continue }
        $hit = Get-ChildItem $key -ErrorAction SilentlyContinue |
               ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
               Where-Object { $_.DisplayName -like 'Inno Setup*' -and $_.InstallLocation } |
               ForEach-Object { Join-Path $_.InstallLocation 'ISCC.exe' } |
               Where-Object { Test-Path $_ } |
               Select-Object -First 1
        if ($hit) { return $hit }
    }

    # 3. versioned folders in the usual roots, newest first
    $roots = @(
        "${env:ProgramFiles(x86)}",
        $env:ProgramFiles,
        "$env:LOCALAPPDATA\Programs",
        "$env:ProgramData\chocolatey\lib\innosetup\tools"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $hit = Get-ChildItem $root -Filter 'Inno Setup*' -Directory -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending |
               ForEach-Object { Join-Path $_.FullName 'ISCC.exe' } |
               Where-Object { Test-Path $_ } |
               Select-Object -First 1
        if ($hit) { return $hit }

        $direct = Join-Path $root 'ISCC.exe'
        if (Test-Path $direct) { return $direct }
    }

    # 4. bounded recursive sweep of the program folders as a last resort
    foreach ($root in $roots) {
        $hit = Get-ChildItem $root -Filter 'ISCC.exe' -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }

    return $null
}

function Show-Summary {
    Write-Banner 'BUILD SUMMARY'
    $script:Steps | Format-Table -AutoSize | Out-String | Write-Host
    if ($script:Artifacts.Count) {
        Write-Host '  Artifacts in dist\' -ForegroundColor Cyan
        $script:Artifacts | Format-Table -AutoSize | Out-String | Write-Host
    }
    $elapsed = (Get-Date) - $script:Started
    Write-Host ("  Total elapsed: {0:mm}m {0:ss}s" -f $elapsed) -ForegroundColor DarkGray
    Write-Host ''
}

# ----------------------------------------------------------------- preflight

Write-Banner 'PREFLIGHT'

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    throw "flutter is not on PATH. Add <flutter-sdk>\bin to PATH and reopen the shell."
}
Write-Info "flutter : $($flutter.Source)"

# Version straight out of pubspec, so artifact names always match the build.
$pubspec = Get-Content (Join-Path $Root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
    throw "Could not parse 'version:' from pubspec.yaml."
}
$AppVersion = $Matches[1]
$BuildNumber = $Matches[2]
$Stamp = Get-Date -Format 'yyyyMMdd-HHmm'
Write-Info "version : $AppVersion+$BuildNumber   (stamp $Stamp)"

$DistDir = Join-Path $Root 'dist'
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
Write-Info "output  : $DistDir"

# Release signing. Absent keystore is legal but produces a debug-signed build
# that Play rejects, so say it once, loudly, rather than letting it slip into
# a handover.
$DebugSigned = $false
if (-not (Test-Path (Join-Path $Root 'android\key.properties'))) {
    $DebugSigned = $true
    Write-Warn2 'android\key.properties not found — Android release builds will be DEBUG-SIGNED.'
    Write-Warn2 'Fine for sideloading and client testing. Google Play will reject it.'
    Write-Warn2 'See the "Release signing (Android)" section of README.md to create a keystore.'
}
else {
    Write-Good 'release keystore configured'
}

# Firebase keys its Android config on the exact applicationId; a mismatch fails
# the build late with a confusing message, so check it early.
$gsj = Join-Path $Root 'android\app\google-services.json'
if (Test-Path $gsj) {
    if ((Get-Content $gsj -Raw) -notmatch 'com\.atomid\.store') {
        Write-Warn2 'google-services.json does not mention com.atomid.store — expect "No matching client found".'
        Write-Warn2 'Rerun: flutterfire configure'
    }
    else { Write-Good 'google-services.json matches com.atomid.store' }
}

# ----------------------------------------------------------------- common

if ($Clean) {
    Invoke-Step 'flutter clean' { flutter clean }
}

Invoke-Step 'Resolve dependencies' { flutter pub get }

if (-not $SkipCodegen) {
    # --delete-conflicting-outputs was removed in build_runner 2.16; deleting
    # conflicting outputs is the default now and the flag only prints a warning.
    Invoke-Step 'Generate Hive adapters (build_runner)' {
        dart run build_runner build
    }
}

# ----------------------------------------------------------------- mobile

if ($Target -in @('all', 'mobile')) {

    Invoke-Step 'Android — release APK (universal)' {
        flutter build apk --release
    }
    $suffix = if ($DebugSigned) { '-DEBUGSIGNED' } else { '' }
    Add-Artifact 'build\app\outputs\flutter-apk\app-release.apk' `
                 "atomid-$AppVersion+$BuildNumber-$Stamp-universal$suffix.apk"

    if ($SplitAbi) {
        Invoke-Step 'Android — per-ABI APKs' {
            flutter build apk --release --split-per-abi
        }
        foreach ($abi in 'armeabi-v7a', 'arm64-v8a', 'x86_64') {
            Add-Artifact "build\app\outputs\flutter-apk\app-$abi-release.apk" `
                         "atomid-$AppVersion+$BuildNumber-$Stamp-$abi$suffix.apk"
        }
    }

    if ($Aab) {
        Invoke-Step 'Android — Play app bundle' {
            flutter build appbundle --release
        }
        Add-Artifact 'build\app\outputs\bundle\release\app-release.aab' `
                     "atomid-$AppVersion+$BuildNumber-$Stamp$suffix.aab"
    }
}

# ----------------------------------------------------------------- desktop

if ($Target -in @('all', 'desktop')) {

    Invoke-Step 'Windows — release build' {
        flutter build windows --release
    }

    $ReleaseDir = Join-Path $Root 'build\windows\x64\runner\Release'
    if (-not (Test-Path $ReleaseDir)) {
        throw "Windows build reported success but $ReleaseDir does not exist."
    }

    # Opt-in only. The Inno Setup installer is already self-contained, so for
    # most handovers the zip is a second copy of the same bytes.
    if ($Portable) {
        Write-Banner 'Windows — portable zip'
        $zip = Join-Path $DistDir "atomid-$AppVersion+$BuildNumber-$Stamp-windows-x64-portable.zip"
        if (Test-Path $zip) { Remove-Item $zip -Force }
        Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $zip -CompressionLevel Optimal
        $zi = Get-Item $zip
        $script:Artifacts += [pscustomobject]@{
            Artifact = Split-Path $zip -Leaf
            SizeMB   = [math]::Round($zi.Length / 1MB, 2)
            SHA256   = (Get-FileHash $zip -Algorithm SHA256).Hash.Substring(0, 16) + '...'
        }
        Write-Good "collected  $(Split-Path $zip -Leaf)  ($([math]::Round($zi.Length/1MB,2)) MB)"
    }

    if ($Installer) {
        Write-Banner 'Windows — Inno Setup installer'

        $iscc = Find-Iscc -Explicit $IsccPath

        if (-not $iscc) {
            Write-Warn2 'ISCC.exe not found — skipping installer.'
            Write-Warn2 'Inno Setup is installed but not where this script looked. Find it with:'
            Write-Warn2 '  Get-ChildItem C:\ -Filter ISCC.exe -Recurse -ErrorAction SilentlyContinue | Select FullName'
            Write-Warn2 'then re-run with:  -IsccPath "<full path to ISCC.exe>"'
        }
        else {
            Write-Info "iscc    : $iscc"

            # setup.iss ships one machine's CRT path and it goes stale on every
            # VS update. Discover the real one and override rather than editing
            # the file.
            # Match on the files, not the folder name: 'Microsoft.VC*.CRT' also
            # matches Microsoft.VC*.DebugCRT, which holds msvcp140d.dll rather
            # than msvcp140.dll. That folder is not redistributable and would
            # fail the compile with a confusing missing-file error.
            $crt = Get-ChildItem -Path 'C:\Program Files*\Microsoft Visual Studio' `
                        -Filter 'Microsoft.VC*.CRT' -Recurse -Directory -ErrorAction SilentlyContinue |
                   Where-Object {
                       $_.FullName -match '\\x64\\' -and
                       $_.Name -notmatch 'Debug' -and
                       (Test-Path (Join-Path $_.FullName 'msvcp140.dll')) -and
                       (Test-Path (Join-Path $_.FullName 'vcruntime140.dll')) -and
                       (Test-Path (Join-Path $_.FullName 'vcruntime140_1.dll'))
                   } |
                   Sort-Object FullName -Descending | Select-Object -First 1

            if (-not $crt) {
                Write-Warn2 'No x64 redistributable CRT folder containing msvcp140.dll was found.'
                Write-Warn2 'That usually means the "Desktop development with C++" workload is missing.'
                Write-Warn2 'Falling back to the default path baked into setup.iss.'
                & $iscc 'setup.iss'
            }
            else {
                Write-Info "crt     : $($crt.FullName)"
                & $iscc "/DCrtDir=$($crt.FullName)" 'setup.iss'
            }

            if ($LASTEXITCODE -ne 0) {
                Write-Warn2 "ISCC exited $LASTEXITCODE — installer not produced."
            }
            else {
                Add-Artifact 'build\windows\installer\AtomidSetup.exe' `
                             "AtomidSetup-$AppVersion+$BuildNumber-$Stamp.exe"
            }
        }
    }

    if ($Msix) {
        Invoke-Step 'Windows — MSIX package' { dart run msix:create }
        $found = Get-ChildItem $ReleaseDir -Filter '*.msix' -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) {
            Add-Artifact $found.FullName "atomid-$AppVersion+$BuildNumber-$Stamp.msix"
        }
        else {
            Write-Warn2 'msix:create reported success but no .msix was found.'
        }
    }
}

# ----------------------------------------------------------------- done

if ($Target -in @('all', 'desktop') -and -not ($Installer -or $Msix -or $Portable)) {
    Write-Warn2 'Windows was built but not packaged. Add -Installer for a single self-contained .exe.'
    Write-Warn2 "The raw build is at build\windows\x64\runner\Release"
}

Show-Summary

if ($DebugSigned -and $Target -in @('all', 'mobile')) {
    Write-Host '  REMINDER: Android artifacts above are debug-signed and cannot go to Google Play.' -ForegroundColor Yellow
    Write-Host ''
}

Write-Host "  All artifacts: $DistDir" -ForegroundColor Cyan
Write-Host ''
