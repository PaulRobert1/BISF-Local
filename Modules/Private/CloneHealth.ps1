# BISF-Local — read-only MCS clone verification inventory.
# Service-state checks do not establish broker registration or successful ICA logon.

function Invoke-BISFCloneVerification {
    param([string]$ScriptRoot,[string]$ConfigPath)
    $ScriptRoot=[IO.Path]::GetFullPath($ScriptRoot)
    $ConfigPath=Resolve-BISFPath $ConfigPath $ScriptRoot
    $config=Read-BISFConfig $ConfigPath $ScriptRoot
    $inventory=Get-BISFInventory
    Test-BISFPlatform $inventory $config Personalize
    $os=Get-BISFWindowsRelease $inventory
    $result=[pscustomobject]@{
        Mode='VerifyClone'
        Computer=$inventory.Identity.Name
        OS=$inventory.Caption
        OSRelease=$os.Release
        Build=$inventory.Build
        PendingReboot=$inventory.PendingReboot
        MCSIdentityService='Unknown'
        DesktopService='Unknown'
        WEMCache='NotChecked'
        ProfileManagers=@()
        SystemDriveFreeGB=$null
        DomainJoined=$null
        VDARegistration='NotVerified: check Citrix Studio / Director / Monitor'
        ICAApplicationLaunch='NotVerified: launch published resource on a test clone'
        WEMRegistration='NotVerified: inspect WEM administration console'
        WindowsActivation='NotVerified: check Windows license state'
    }
    Write-Host '==== BISF-Local MCS clone health (READ ONLY) ===='
    Write-Host ("Computer={0}; OS={1}; Build={2}; Release={3}; PendingReboot={4}" -f $result.Computer,$result.OS,$result.Build,$result.OSRelease,$result.PendingReboot)
    try {
        $citrix=Get-BISFCitrixReadiness $config 'Validate'
        if ($null -ne $citrix.VDA) {
            $result.DesktopService=[string]$citrix.VDA.State
            $result.MCSIdentityService=[string]$citrix.VDA.MachineIdentityService
            Write-Host ("Citrix DesktopService={0}; MachineIdentity={1}; VDA={2}" -f $result.DesktopService,$result.MCSIdentityService,$citrix.VDA.Version)
            if ($result.DesktopService -ne 'Running') { Write-Warning 'BrokerAgent is not running; VDA cannot register until it is running.' }
        }
        if ($null -ne $citrix.WEM) {
            $result.WEMCache=[string]$citrix.WEM.CacheStatus
            Write-Host ("WEM Host={0}; WEM cache={1}; Version={2}" -f $citrix.WEM.HostState,$result.WEMCache,$citrix.WEM.Version)
            if ($result.WEMCache -notin @('FilesPresent','Unknown')) { Write-Warning 'WEM cache is absent or incomplete; verify WEM agent configuration and synchronization.' }
        }
    } catch {
        Write-Warning "Citrix local readiness check failed: $($_.Exception.Message)"
    }
    try {
        $managers=@(Get-BISFProfileManagementServices)
        $result.ProfileManagers=$managers
        foreach ($svc in $managers) {
            Write-Host ("Profile manager: {0} = {1}, {2}" -f $svc.Name,$svc.State,$svc.StartMode)
        }
    } catch { Write-Warning "Profile-manager inventory failed: $($_.Exception.Message)" }
    try {
        $disk=Get-BISFSystemDriveStatus
        $result.SystemDriveFreeGB=$disk.FreeGB
        Write-Host ("System drive={0}; FreeGB={1}; TotalGB={2}" -f $disk.Drive,$disk.FreeGB,$disk.TotalGB)
    } catch { Write-Warning "System drive inventory failed: $($_.Exception.Message)" }
    try {
        $computer=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $result.DomainJoined=[bool]$computer.PartOfDomain
        Write-Host ("DomainJoined={0}; Domain={1}" -f $result.DomainJoined,$computer.Domain)
    } catch { Write-Warning "Domain-join inventory failed: $($_.Exception.Message)" }
    Write-Host 'VDA registration: NOT VERIFIED locally; inspect Studio/Director/Monitor.'
    Write-Host 'ICA logon/HDX: NOT VERIFIED; launch a desktop or application on a disposable MCS clone.'
    Write-Host 'WEM registration/synchronization: NOT VERIFIED; inspect WEM console and applied settings.'
    Write-Host 'Windows licensing / FSLogix container attach: NOT VERIFIED by service status.'
    Write-Host 'No image preparation, cleanup, shutdown, task registration or file logging was executed.'
    $result
}
