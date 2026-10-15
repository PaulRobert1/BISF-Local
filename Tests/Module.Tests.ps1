BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules/BISF.Local.psm1') -Force
}
Describe 'Exported module under production strict mode' {
    It 'can execute a default empty preparation with disabled logging' {
        InModuleScope BISF.Local {
            $root=Split-Path $PSScriptRoot -Parent
            $package=Split-Path $root -Parent
            # Module PSScriptRoot points to Modules, so resolve via module path instead.
            $package=Split-Path (Split-Path (Get-Module BISF.Local).Path -Parent) -Parent
            $config=Join-Path $TestDrive 'config.xml'
            (Get-Content (Join-Path $package 'GlobalConfig.xml') -Raw).Replace('<Enabled>true</Enabled>','<Enabled>false</Enabled>') | Set-Content $config
            Mock Get-BISFInventory { [pscustomobject]@{Caption='Test';Build=26100;Identity=[pscustomobject]@{Name='MASTER'};CMInstalled=$false} }
            Mock Test-BISFPreflight {}
            Mock Get-BISFPendingRebootReasons { @() }
            $r=Invoke-BISFLocal $config $package Prepare -Confirm:$false
            $r.ExitCode | Should -Be 0
            $r.Results.Count | Should -Be 0
        }
    }
}
Describe 'Citrix production module strict mode' {
    It 'discovers and reports an enabled VDA without relying on dot-source test scope' {
        InModuleScope BISF.Local {
            $package=Split-Path (Split-Path (Get-Module BISF.Local).Path -Parent) -Parent
            $c=Read-BISFConfig (Join-Path $package 'GlobalConfig.xml') $package
            $c.Citrix.WEM.Enabled=$false
            Mock Get-BISFCitrixServices { @(
                [pscustomobject]@{Name='BrokerAgent';DisplayName='Citrix Desktop Service';StartMode='Auto';State='Running';PathName='C:\Citrix\BrokerAgent.exe'},
                [pscustomobject]@{Name='PvsVmAgent';DisplayName='Citrix Pvs for VMs Agent';StartMode='Manual';State='Stopped'}
            ) }
            Mock Get-BISFCitrixProducts { [pscustomobject]@{DisplayName='Citrix Virtual Delivery Agent 2507 LTSR';DisplayVersion='7.45.0.1'} }
            Mock Get-BISFServiceBinaryVersion { '2507.0.1' }
            $r=Get-BISFCitrixReadiness $c Prepare
            $r.VDA.MachineIdentityService | Should -Be 'PvsVmAgent'
            $r.VDA.Version | Should -Be '7.45.0.1'
            $r.WEM | Should -BeNullOrEmpty
        }
    }
}
