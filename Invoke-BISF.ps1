#requires -Version 5.1
<#
.SYNOPSIS
Local PowerShell-only image preparation, preview and clone personalization.
.DESCRIPTION
Unofficial reduced-scope derivative of EUCweb BIS-F 7.1912.7.
Modified 2026-10-12. GPL-3.0. See LICENSE, UPSTREAM.md and README.md.
Configuration defaults to GlobalConfig.xml beside this script. Default mode Validate
performs no image changes; enabled logging may create diagnostic log files.
.EXAMPLE
.\Invoke-BISF.ps1 -Mode Prepare -WhatIf
.EXAMPLE
.\Invoke-BISF.ps1 -Mode Prepare
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
    [ValidateSet('Validate','Prepare','Personalize','Finalize')][string]$Mode='Validate',
    [string]$ConfigPath=(Join-Path $PSScriptRoot 'GlobalConfig.xml')
)
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'Modules/BISF.Local.psm1') -Force -ErrorAction Stop
    if ($Mode -eq 'Finalize') {
        # This is only used by the protected SYSTEM task; the module verifies
        # the machine identity, staged state, calling SID and unloaded profile.
        exit [int](Invoke-BISFOperatorSealFinalizer -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath)
    }
    $arguments=@{ConfigPath=$ConfigPath;ScriptRoot=$PSScriptRoot;Mode=$Mode}
    if ($PSBoundParameters.ContainsKey('WhatIf')) { $arguments.WhatIf=$PSBoundParameters.WhatIf }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $arguments.Confirm=$PSBoundParameters.Confirm }
    $result=Invoke-BISFLocal @arguments
    exit $result.ExitCode
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
