param(
    [string]$ProfilePath = "$env:APPDATA\r2modmanPlus-local\Valheim\profiles\Modded",
    [string]$OutputZip = "$env:USERPROFILE\Desktop\valheim-server-mods.zip"
)

$ErrorActionPreference = "Stop"

$items = @(
    "BepInEx\plugins",
    "BepInEx\config",
    "doorstop_libs",
    ".doorstop_version",
    "doorstop_config.ini",
    "start_server_bepinex.sh"
)

$staging = Join-Path $env:TEMP "valheim-server-mods"
if (Test-Path $staging) {
    Remove-Item -Recurse -Force $staging
}

New-Item -ItemType Directory -Path $staging | Out-Null

foreach ($item in $items) {
    $source = Join-Path $ProfilePath $item
    if (-not (Test-Path $source)) {
        Write-Error "Missing required profile item: $source"
    }

    $destination = Join-Path $staging $item
    $destinationParent = Split-Path $destination -Parent
    if (-not (Test-Path $destinationParent)) {
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }

    Copy-Item -Path $source -Destination $destination -Recurse -Force
}

if (Test-Path $OutputZip) {
    Remove-Item -Force $OutputZip
}

Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $OutputZip -Force
Write-Output "Created $OutputZip"
