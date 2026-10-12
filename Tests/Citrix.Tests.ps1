BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Configuration','Operations','Runner') { . "$root/Modules/Private/$n.ps1" }
    if (Test-Path "$root/Modules/Private/Citrix.ps1") { . "$root/Modules/Private/Citrix.ps1" }
}
Describe 'Citrix XML and MCS validation' {
    BeforeEach { $c=Read-BISFConfig "$root/GlobalConfig.xml" $root }
    It 'enables VDA and WEM release checks in the supplied configuration' {
        $c.Citrix.VDA.Enabled | Should -BeTrue
        $c.Citrix.WEM.Enabled | Should -BeTrue
        $c.Citrix.VDA.ExpectedRelease | Should -Be '2507'
        $c.Citrix.VDA.StopBeforeShutdown | Should -BeFalse
    }
    It 'keeps older configurations without Citrix disabled' {
        (Get-Content "$root/GlobalConfig.xml" -Raw) -replace '(?s)  <Citrix>.*?</Citrix>\s*','' | Set-Content "$TestDrive/old.xml"
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
    It 'matches the release token rather than a partial number' {
        Test-BISFCitrixRelease 'Citrix Virtual Delivery Agent 2507 LTSR CU1' '7.45.100.12' '2507' | Should -BeTrue
        Test-BISFCitrixRelease 'Citrix Virtual Delivery Agent' '2507.0.100.12' '2507' | Should -BeTrue
        Test-BISFCitrixRelease 'Citrix Virtual Delivery Agent 12507' '25070.0.1' '2507' | Should -BeFalse
        Test-BISFCitrixRelease 'Citrix Virtual Delivery Agent' '7.45.0.1' '2507' | Should -BeFalse
    }
}
Describe 'Citrix prerequisite checks preserve installed configuration' {
    BeforeEach {
        $c=Read-BISFConfig "$root/GlobalConfig.xml" $root
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
    It 'rejects a mismatched installed release' {
        Mock Get-BISFCitrixProducts { [pscustomobject]@{DisplayName='Citrix Virtual Delivery Agent 2402 LTSR';DisplayVersion='7.41.0.1'} }
        { Get-BISFCitrixReadiness $c Prepare } | Should -Throw '*2507*'
    }
    It 'requires both WEM services and automatic SENS startup' {
        $script:services[4].StartMode='Manual'
        { Get-BISFCitrixReadiness $c Prepare } | Should -Throw '*SENS*'
    }
    It 'rejects a WEM host service running under another account' {
        $script:services[2].StartName='DOMAIN\account'
        { Get-BISFCitrixReadiness $c Prepare } | Should -Throw '*LocalSystem*'
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
    It 'fails closed on an unknown internal version without release metadata' {
        Mock Get-BISFServiceBinaryVersion { '7.45.0.1' }
        { Get-BISFCitrixVersion @() 'VDA' $service '2507' } | Should -Throw '*2507*'
    }
    It 'rejects conflicting product registrations' {
        Mock Get-BISFServiceBinaryVersion { '2507.0.1' }
        $products=@([pscustomobject]@{DisplayName='VDA 2507';DisplayVersion='2507.0'},[pscustomobject]@{DisplayName='VDA 2402';DisplayVersion='2402.0'})
        { Get-BISFCitrixVersion $products 'VDA' $service '2507' } | Should -Throw '*conflicting*'
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
