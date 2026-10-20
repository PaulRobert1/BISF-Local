BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Configuration','Operations','Runner') { . "$root/Modules/Private/$n.ps1" }
    if (Test-Path "$root/Modules/Private/Citrix.ps1") { . "$root/Modules/Private/Citrix.ps1" }
}
Describe 'Citrix XML and MCS validation' {
    BeforeEach { $c=Read-BISFConfig "$root/Tests/Fixtures/OptInBaseline.xml" $root }
    It 'enables VDA and WEM release checks in the supplied configuration' {
        $c.Citrix.VDA.Enabled | Should -BeTrue
        $c.Citrix.WEM.Enabled | Should -BeTrue
        $c.Citrix.VDA.StopBeforeShutdown | Should -BeFalse
    }
    It 'keeps older configurations without Citrix disabled' {
        (Get-Content "$root/Tests/Fixtures/OptInBaseline.xml" -Raw) -replace '(?s)  <Citrix>.*?</Citrix>\s*','' | Set-Content "$TestDrive/old.xml"
        $old=Read-BISFConfig "$TestDrive/old.xml" $root
        $old.Citrix.VDA.Enabled | Should -BeFalse
        $old.Citrix.WEM.Enabled | Should -BeFalse
    }
    It 'requires shutdown for an enabled stop option' {
        $c.Citrix.VDA.StopBeforeShutdown=$true
        { Test-BISFCitrixSettings $c } | Should -Throw '*Shutdown*'
    }
    It 'places optional VDA stop immediately before shutdown' {
        $c.Citrix.VDA.StopBeforeShutdown=$true; $c.FinalAction='Shutdown'
        (@(Get-BISFPlan $c Prepare).Id -join ',') | Should -Be 'VDAStop,Shutdown'
        (@(Get-BISFPlan $c Personalize).Id) | Should -Not -Contain 'VDAStop'
    }

}
Describe 'Citrix prerequisite checks preserve installed configuration' {
    BeforeEach {
        $c=Read-BISFConfig "$root/Tests/Fixtures/OptInBaseline.xml" $root
        $script:services=@(
            [pscustomobject]@{Name='BrokerAgent';DisplayName='Citrix Desktop Service';StartMode='Auto';State='Running';StartName='LocalSystem';PathName='"C:\Citrix\BrokerAgent.exe"'},
            [pscustomobject]@{Name='PvsVmAgent';DisplayName='Citrix Pvs for VMs Agent';StartMode='Manual';State='Stopped';StartName='LocalSystem';PathName='"C:\Citrix\Identity.exe"'},
            [pscustomobject]@{Name='WemAgentSvc';DisplayName='Citrix WEM Agent Host Service';StartMode='Auto';State='Running';StartName='LocalSystem';PathName='"C:\WEM\Agent.exe"'},
            [pscustomobject]@{Name='WemLogon';DisplayName='Citrix WEM Agent User Logon Service';StartMode='Auto';State='Running';StartName='LocalSystem';PathName='"C:\WEM\Logon.exe"'},
            [pscustomobject]@{Name='SENS';DisplayName='System Event Notification Service';StartMode='Auto';State='Running';StartName='LocalSystem';PathName='C:\Windows\svchost.exe'}
        )
        Mock Get-BISFCitrixServices { $script:services }
        Mock Get-BISFCitrixProducts { @(
            [pscustomobject]@{DisplayName='Citrix Virtual Delivery Agent 2507 LTSR';DisplayVersion='7.45.0.1'},
            [pscustomobject]@{DisplayName='Citrix Workspace Environment Management Agent';DisplayVersion='2507.0.1'}
        ) }
        Mock Get-BISFWEMCache { "$TestDrive/WEM/Local Databases Set" }
        Mock Get-BISFServiceBinaryVersion { '2507.0.1' }
    }
    It 'returns detected versions and a protected cache path without changing services' {
        $r=Get-BISFCitrixReadiness $c Prepare
        $r.VDA.Version | Should -Be '7.45.0.1'
        $r.WEM.CachePath | Should -Be "$TestDrive/WEM/Local Databases Set"
    }
    It 'requires the MCS Machine Identity component' {
        $script:services=@($script:services | Where-Object Name -ne PvsVmAgent)
        { Get-BISFCitrixReadiness $c Prepare } | Should -Throw '*Machine Identity*'
    }
    It 'accepts an older installed release' {
        Mock Get-BISFCitrixProducts { [pscustomobject]@{DisplayName='Citrix Virtual Delivery Agent 2402 LTSR';DisplayVersion='7.41.0.1'} }
        (Get-BISFCitrixReadiness $c Prepare).VDA.Version | Should -Be '7.41.0.1'
    }
    It 'requires both WEM services and automatic SENS startup' {
        $script:services[4].StartMode='Manual'
        { Get-BISFCitrixReadiness $c Prepare } | Should -Throw '*SENS*'
    }
    It 'rejects a WEM host service running under another account' {
        $script:services[2].StartName='DOMAIN\account'
        { Get-BISFCitrixReadiness $c Prepare } | Should -Throw '*LocalSystem*'
    }
    It 'accepts the legacy WEM host without a separate user logon service' {
        $script:services[2].Name='Norskale Agent Host Service'
        $script:services[2].DisplayName='Norskale Agent Host Service'
        $script:services=@($script:services | Where-Object Name -ne WemLogon)
        $r=Get-BISFCitrixReadiness $c Prepare
        $r.WEM.HostService | Should -Be 'Norskale Agent Host Service'
        $r.WEM.LogonService | Should -Be 'Not installed'
    }
    It 'does not discover Citrix when both integrations are disabled' {
        $c.Citrix.VDA.Enabled=$false; $c.Citrix.WEM.Enabled=$false
        $r=Get-BISFCitrixReadiness $c Prepare
        Should -Invoke Get-BISFCitrixServices -Times 0
        $r.WEM | Should -BeNullOrEmpty
    }
    It 'does not impose master image checks during optional clone personalization' {
        $r=Get-BISFCitrixReadiness $c Personalize
        Should -Invoke Get-BISFCitrixServices -Times 0
    }
}
Describe 'Citrix installed version evidence' {
    BeforeEach { $service=[pscustomobject]@{Name='BrokerAgent';PathName='"C:\Citrix\BrokerAgent.exe"'} }
    It 'uses the binary marketing release if uninstall metadata is absent' {
        Mock Get-BISFServiceBinaryVersion { '2507.0.100.428' }
        Get-BISFCitrixVersion @() 'VDA' $service '2507' | Should -Be '2507.0.100.428'
    }
    It 'reports internal versions without guessing or blocking their release' {
        Mock Get-BISFServiceBinaryVersion { '7.15.0.1' }
        Get-BISFCitrixVersion @() 'VDA' $service | Should -Be '7.15.0.1'
    }
    It 'reports unknown version resources without blocking preparation' {
        Mock Get-BISFServiceBinaryVersion { '' }
        Get-BISFCitrixVersion @() 'VDA' $service | Should -Be 'Unknown'
    }
    It 'requires the installed binary even when the product registration matches' {
        Mock Get-BISFServiceBinaryVersion { throw 'binary missing' }
        $products=@([pscustomobject]@{DisplayName='VDA 2507';DisplayVersion='2507.0'})
        { Get-BISFCitrixVersion $products 'VDA' $service '2507' } | Should -Throw '*binary missing*'
    }
}
Describe 'WEM cache location handling' {
    BeforeAll {
        # Pure selection logic is portable; Windows canonicalization is tested separately.
        if (-not (Get-Command Resolve-BISFCitrixLocalPath -ErrorAction SilentlyContinue)) { function Resolve-BISFCitrixLocalPath { param($Path) } }
    }
    BeforeEach {
        Mock Resolve-BISFCitrixLocalPath { $Path }
        Mock Test-Path { $false }
        Mock Get-BISFServiceBinaryPath { 'C:\WEM\Agent.exe' }
        $service=[pscustomobject]@{PathName='"C:\WEM\Agent.exe"'}
    }
    It 'preserves an explicitly configured alternate cache' {
        Mock Get-ItemProperty { [pscustomobject]@{AgentLocation='C:\WEM';AgentCacheAlternateLocation='D:\Persistent\WEM'} }
        Get-BISFWEMCache $service | Should -Be 'D:\Persistent\WEM'
    }
    It 'uses the WEM installation folder when no alternate cache is set' {
        Mock Get-ItemProperty { [pscustomobject]@{AgentLocation='C:\WEM';AgentCacheAlternateLocation=''} }
        Get-BISFWEMCache $service | Should -Be 'C:\WEM\Local Databases Set'
    }
    It 'refuses a missing registry configuration rather than silently choosing another cache' {
        Mock Get-ItemProperty { throw 'missing WEM settings' }
        { Get-BISFWEMCache $service } | Should -Throw '*missing WEM settings*'
    }
}
Describe 'WEM cache read-only status' {
    BeforeEach { $script:cacheRoot=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')) }
    It 'reports a missing cache directory without creating it' {
        $r=Get-BISFWEMCacheStatus $script:cacheRoot
        $r.Status | Should -Be 'DirectoryMissing'
        $r.DirectoryExists | Should -BeFalse
        $r.LocalAgentCachePresent | Should -BeFalse
        $r.LocalAgentDatabasePresent | Should -BeFalse
        (Test-Path -LiteralPath $script:cacheRoot) | Should -BeFalse
    }
    It 'does not treat an empty directory as an initialized cache' {
        New-Item -ItemType Directory -Path $script:cacheRoot | Out-Null
        $r=Get-BISFWEMCacheStatus $script:cacheRoot
        $r.Status | Should -Be 'Incomplete'
        $r.DirectoryExists | Should -BeTrue
    }
    It 'reports either individual database file missing' {
        New-Item -ItemType Directory -Path $script:cacheRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $script:cacheRoot 'LocalAgentCache.db') -Value 'cache'
        $r=Get-BISFWEMCacheStatus $script:cacheRoot
        $r.Status | Should -Be 'Incomplete'
        $r.LocalAgentCachePresent | Should -BeTrue
        $r.LocalAgentDatabasePresent | Should -BeFalse
        Remove-Item -LiteralPath (Join-Path $script:cacheRoot 'LocalAgentCache.db')
        Set-Content -LiteralPath (Join-Path $script:cacheRoot 'LocalAgentDatabase.db') -Value 'database'
        $r=Get-BISFWEMCacheStatus $script:cacheRoot
        $r.Status | Should -Be 'Incomplete'
        $r.LocalAgentCachePresent | Should -BeFalse
        $r.LocalAgentDatabasePresent | Should -BeTrue
    }
    It 'reports both file names as present without touching their contents' {
        New-Item -ItemType Directory -Path $script:cacheRoot | Out-Null
        $cacheDb=Join-Path $script:cacheRoot 'LocalAgentCache.db'
        $databaseDb=Join-Path $script:cacheRoot 'LocalAgentDatabase.db'
        Set-Content -LiteralPath $cacheDb -Value 'cache-value'
        Set-Content -LiteralPath $databaseDb -Value 'database-value'
        $r=Get-BISFWEMCacheStatus $script:cacheRoot
        $r.Status | Should -Be 'FilesPresent'
        $r.LocalAgentCachePresent | Should -BeTrue
        $r.LocalAgentDatabasePresent | Should -BeTrue
        (Get-Content -LiteralPath $cacheDb -Raw).Trim() | Should -Be 'cache-value'
        (Get-Content -LiteralPath $databaseDb -Raw).Trim() | Should -Be 'database-value'
    }
}
Describe 'Citrix local path validation' {
    It 'rejects a nonlocal or ambiguous cache path: <Path>' -ForEach @(
        @{Path='\\server\cache'},@{Path='D:cache'},@{Path='cache'},@{Path='%UNKNOWN%\cache'},@{Path='D:\cache:stream'}
    ) {
        { Resolve-BISFCitrixLocalPath $Path } | Should -Throw
    }
}
Describe 'VDA service rollback' {
    BeforeAll {
        if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) { function Get-Service { param($Name) } }
    }
    It 'never starts a previously stopped VDA during recovery' {
        Mock Get-Service { throw 'must not obtain a controller or start the service' }
        Restore-BISFVDA 'Stopped'
        Should -Invoke Get-Service -Times 0
    }
}
Describe 'VDA bounded service-control operations' {
    BeforeAll {
        if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) { function Get-Service { param($Name) } }
        if (-not (Get-Command Stop-Service -ErrorAction SilentlyContinue)) { function Stop-Service { [CmdletBinding(SupportsShouldProcess)]param($Name,[switch]$NoWait,[switch]$Force) } }
    }
    BeforeEach {
        $script:controls=New-Object 'System.Collections.Generic.List[string]'
        $script:controller=[pscustomobject]@{Status='StopPending'}
        $script:controller | Add-Member ScriptMethod WaitForStatus { param($State,$Timeout) $script:controls.Add("wait:$State/$($Timeout.TotalSeconds)"); $this.Status=[string]$State }
        $script:controller | Add-Member ScriptMethod Start { $script:controls.Add('start') }
        Mock Get-Service { $script:controller }
        Mock Stop-Service { if (-not $NoWait) { throw 'unbounded wait' }; $script:controls.Add('stop') }
    }
    It 'issues nonblocking stop without force or another confirmation then waits at most thirty seconds' {
        Stop-BISFVDA
        ($script:controls -join ',') | Should -Be 'stop,wait:Stopped/30'
        Should -Invoke Stop-Service -Times 1 -ParameterFilter { $NoWait -and -not $Force -and $Confirm -eq $false -and $Name -eq 'BrokerAgent' }
    }
    It 'waits for pending stop before starting and bounding the recovery wait' {
        Restore-BISFVDA 'Running'
        ($script:controls -join ',') | Should -Be 'wait:Stopped/30,start,wait:Running/30'
    }
    It 'surfaces a stop timeout to the runner recovery path' {
        $script:controller | Add-Member ScriptMethod WaitForStatus { param($State,$Timeout) throw 'timed out' } -Force
        { Stop-BISFVDA } | Should -Throw '*timed out*'
    }
}
Describe 'Citrix version-independent inventory' {
    It 'accepts installed version <Version> without a release gate' -ForEach @(@{Version='7.15.0.1'},@{Version='1912.0.1'},@{Version='2402.0.1'},@{Version='2507.0.1'},@{Version='2607.0.1'},@{Version='future-version'}) {
        Mock Get-BISFServiceBinaryVersion { $Version }
        Get-BISFCitrixVersion @() 'VDA' ([pscustomobject]@{Name='BrokerAgent'}) | Should -Be $Version
    }
}
