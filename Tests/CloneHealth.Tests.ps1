BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Configuration','Preflight','Citrix','Maintenance','CloneHealth') { . "$root/Modules/Private/$n.ps1" }
}
Describe 'Read-only MCS test clone verification report' {
    BeforeEach {
        $script:fakeOS=[pscustomobject]@{
            Identity=[pscustomobject]@{Name='MCS-CLONE-001'}
            Caption='Microsoft Windows Server 2025 Standard'
            Version='10.0.26100';Build=26100;ProductType=3
            Edition='Desktop';PSVersion='5.1.26100';Is64Bit=$true;IsAdmin=$true
            PendingReboot=$false
        }
        Mock Get-BISFInventory { $script:fakeOS }
        Mock Get-BISFCitrixReadiness {
            [pscustomobject]@{
                VDA=[pscustomobject]@{State='Running';Version='2507';MachineIdentityService='PvsVmAgent'}
                WEM=[pscustomobject]@{HostState='Running';CacheStatus='FilesPresent';Version='2507'}
            }
        }
        Mock Get-BISFProfileManagementServices {
            [pscustomobject]@{Name='frxsvc';State='Running';StartMode='Auto'}
        }
        Mock Get-BISFSystemDriveStatus { [pscustomobject]@{Drive='C:';FreeGB=24;TotalGB=100} }
        Mock Get-CimInstance { [pscustomobject]@{PartOfDomain=$true;Domain='example.test'} }
        Mock Remove-CimInstance { throw 'Clone verification must not delete profiles' }
        Mock Stop-Computer { throw 'Clone verification must not shut down' }
        Mock Start-ScheduledTask { throw 'Clone verification must not run Windows maintenance' }
    }
    It 'reports meaningful local service evidence without claiming VDA registered' {
        $result=Invoke-BISFCloneVerification $root "$root/Tests/Fixtures/OptInBaseline.xml"
        $result.Mode | Should -Be 'VerifyClone'
        $result.OSRelease | Should -Be 'Windows Server 2025'
        $result.DesktopService | Should -Be 'Running'
        $result.MCSIdentityService | Should -Be 'PvsVmAgent'
        $result.WEMCache | Should -Be 'FilesPresent'
        $result.ProfileManagers.Count | Should -Be 1
        $result.SystemDriveFreeGB | Should -Be 24
        $result.DomainJoined | Should -BeTrue
        $result.VDARegistration | Should -Match 'NotVerified'
        $result.ICAApplicationLaunch | Should -Match 'NotVerified'
        Should -Invoke Remove-CimInstance -Times 0
        Should -Invoke Stop-Computer -Times 0
        Should -Invoke Start-ScheduledTask -Times 0
    }
    It 'recognizes a Windows 11 client clone using ProductType not just build 26100' {
        $script:fakeOS.ProductType=1
        $script:fakeOS.Caption='Microsoft Windows 11 Enterprise'
        (Invoke-BISFCloneVerification $root "$root/Tests/Fixtures/OptInBaseline.xml").OSRelease | Should -Be 'Windows 11 24H2'
    }
    It 'does not claim full Citrix health if the local VDA readiness query fails' {
        Mock Get-BISFCitrixReadiness { throw 'VDA services unavailable' }
        $r=Invoke-BISFCloneVerification $root "$root/Tests/Fixtures/OptInBaseline.xml"
        $r.DesktopService | Should -Be 'Unknown'
        $r.VDARegistration | Should -Match 'NotVerified'
        Should -Invoke Stop-Computer -Times 0
    }
    It 'reports a pending reboot but never performs image modifications on the clone' {
        $script:fakeOS.PendingReboot=$true
        (Invoke-BISFCloneVerification $root "$root/Tests/Fixtures/OptInBaseline.xml").PendingReboot | Should -BeTrue
        Should -Invoke Remove-CimInstance -Times 0
    }
}
