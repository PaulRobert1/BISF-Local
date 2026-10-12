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
            $r=Invoke-BISFLocal $config $package Prepare -Confirm:$false
            $r.ExitCode | Should -Be 0
            $r.Results.Count | Should -Be 0
        }
    }
}
