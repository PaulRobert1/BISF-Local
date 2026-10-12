# BIS-F Local, unofficial derivative. Modified 2026-10-12. GPL-3.0; see LICENSE.
function Get-BISFInventory {
    if ($env:OS -ne 'Windows_NT') { throw 'Run on Windows in elevated 64-bit Windows PowerShell 5.1.' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $pending = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    $session = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
    if ($null -ne $session.PSObject.Properties['PendingFileRenameOperations']) {
        $pending = $pending -or (@($session.PendingFileRenameOperations).Count -gt 0)
    }
    [pscustomobject]@{
        Caption=[string]$os.Caption; Build=[int]$os.BuildNumber; ProductType=[int]$os.ProductType
        Version=[string]$os.Version; Edition=[string]$PSVersionTable.PSEdition
        PSVersion=$PSVersionTable.PSVersion.ToString(); Is64Bit=[Environment]::Is64BitProcess
        IsAdmin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        PendingReboot=[bool]$pending; Identity=Get-BISFIdentity
        CMInstalled=(@(Get-Service -Name CcmExec -ErrorAction SilentlyContinue).Count -gt 0)
    }
}
function Test-BISFPlatform {
    param($Inventory, $Config, [string]$Mode)
    if ($Inventory.Edition -ne 'Desktop' -or $Inventory.PSVersion -notmatch '^5\.1($|\.)' -or -not $Inventory.Is64Bit -or -not $Inventory.IsAdmin) {
        throw 'Requires elevated 64-bit Windows PowerShell 5.1 (Desktop).'
    }
    if ($Inventory.ProductType -eq 2) { throw 'Domain controllers cannot be prepared.' }
    if ($Inventory.Version -notmatch '^10\.0\.' -or -not (
        ($Inventory.ProductType -eq 3 -and $Inventory.Build -eq 26100) -or
        ($Inventory.ProductType -eq 1 -and $Inventory.Build -ge 22000))) {
        throw 'Target must be Windows Server 2025 (26100) or Windows 11 workstation (22000+).'
    }
    if ($Mode -eq 'Prepare' -and $Inventory.PendingReboot -and $Config.Preflight.BlockPendingReboot) {
        throw 'A pending reboot blocks preparation. Reboot the master and retry.'
    }
}
function Get-BISFTempRoots {
    [pscustomobject]@{
        WindowsTemp = Join-Path $env:SystemRoot 'Temp'
        CurrentUserTemp = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Temp'
    }
}
function Test-BISFPreflight {
    param($Config, [string]$Mode, $Plan, [string]$ScriptRoot, [string]$ConfigPath, $Inventory)
    $targetMode = $Mode
    if ($Mode -eq 'Validate') { $targetMode = 'Prepare' }
    Test-BISFPlatform $Inventory $Config $targetMode
    $ids = @($Plan | ForEach-Object { $_.Id })
    if ($Config.ConfigurationManager.PrepareIdentityReset -or $Config.ConfigurationManager.CloneTrustedRootKeyReset) {
        $svc = Get-Service -Name CcmExec -ErrorAction Stop
        if ($svc.StartType -eq 'Disabled') { throw 'CcmExec is disabled; fix the client before preparing.' }
        foreach ($cmd in 'Get-CimInstance','Remove-CimInstance','Stop-Service','Start-Service') { $null = Get-Command $cmd -CommandType Cmdlet -ErrorAction Stop }
    }
    if ($Config.ConfigurationManager.CloneTrustedRootKeyReset) {
        $null = Get-CimClass -Namespace 'root\ccm\locationservices' -ClassName TrustedRootKey -ErrorAction Stop
    }
    if ($Config.ConfigurationManager.PrepareIdentityReset) {
        # Opening an existing store read-only verifies it without creating it.
        $store = New-Object Security.Cryptography.X509Certificates.X509Store('SMS','LocalMachine')
        try { $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor [Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly) }
        finally { $store.Close() }
    }
    if ($Config.Personalization.Enabled) {
        foreach ($cmd in 'Get-ScheduledTask','Register-ScheduledTask','New-ScheduledTaskAction','New-ScheduledTaskTrigger','New-ScheduledTaskPrincipal','New-ScheduledTaskSettingsSet') {
            $null = Get-Command $cmd -Module ScheduledTasks -CommandType Cmdlet,Function -ErrorAction Stop
        }
        Test-BISFProtectedLocation $ScriptRoot
        Test-BISFProtectedLocation $ConfigPath
        Test-BISFTaskOwnership $ScriptRoot $ConfigPath
        if ($Config.Logging.Enabled) { Test-BISFProtectedLocation $Config.Logging.Path }
        # Reject redirecting any file imported by the SYSTEM task.
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $ScriptRoot 'Modules') -Recurse -Force -ErrorAction Stop) {
            Test-BISFProtectedLocation $f.FullName
        }
        Test-BISFProtectedLocation (Join-Path $ScriptRoot 'Invoke-BISF.ps1')
        Test-BISFProtectedLocation (Join-Path $ScriptRoot 'GlobalConfig.xsd')
    }
    if ($Config.Personalization.Enabled -or $Config.ConfigurationManager.PrepareIdentityReset -or $Config.ConfigurationManager.CloneTrustedRootKeyReset -or $targetMode -eq 'Personalize') {
        Test-BISFProtectedLocation $ScriptRoot
        Test-BISFProtectedLocation (Join-Path $ScriptRoot 'state')
    }
    if ($ids -contains 'WindowsTemp' -or $ids -contains 'CurrentUserTemp') {
        $roots = Get-BISFTempRoots
        foreach ($id in 'WindowsTemp','CurrentUserTemp') {
            if ($ids -contains $id) {
                $path = $roots.$id
                if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Temporary directory missing: $path" }
                Test-BISFNoReparsePath $path
            }
        }
    }
    if ($ids -contains 'Shutdown') { $null = Get-Command Stop-Computer -CommandType Cmdlet -ErrorAction Stop }
}
