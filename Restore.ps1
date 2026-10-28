[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$GamePath,[string]$ReceiptPath)
$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'Installer.Core.ps1')
    if (-not $GamePath) { $GamePath=Select-GameFolder }
    if (-not $GamePath) { Write-Output 'Cancelled. No files changed.'; exit 0 }
    if (-not $ReceiptPath) { $ReceiptPath=Select-Receipt $GamePath }
    if (-not $ReceiptPath) { Write-Output 'No restore selected. No files changed.'; exit 0 }
    Invoke-PatchRestore -GamePath $GamePath -ReceiptPath $ReceiptPath -WhatIf:$WhatIfPreference
} catch { Write-Error $_; exit 1 }
