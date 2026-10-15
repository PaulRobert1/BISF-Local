# BIS-F Local, unofficial derivative. Modified 2026-10-12. GPL-3.0; see LICENSE.
function Test-BISFCitrixSettings {
    param($Config)
    if ($Config.Citrix.VDA.StopBeforeShutdown -and (-not $Config.Citrix.VDA.Enabled -or $Config.FinalAction -ne 'Shutdown')) {
        throw 'Citrix VDA StopBeforeShutdown requires VDA.Enabled=true and FinalAction=Shutdown.'
    }
}
function Get-BISFCitrixServices {
    # Read-only service inventory; never query Win32_Product (MSI repair side effects).
    Get-CimInstance -ClassName Win32_Service -ErrorAction Stop
}
function Get-BISFCitrixProducts {
    foreach ($path in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (Test-Path -LiteralPath $path) {
            foreach ($key in Get-ChildItem -LiteralPath $path -ErrorAction Stop) {
                $p=Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                if ($null -ne $p.PSObject.Properties['DisplayName'] -and $p.DisplayName -match '^Citrix.*(Virtual (Delivery|Desktop) Agent|Workspace Environment Management.*Agent)') {
                    $version=''
                    if ($null -ne $p.PSObject.Properties['DisplayVersion']) { $version=[string]$p.DisplayVersion }
                    [pscustomobject]@{DisplayName=[string]$p.DisplayName;DisplayVersion=$version}
                }
            }
        }
    }
}
function Resolve-BISFCitrixLocalPath {
    param([string]$Path)
    $value=[Environment]::ExpandEnvironmentVariables($Path.Trim())
    if ($value -notmatch '^[A-Za-z]:[\\/]' -or $value.Contains('%') -or $value.Substring(2).Contains(':') -or $value -match '[\x00-\x1f"*?]') {
        throw 'Citrix path must be an unambiguous absolute local filesystem path.'
    }
    $value=[IO.Path]::GetFullPath($value)
    Test-BISFNoReparsePath $value
    $value
}
function Get-BISFServiceBinaryPath {
    param([string]$PathName)
    $path=[Environment]::ExpandEnvironmentVariables($PathName.Trim())
    if ($path -match '^"([^"]+\.exe)"(?:\s.*)?$') { $path=$Matches[1] }
    elseif ($path -match '^([^"\r\n]+?\.exe)(?:\s.*)?$') { $path=$Matches[1] }
    else { throw 'Cannot identify the installed service binary path.' }
    $path=Resolve-BISFCitrixLocalPath $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Citrix service binary missing: $path" }
    $path
}
function Get-BISFServiceBinaryVersion {
    param($Service)
    $path=Get-BISFServiceBinaryPath $Service.PathName
    # Reading version resources does not execute the installed binary.
    [Diagnostics.FileVersionInfo]::GetVersionInfo($path).ProductVersion
}
function Get-BISFCitrixVersion {
    param($Products, [string]$Pattern, $Service)
    # Installed versions are inventory only. Windows eligibility and component
    # prerequisites determine whether preparation can proceed.
    $binaryVersion=Get-BISFServiceBinaryVersion $Service
    $versions=@($Products | Where-Object { $_.DisplayName -match $Pattern } | ForEach-Object { $_.DisplayVersion } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($versions.Count -gt 0) { return [string]($versions -join ', ') }
    if (-not [string]::IsNullOrWhiteSpace($binaryVersion)) { return [string]$binaryVersion }
    'Unknown'
}
function Get-BISFRequiredCitrixService {
    param($Services, [string[]]$Name, [string[]]$DisplayName)
    $found=@($Services | Where-Object { ($Name -and $Name -contains $_.Name) -or ($DisplayName -and $DisplayName -contains $_.DisplayName) })
    if ($found.Count -ne 1) { throw "Required Citrix service missing or ambiguous: $Name $DisplayName" }
    if ($found[0].StartMode -eq 'Disabled') { throw "Required Citrix service is disabled: $($found[0].Name)" }
    $found[0]
}
function Get-BISFWEMCache {
    param($Service)
    $path='HKLM:\SYSTEM\CurrentControlSet\Control\Norskale\Agent Host'
    $settings=Get-ItemProperty -LiteralPath $path -ErrorAction Stop
    $cache=''
    if ($null -ne $settings.PSObject.Properties['AgentCacheAlternateLocation']) { $cache=[string]$settings.AgentCacheAlternateLocation }
    if ([string]::IsNullOrWhiteSpace($cache)) {
        $install=''
        if ($null -ne $settings.PSObject.Properties['AgentLocation']) { $install=[string]$settings.AgentLocation }
        if ([string]::IsNullOrWhiteSpace($install)) { $install=Split-Path (Get-BISFServiceBinaryPath $Service.PathName) -Parent }
        $cache=$install.TrimEnd('\','/')+'\Local Databases Set'
    }
    $cache=Resolve-BISFCitrixLocalPath $cache
    if ((Test-Path -LiteralPath $cache) -and -not (Test-Path -LiteralPath $cache -PathType Container)) { throw 'WEM cache path is not a directory.' }
    $cache
}
function Get-BISFWEMCacheStatus {
    param([Parameter(Mandatory=$true)][string]$CachePath)
    # Existence is not synchronization or integrity. Modern WEM agents manage
    # cache creation and clone-specific database refresh themselves.
    $directoryExists=Test-Path -LiteralPath $CachePath -PathType Container -ErrorAction Stop
    $cacheDbExists=$false
    $databaseDbExists=$false
    if ($directoryExists) {
        $cacheDbExists=Test-Path -LiteralPath (Join-Path $CachePath 'LocalAgentCache.db') -PathType Leaf -ErrorAction Stop
        $databaseDbExists=Test-Path -LiteralPath (Join-Path $CachePath 'LocalAgentDatabase.db') -PathType Leaf -ErrorAction Stop
    }
    $status='Incomplete'
    if (-not $directoryExists) { $status='DirectoryMissing' }
    elseif ($cacheDbExists -and $databaseDbExists) { $status='FilesPresent' }
    [pscustomobject]@{
        DirectoryExists=[bool]$directoryExists
        LocalAgentCachePresent=[bool]$cacheDbExists
        LocalAgentDatabasePresent=[bool]$databaseDbExists
        Status=$status
    }
}
function Get-BISFCitrixReadiness {
    param($Config, [string]$Mode)
    Test-BISFCitrixSettings $Config
    $report=[pscustomobject]@{VDA=$null;WEM=$null}
    if ($Mode -eq 'Personalize' -or (-not $Config.Citrix.VDA.Enabled -and -not $Config.Citrix.WEM.Enabled)) { return $report }
    $services=@(Get-BISFCitrixServices)
    $products=@(Get-BISFCitrixProducts)
    if ($Config.Citrix.VDA.Enabled) {
        $vda=Get-BISFRequiredCitrixService $services 'BrokerAgent' ''
        $identity=Get-BISFRequiredCitrixService $services 'PvsVmAgent' 'Citrix Machine Identity Service'
        if ($vda.StartMode -ne 'Auto') { throw 'Citrix Desktop Service (BrokerAgent) must start automatically on MCS clones.' }
        if ($vda.State -notin @('Running','Stopped')) { throw 'Citrix Desktop Service is in a transitional state; retry after it settles.' }
        $version=Get-BISFCitrixVersion $products '^Citrix.*Virtual (Delivery|Desktop) Agent' $vda
        $report.VDA=[pscustomobject]@{Version=$version;Service=$vda.Name;MachineIdentityService=$identity.Name;Startup=$vda.StartMode;State=$vda.State}
    }
    if ($Config.Citrix.WEM.Enabled) {
        $hostService=Get-BISFRequiredCitrixService $services @('WemAgentSvc','Norskale Agent Host Service') @('Citrix WEM Agent Host Service','Norskale Agent Host Service')
        # Older WEM agents may not install a separate user-logon service.
        $logon=$null
        if (@($services | Where-Object { $_.DisplayName -in @('Citrix WEM Agent User Logon Service','Citrix WEM User Logon Service') }).Count -gt 0) {
            $logon=Get-BISFRequiredCitrixService $services '' @('Citrix WEM Agent User Logon Service','Citrix WEM User Logon Service')
        }
        $sens=Get-BISFRequiredCitrixService $services 'SENS' ''
        foreach ($svc in @($hostService,$logon,$sens) | Where-Object { $null -ne $_ }) {
            if ($svc.StartMode -ne 'Auto') { throw "WEM requires Automatic startup for $($svc.Name); fix the installed configuration first." }
        }
        foreach ($svc in @($hostService,$logon) | Where-Object { $null -ne $_ }) {
            if ($svc.StartName -notin @('LocalSystem','NT AUTHORITY\SYSTEM')) { throw "WEM requires LocalSystem for $($svc.Name)." }
        }
        $version=Get-BISFCitrixVersion $products '^Citrix.*Workspace Environment Management.*Agent' $hostService
        $cache=Get-BISFWEMCache $hostService
        $cacheStatus=Get-BISFWEMCacheStatus $cache
        $report.WEM=[pscustomobject]@{Version=$version;HostService=$hostService.Name;HostState=$hostService.State;LogonService=$(if ($null -ne $logon) { $logon.Name } else { 'Not installed' });CachePath=$cache;CacheExists=$cacheStatus.DirectoryExists;CacheStatus=$cacheStatus.Status;LocalAgentCachePresent=$cacheStatus.LocalAgentCachePresent;LocalAgentDatabasePresent=$cacheStatus.LocalAgentDatabasePresent}
    }
    $report
}
function Get-BISFVDARunningState {
    $svc=Get-Service -Name BrokerAgent -ErrorAction Stop
    if ($svc.Status -notin @('Running','Stopped')) { throw 'Citrix Desktop Service is not in a stable running/stopped state.' }
    [string]$svc.Status
}
function Stop-BISFVDA {
    # No Force: do not cascade into dependent services. Never change startup type.
    Stop-Service -Name BrokerAgent -NoWait -Confirm:$false -ErrorAction Stop
    $svc=Get-Service -Name BrokerAgent -ErrorAction Stop
    $svc.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(30))
}
function Restore-BISFVDA {
    param([string]$PreviousState)
    if ($PreviousState -eq 'Running') {
        $svc=Get-Service -Name BrokerAgent -ErrorAction Stop
        if ($svc.Status -eq 'StopPending') { $svc.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(30)) }
        # ServiceController.Start returns without waiting for Running; the explicit
        # wait below bounds recovery rather than hiding a wait inside Start-Service.
        if ($svc.Status -ne 'Running') { $svc.Start() }
        $svc.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(30))
    }
}
