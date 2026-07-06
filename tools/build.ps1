param(
    [string]$Device = "gpsmaph1",
    [string]$SdkPath = "",
    [string]$DeveloperKey = "developer_key.der",
    [string]$Output = "bin/pics-viewer.prg"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

function Find-Monkeyc {
    param([string]$ExplicitSdkPath)

    if ($ExplicitSdkPath) {
        $candidate = Join-Path $ExplicitSdkPath "bin\monkeyc.bat"
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
        throw "monkeyc.bat was not found under SDK path: $ExplicitSdkPath"
    }

    $cmd = Get-Command monkeyc -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $roots = @(
        Join-Path $env:APPDATA "Garmin\ConnectIQ\Sdks",
        Join-Path $env:LOCALAPPDATA "Garmin\ConnectIQ\Sdks",
        Join-Path $env:USERPROFILE "Garmin\ConnectIQ\Sdks"
    )

    foreach ($root in $roots) {
        if (!(Test-Path $root)) {
            continue
        }

        $sdk = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object {
                $candidate = Join-Path $_.FullName "bin\monkeyc.bat"
                if (Test-Path $candidate) {
                    return (Resolve-Path $candidate).Path
                }
            } |
            Select-Object -First 1

        if ($sdk) {
            return $sdk
        }
    }

    throw "Connect IQ SDK was not found. Install it with Garmin SDK Manager, then rerun this script or pass -SdkPath."
}

if (!(Test-Path $DeveloperKey)) {
    throw "Developer key not found: $DeveloperKey. Generate one with the Connect IQ SDK tools or OpenSSL before building."
}

$monkeyc = Find-Monkeyc -ExplicitSdkPath $SdkPath
New-Item -ItemType Directory -Path (Split-Path $Output) -Force | Out-Null

& $monkeyc -d $Device -f "monkey.jungle" -o $Output -y $DeveloperKey
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Built $Output for $Device"
