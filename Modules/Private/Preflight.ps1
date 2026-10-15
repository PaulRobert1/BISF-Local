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
function Get-BISFWindowsRelease {
    param($Inventory)
    # Marketing release labels are diagnostic only, never a vendor support guarantee.
    # ProductType distinguishes Windows 11 24H2 from Server 2025: both use build 26100.
    $build=[int]$Inventory.Build
    $platform=[pscustomobject]@{
        Family='Unsupported'
        Release='Unknown'
        Build=$build
        Eligible=$false
        RecognizedBuild=$false
        RequiresCompatibilityReview=$true
        Guidance='Unsupported Windows family or kernel version.'
    }
    if ([string]$Inventory.Version -notmatch '^10\.0\.') { return $platform }
    if ([int]$Inventory.ProductType -eq 1 -and $build -ge 22000) {
        $platform.Family='Windows 11 workstation'
        $platform.Eligible=$true
        $platform.Guidance='Windows 11 single-session VDA is supported where Citrix product/edition requirements are met. Multi-session Windows 11 requires Citrix DaaS.'
        switch ($build) {
            22000 { $platform.Release='Windows 11 21H2'; $platform.RecognizedBuild=$true }
            22621 { $platform.Release='Windows 11 22H2'; $platform.RecognizedBuild=$true }
            22631 { $platform.Release='Windows 11 23H2'; $platform.RecognizedBuild=$true }
            26100 { $platform.Release='Windows 11 24H2'; $platform.RecognizedBuild=$true }
            26200 { $platform.Release='Windows 11 25H2'; $platform.RecognizedBuild=$true }
            26300 {
                $platform.Release='Windows 11 26H2'
                $platform.RecognizedBuild=$true
                $platform.Guidance='Windows 11 26H2: Citrix lists 2507 LTSR CU2 or newer (or another approved VDA release); multi-session requires DaaS.'
            }
            28000 {
                $platform.Release='Windows 11 26H1 (specialized hardware)'
                $platform.RecognizedBuild=$true
                $platform.Guidance='Windows 11 26H1 targets new hardware such as Snapdragon X2; Citrix VDA/CPU architecture support requires separate verification.'
            }
            default {
                $platform.Release='Unrecognized Windows 11-family build'
                $platform.Guidance='Unknown client build: Windows PowerShell / cleanup eligibility is not Citrix OS certification; verify the exact OS, VDA, and profile provider on a disposable image.'
            }
        }
        $platform.RequiresCompatibilityReview=($build -eq 26300 -or $build -eq 28000 -or -not $platform.RecognizedBuild)
    } elseif ([int]$Inventory.ProductType -eq 3 -and $build -eq 26100) {
        $platform.Family='Windows Server'
        $platform.Release='Windows Server 2025'
        $platform.Eligible=$true
        $platform.RecognizedBuild=$true
        $platform.RequiresCompatibilityReview=$false
        $platform.Guidance='Supported BISF-Local platform; check the installed Citrix VDA and image prerequisites before capture.'
    } elseif ([int]$Inventory.ProductType -eq 3 -and $build -gt 26100) {
        $platform.Family='Windows Server'
        $platform.Release='Unrecognized future Windows Server build'
        $platform.Guidance='Later Windows Server releases are not automatically eligible for destructive preparation until platform-specific validation is added.'
    }
    $platform
}
function Test-BISFPlatform {
    param($Inventory, $Config, [string]$Mode)
    if ($Inventory.Edition -ne 'Desktop' -or $Inventory.PSVersion -notmatch '^5\.1($|\.)' -or -not $Inventory.Is64Bit -or -not $Inventory.IsAdmin) {
        throw 'Requires elevated 64-bit Windows PowerShell 5.1 (Desktop).'
    }
    if ($Inventory.ProductType -eq 2) { throw 'Domain controllers cannot be prepared.' }
    $platform=Get-BISFWindowsRelease $Inventory
    if (-not $platform.Eligible) {
        throw ('Target must be Windows Server 2025 (26100) or Windows 11 workstation (22000+). Detected: {0}, build {1}. {2}' -f $platform.Release,$platform.Build,$platform.Guidance)
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
    if ($ids -contains 'UserProfiles') {
        foreach ($cmd in 'Get-CimInstance','Remove-CimInstance') {
            $null=Get-Command $cmd -CommandType Cmdlet -ErrorAction Stop
        }
        # Win32_UserProfile inventory and path validation take place in Runner
        # before any image operations. Do not require WEM to be initialized.
    }
    if ($targetMode -eq 'Prepare' -and $Config.Preflight.MinimumSystemDriveFreeGB -gt 0) {
        $volume=Get-BISFSystemDriveStatus
        if ($volume.FreeGB -lt $Config.Preflight.MinimumSystemDriveFreeGB) {
            throw ("Not enough free space on {0}: {1} GB available, {2} GB required." -f $volume.Drive,$volume.FreeGB,$Config.Preflight.MinimumSystemDriveFreeGB)
        }
    }
    if ($targetMode -eq 'Prepare' -and $Config.Preflight.BlockOtherLoadedProfiles) {
        $others=@(Get-BISFLoadedNonSystemProfiles (Get-BISFCurrentUserSid))
        if ($others.Count -gt 0) { throw 'Other loaded local user profiles exist. Log off other users and retry image preparation.' }
    }
    if ($ids -contains 'Servicing') {
        foreach ($cmd in 'Get-ScheduledTask','Get-ScheduledTaskInfo','Start-ScheduledTask') {
            $null=Get-Command $cmd -Module ScheduledTasks -CommandType Cmdlet,Function -ErrorAction Stop
        }
        $null=Get-BISFComponentCleanupTask
    }
    if ($ids -contains 'RecycleBin') {
        $null=Get-Command 'Clear-RecycleBin' -CommandType Cmdlet -ErrorAction Stop
    }
    if ($Config.Finalization.RemoveOperatorProfile) {
        Test-BISFOperatorSealSettings $Config
        if ($targetMode -eq 'Prepare') {
            foreach ($cmd in 'Get-ScheduledTask','Register-ScheduledTask','Start-ScheduledTask','Unregister-ScheduledTask',
                    'New-ScheduledTaskAction','New-ScheduledTaskPrincipal','New-ScheduledTaskSettingsSet') {
                $null=Get-Command $cmd -Module ScheduledTasks -CommandType Cmdlet,Function -ErrorAction Stop
            }
            Test-BISFProtectedLocation $ScriptRoot
            Test-BISFProtectedLocation $ConfigPath
            Test-BISFProtectedLocation (Join-Path $ScriptRoot 'Invoke-BISF.ps1')
            Test-BISFProtectedLocation (Join-Path $ScriptRoot 'state')
            if ($Config.Logging.Enabled) { Test-BISFProtectedLocation $Config.Logging.Path }
            Test-BISFOperatorSealTaskOwnership $ScriptRoot $ConfigPath
        }
    }
    if ($ids -contains 'Shutdown') { $null = Get-Command Stop-Computer -CommandType Cmdlet -ErrorAction Stop }
}
