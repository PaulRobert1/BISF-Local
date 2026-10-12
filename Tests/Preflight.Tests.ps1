BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    foreach ($name in 'Configuration','Preflight','Runner') {
        $p = "$root/Modules/Private/$name.ps1"
        if (Test-Path $p) { . $p }
    }
}
Describe 'Platform and plan validation' {
    BeforeEach {
        $i=[pscustomobject]@{Build=26100;ProductType=3;Version='10.0.26100';Edition='Desktop';PSVersion='5.1';Is64Bit=$true;IsAdmin=$true;PendingReboot=$false}
        $c=Read-BISFConfig "$root/GlobalConfig.xml" $root
    }
    It 'accepts Server 2025 and Windows 11 workstation builds' {
        { Test-BISFPlatform $i $c Prepare } | Should -Not -Throw
        $i.ProductType=1; $i.Build=22631
        { Test-BISFPlatform $i $c Prepare } | Should -Not -Throw
    }
    It 'rejects unsupported environment: <Field>=<Value>' -ForEach @(
        @{Field='ProductType';Value=2},@{Field='Build';Value=20348},
        @{Field='Edition';Value='Core'},@{Field='PSVersion';Value='7.6'},
        @{Field='Is64Bit';Value=$false},@{Field='IsAdmin';Value=$false},
        @{Field='Version';Value='11.0.0'}
    ) {
        $i.$Field=$Value
        { Test-BISFPlatform $i $c Prepare } | Should -Throw
    }
    It 'blocks pending reboot only for preparation and permits configured override' {
        $i.PendingReboot=$true
        { Test-BISFPlatform $i $c Prepare } | Should -Throw '*reboot*'
        { Test-BISFPlatform $i $c Personalize } | Should -Not -Throw
        $c.Preflight.BlockPendingReboot=$false
        { Test-BISFPlatform $i $c Prepare } | Should -Not -Throw
    }
    It 'has no destructive default operation' {
        @(Get-BISFPlan $c Prepare).Count | Should -Be 0
    }
    It 'orders selected preparation steps before shutdown' {
        $c.Cleanup.WindowsTemp=$true
        $c.Cleanup.CurrentUserTemp=$true
        $c.ConfigurationManager.PrepareIdentityReset=$true
        $c.Personalization.Enabled=$true
        $c.FinalAction='Shutdown'
        $ids=@(Get-BISFPlan $c Prepare).Id -join ','
        $ids | Should -Be 'WindowsTemp,CurrentUserTemp,CMPrepare,Lifecycle,Shutdown'
    }
    It 'plans reset before client start and completion' {
        $c.ConfigurationManager.CloneTrustedRootKeyReset=$true
        $c.ConfigurationManager.PrepareIdentityReset=$true
        (@(Get-BISFPlan $c Personalize).Id -join ',') | Should -Be 'CloneGuard,CMCloneReset,CMStart,Complete'
    }
}
