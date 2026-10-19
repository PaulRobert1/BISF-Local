#requires -Version 5.1
<#
.SYNOPSIS
Local PowerShell-only image preparation, preview and clone personalization.
.DESCRIPTION
Unofficial reduced-scope derivative of EUCweb BIS-F 7.1912.7.
Modified 2026-10-12. GPL-3.0. See LICENSE, UPSTREAM.md and README.md.
Configuration defaults to GlobalConfig.xml beside this script. Default mode Prepare applies enabled cleanup. Use -Mode Validate for checks only
or -Mode Prepare -WhatIf to preview without applying image operations.
.EXAMPLE
.\Invoke-BISF.ps1 -Mode Prepare -WhatIf
.EXAMPLE
.\Invoke-BISF.ps1 -Mode Prepare
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
    [ValidateSet('Validate','Prepare','Personalize','Finalize','VerifyClone')][string]$Mode='Prepare',
    [string]$ConfigPath
)
$ErrorActionPreference='Stop'
try {
    # Windows PowerShell 5.1 may leave PSScriptRoot empty during parameter binding.
    # Resolve the default only after entering the script; preserve explicit paths.
    if (-not $PSBoundParameters.ContainsKey('ConfigPath')) {
        $ConfigPath=Join-Path $PSScriptRoot 'GlobalConfig.xml'
    }
    Import-Module (Join-Path $PSScriptRoot 'Modules/BISF.Local.psm1') -Force -ErrorAction Stop
    if ($Mode -eq 'VerifyClone') {
        # Read-only local inventory; never applies image operations or writes logs.
        $null=Invoke-BISFCloneVerification -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath
        exit 0
    }
    if ($Mode -eq 'Finalize') {
        # This is only used by the protected SYSTEM task; the module verifies
        # the machine identity, staged state, calling SID and unloaded profile.
        $finalArguments=@{ScriptRoot=$PSScriptRoot;ConfigPath=$ConfigPath}
        if ($PSBoundParameters.ContainsKey('WhatIf')) { $finalArguments.WhatIf=$PSBoundParameters.WhatIf }
        if ($PSBoundParameters.ContainsKey('Confirm')) { $finalArguments.Confirm=$PSBoundParameters.Confirm }
        exit [int](Invoke-BISFOperatorSealFinalizer @finalArguments)
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

