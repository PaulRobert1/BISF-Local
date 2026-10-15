# BIS-F Local, unofficial derivative. Modified 2026-10-12. GPL-3.0; see LICENSE.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
foreach ($name in @('Configuration','Logging','Preflight','Operations','Lifecycle','Citrix','Profiles','Maintenance','LogCleanup','Finalization','CloneHealth','Runner')) {
    $file = Join-Path $PSScriptRoot "Private/$name.ps1"
    if (Test-Path -LiteralPath $file) { . $file }
}
Export-ModuleMember -Function Invoke-BISFLocal,Invoke-BISFOperatorSealFinalizer,Invoke-BISFCloneVerification
