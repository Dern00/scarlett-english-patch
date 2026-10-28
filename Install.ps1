[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$GamePath)
$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'Installer.Core.ps1')
    if (-not $GamePath) { $GamePath=Select-GameFolder }
    if (-not $GamePath) { Write-Output 'Cancelled. No files changed.'; exit 0 }
    Invoke-PatchInstall -GamePath $GamePath -PackageRoot $PSScriptRoot -WhatIf:$WhatIfPreference
} catch { Write-Error $_; exit 1 }
