#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if (-not (Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.0' })) {
    throw 'Development tests require Pester 5. Install it separately; the image preparation package itself needs no Pester.'
}
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
Write-Host "Testing with $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion) on $([Environment]::OSVersion). Windows operations are mocked."
$result=Invoke-Pester -Path $PSScriptRoot -Output Detailed -PassThru
if ($result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0 -or $result.TotalCount -eq 0) { exit 1 }
exit 0
