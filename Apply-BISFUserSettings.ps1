#requires -Version 5.1
[CmdletBinding()]param([switch]$RemoveQuickAccess,[switch]$ClassicContextMenu)
$ErrorActionPreference='Stop'
try {
 Import-Module (Join-Path $PSScriptRoot 'Modules/BISF.Local.psm1') -Force -ErrorAction Stop
 Invoke-BISFUserCustomizations -RemoveQuickAccess:$RemoveQuickAccess -ClassicContextMenu:$ClassicContextMenu
 exit 0
} catch {Write-Error $_;exit 1}
