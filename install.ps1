# install.ps1 - Installs (or removes) the Claude Code "done" toast hook.
#
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
#
# What it does:
#   1. Copies done-toast.ps1 to %USERPROFILE%\.claude\hooks\
#   2. Registers a Stop hook in %USERPROFILE%\.claude\settings.json
#      (existing settings are preserved; a timestamped .bak is written first)

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [string]$ClaudeDir = (Join-Path $env:USERPROFILE '.claude')
)

$ErrorActionPreference = 'Stop'

$scriptName  = 'done-toast.ps1'
$source      = Join-Path $PSScriptRoot $scriptName
$hooksDir    = Join-Path $ClaudeDir 'hooks'
$target      = Join-Path $hooksDir $scriptName
$settingsPath = Join-Path $ClaudeDir 'settings.json'

# Claude Code reads settings.json with a JSON parser that chokes on a BOM,
# so always write UTF-8 without one.
function Write-JsonFile($path, $object) {
    $json = $object | ConvertTo-Json -Depth 100
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
}

function Read-Settings($path) {
    if (-not (Test-Path $path)) { return [pscustomobject]@{} }
    $raw = Get-Content -Path $path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{} }
    return $raw | ConvertFrom-Json
}

function Backup-Settings($path) {
    if (-not (Test-Path $path)) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = "$path.bak-$stamp"
    Copy-Item $path $bak -Force
    return $bak
}

# ConvertFrom-Json returns PSCustomObject. On an object with no properties,
# .PSObject.Properties.Name is $null, so wrap it before testing membership.
function Test-HasProperty($obj, $name) {
    return (@($obj.PSObject.Properties.Name) -contains $name)
}

function Ensure-Property($obj, $name, $default) {
    if (-not (Test-HasProperty $obj $name)) {
        $obj | Add-Member -MemberType NoteProperty -Name $name -Value $default
    }
    return $obj.$name
}

function Get-StopGroups($settings) {
    $hooks = Ensure-Property $settings 'hooks' ([pscustomobject]@{})
    $null  = Ensure-Property $hooks 'Stop' @()
    return $hooks
}

function Test-IsOurGroup($group) {
    if (-not $group.hooks) { return $false }
    foreach ($h in @($group.hooks)) {
        if ($h.command -and $h.command -like "*$scriptName*") { return $true }
    }
    return $false
}

# --------------------------------------------------------------------------

if ($Uninstall) {
    Write-Host 'Removing the Claude Code done-toast hook...'

    if (Test-Path $settingsPath) {
        $settings = Read-Settings $settingsPath
        $hooks = $settings.hooks
        if ($hooks -and (Test-HasProperty $hooks 'Stop')) {
            $kept = @(@($hooks.Stop) | Where-Object { -not (Test-IsOurGroup $_) })
            $bak = Backup-Settings $settingsPath
            if ($kept.Count -eq 0) {
                $hooks.PSObject.Properties.Remove('Stop')
            } else {
                $hooks.Stop = $kept
            }
            if (@($hooks.PSObject.Properties.Name).Count -eq 0) {
                $settings.PSObject.Properties.Remove('hooks')
            }
            Write-JsonFile $settingsPath $settings
            Write-Host "  settings.json updated (backup: $bak)"
        } else {
            Write-Host '  no Stop hook found in settings.json'
        }
    }

    if (Test-Path $target) {
        Remove-Item $target -Force
        Write-Host "  removed $target"
    }

    Write-Host 'Done. Restart Claude Code to apply.'
    return
}

# --- install ---------------------------------------------------------------

if (-not (Test-Path $source)) {
    throw "$scriptName not found next to install.ps1 (looked in $PSScriptRoot)"
}

Write-Host 'Installing the Claude Code done-toast hook...'

if (-not (Test-Path $hooksDir)) { New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null }
Copy-Item $source $target -Force
Write-Host "  copied  -> $target"

# Forward slashes avoid backslash-escaping headaches inside JSON.
$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f ($target -replace '\\', '/')

$newGroup = [pscustomobject]@{
    hooks = @(
        [pscustomobject][ordered]@{
            type    = 'command'
            command = $command
            async   = $true      # without this, Claude Code blocks until the toast is clicked
        }
    )
}

$settings = Read-Settings $settingsPath
$hooks = Get-StopGroups $settings

$existing = @(@($hooks.Stop) | Where-Object { -not (Test-IsOurGroup $_) })
$hooks.Stop = @($existing + $newGroup)

$bak = Backup-Settings $settingsPath
Write-JsonFile $settingsPath $settings

if ($bak) { Write-Host "  settings.json updated (backup: $bak)" }
else      { Write-Host "  created $settingsPath" }

Write-Host ''
Write-Host 'Done. Restart Claude Code, then run any prompt - a toast should appear'
Write-Host 'in the bottom-right corner when the turn finishes.'
