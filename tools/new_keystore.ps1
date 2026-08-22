<#
.SYNOPSIS
    Generates the Android upload keystore and writes android\key.properties.

.DESCRIPTION
    Run once, before the first Play release. Everything it produces stays on
    this machine: the keystore is written where you choose, and the password
    is passed to keytool through an environment variable rather than the
    command line, so it never appears in the process list or your shell
    history.

    The keystore is the only thing that proves an update comes from you. Play
    refuses an upload signed with a different key, and there is no recovery
    path if it is lost — an app published under a key you cannot reproduce can
    never be updated again. Back it up somewhere that is not this laptop
    before you ship.

.EXAMPLE
    .\tools\new_keystore.ps1

.EXAMPLE
    .\tools\new_keystore.ps1 -KeystorePath "D:\keys\atomid-upload.jks"
#>
[CmdletBinding()]
param(
    # Default deliberately sits outside the repo. android\key.properties and
    # *.jks are git-ignored, but a keystore inside a working tree is one
    # careless `git add -f` from being public forever.
    [string] $KeystorePath = (Join-Path $env:USERPROFILE 'atomid-upload.jks'),
    [string] $Alias        = 'upload',
    [int]    $ValidityDays = 10000
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$PropsPath = Join-Path $Root 'android\key.properties'

function Write-Banner([string] $t) {
    Write-Host ''; Write-Host ('-' * 70) -ForegroundColor DarkGray
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ('-' * 70) -ForegroundColor DarkGray
}

# ------------------------------------------------------------------ keytool

function Find-Keytool {
    # Flutter, Android Studio and a standalone JDK all ship one, and which is
    # on PATH varies by machine. Any of them produces the same keystore.
    $c = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }

    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin\keytool.exe' }
    $candidates += @(
        "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
        "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\keytool.exe",
        "${env:ProgramFiles(x86)}\Android\Android Studio\jbr\bin\keytool.exe"
    )
    foreach ($p in $candidates) { if ($p -and (Test-Path $p)) { return $p } }

    foreach ($root in @("$env:ProgramFiles\Java", "$env:ProgramFiles\Eclipse Adoptium")) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Filter 'keytool.exe' -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

Write-Banner 'ANDROID UPLOAD KEYSTORE'

$keytool = Find-Keytool
if (-not $keytool) {
    throw "keytool.exe not found. It ships with any JDK and with Android Studio " +
          "(<studio>\jbr\bin). Set JAVA_HOME or add it to PATH, then re-run."
}
Write-Host "  keytool : $keytool" -ForegroundColor Gray
Write-Host "  keystore: $KeystorePath" -ForegroundColor Gray
Write-Host "  alias   : $Alias" -ForegroundColor Gray

# Never silently replace a keystore. If an app was published with the one
# already sitting there, overwriting it ends that app's update path.
if (Test-Path $KeystorePath) {
    throw "A keystore already exists at $KeystorePath. Refusing to overwrite it — " +
          "if an app was ever published with it, replacing it means that app can " +
          "never be updated. Point -KeystorePath somewhere else, or use the existing one."
}

# ------------------------------------------------------------------ identity

Write-Host ''
Write-Host '  Certificate identity. This is embedded in every build you sign and' -ForegroundColor Gray
Write-Host '  cannot be changed later. Press Enter to accept a default.' -ForegroundColor Gray
Write-Host ''

function Ask([string] $label, [string] $default) {
    $v = Read-Host "  $label [$default]"
    if ([string]::IsNullOrWhiteSpace($v)) { return $default }
    return $v
}

$cn = Ask 'Your name or company' 'Atomid'
$ou = Ask 'Organisational unit'  'Development'
$o  = Ask 'Organisation'         'Atomid'
$l  = Ask 'City'                 'Chennai'
$st = Ask 'State'                'Tamil Nadu'
$c  = Ask 'Country code'         'IN'
$dname = "CN=$cn, OU=$ou, O=$o, L=$l, ST=$st, C=$c"

# ------------------------------------------------------------------ password

Write-Host ''
$p1 = Read-Host '  Keystore password (min 6 chars)' -AsSecureString
$p2 = Read-Host '  Confirm password'                -AsSecureString

function Plain([Security.SecureString] $s) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

$pw = Plain $p1
if ($pw -ne (Plain $p2)) { throw 'The two passwords do not match. Nothing was created.' }
if ($pw.Length -lt 6)    { throw 'keytool requires at least 6 characters. Nothing was created.' }

# ------------------------------------------------------------------ generate

Write-Banner 'GENERATING'

# Through the environment, not the argument list: anything on a command line
# is readable by any other process on this machine while keytool runs, and
# lands in your shell history.
$env:ATOMID_KS_PW = $pw
try {
    & $keytool -genkeypair -v `
        -keystore $KeystorePath `
        -storetype JKS `
        -keyalg RSA -keysize 2048 `
        -validity $ValidityDays `
        -alias $Alias `
        -dname $dname `
        -storepass:env ATOMID_KS_PW `
        -keypass:env  ATOMID_KS_PW
    if ($LASTEXITCODE -ne 0) { throw "keytool failed with exit code $LASTEXITCODE." }

    if (-not (Test-Path $KeystorePath)) {
        throw 'keytool reported success but no keystore was written.'
    }

    # ----------------------------------------------------------- properties
    #
    # Gradle reads this as a java.util.Properties file, where a backslash
    # starts an escape sequence — a Windows path written verbatim silently
    # resolves to the wrong place, or to nothing.
    $escaped = $KeystorePath -replace '\\', '/'

    $props = @"
# Generated by tools/new_keystore.ps1. Git-ignored on purpose: this file and
# the keystore it points at are together enough to publish updates as this app.
#
# Keep a backup of BOTH somewhere that is not this machine. A lost keystore
# cannot be regenerated, and Play will not accept a replacement.
storePassword=$pw
keyPassword=$pw
keyAlias=$Alias
storeFile=$escaped
"@

    Set-Content -Path $PropsPath -Value $props -Encoding UTF8

    Write-Banner 'DONE'
    Write-Host "  keystore   : $KeystorePath" -ForegroundColor Green
    Write-Host "  properties : $PropsPath" -ForegroundColor Green
    Write-Host ''
    Write-Host '  Certificate fingerprints (Firebase and Play ask for these):' -ForegroundColor Cyan

    # Still inside the try: this needs the password, so the env var is cleared
    # in the finally below rather than the moment generation finished.
    $listing = & $keytool -list -v -keystore $KeystorePath -alias $Alias `
                   -storepass:env ATOMID_KS_PW 2>$null
    $prints = $listing | Select-String -Pattern 'SHA1:|SHA256:'
    if ($prints) {
        $prints | ForEach-Object { Write-Host "    $($_.Line.Trim())" -ForegroundColor Gray }
    } else {
        Write-Host '    (could not read them back — run keytool -list -v yourself)' -ForegroundColor Yellow
    }
}
finally {
    Remove-Item Env:\ATOMID_KS_PW -ErrorAction SilentlyContinue
    $pw = $null
}

Write-Host ''
Write-Host '  BACK UP the keystore and its password somewhere off this machine.' -ForegroundColor Yellow
Write-Host '  Losing them means this app can never be updated again.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  Next:  .\tools\build_release.ps1 -Aab' -ForegroundColor Cyan
Write-Host ''
