BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path $PSScriptRoot -Parent
    foreach ($name in 'Configuration','Operations','Lifecycle','Profiles','Maintenance','LogCleanup','Finalization','Preflight','Runner') {
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
    It 'recognizes Windows 11 client builds through 26H2: <Release>' -ForEach @(
        @{Build=22000;Release='Windows 11 21H2'},
        @{Build=22621;Release='Windows 11 22H2'},
        @{Build=22631;Release='Windows 11 23H2'},
        @{Build=26100;Release='Windows 11 24H2'},
        @{Build=26200;Release='Windows 11 25H2'},
        @{Build=26300;Release='Windows 11 26H2'},
        @{Build=28000;Release='Windows 11 26H1 (specialized hardware)'}
    ) {
        $i.ProductType=1
        $i.Build=$Build
        $i.Version="10.0.$Build"
        $platform=Get-BISFWindowsRelease $i
        $platform.Eligible | Should -BeTrue
        $platform.RecognizedBuild | Should -BeTrue
        $platform.Release | Should -Be $Release
        { Test-BISFPlatform $i $c Validate } | Should -Not -Throw
    }
    It 'distinguishes Windows Server 2025 and Windows 11 24H2 sharing build 26100' {
        $server=Get-BISFWindowsRelease $i
        $server.Release | Should -Be 'Windows Server 2025'
        $server.Family | Should -Be 'Windows Server'
        $i.ProductType=1
        $client=Get-BISFWindowsRelease $i
        $client.Release | Should -Be 'Windows 11 24H2'
        $client.Family | Should -Be 'Windows 11 workstation'
    }
    It 'warns for an unrecognized future Windows client build without claiming Citrix support' {
        $i.ProductType=1
        $i.Build=29000
        $i.Version='10.0.29000'
        $platform=Get-BISFWindowsRelease $i
        $platform.Eligible | Should -BeTrue
        $platform.RecognizedBuild | Should -BeFalse
        $platform.RequiresCompatibilityReview | Should -BeTrue
        $platform.Guidance | Should -Match 'Unknown client build'
    }
    It 'accepts later Windows Server builds with explicit compatibility-review diagnostics' {
        $i.Build=27500
        $i.Version='10.0.27500'
        $platform=Get-BISFWindowsRelease $i
        $platform.Eligible | Should -BeTrue
        $platform.RecognizedBuild | Should -BeFalse
        $platform.RequiresCompatibilityReview | Should -BeTrue
        { Test-BISFPlatform $i $c Prepare } | Should -Not -Throw
    }
    It 'accepts future Windows kernel families without claiming a recognized release: <ProductType>' -ForEach @(@{ProductType=1},@{ProductType=3}) {
        $i.ProductType=$ProductType; $i.Version='11.0.1000'; $i.Build=1000
        $platform=Get-BISFWindowsRelease $i
        $platform.Eligible | Should -BeTrue
        $platform.RecognizedBuild | Should -BeFalse
        $platform.RequiresCompatibilityReview | Should -BeTrue
        { Test-BISFPlatform $i $c Prepare } | Should -Not -Throw
        $i.PendingReboot=$true
        { Test-BISFPlatform $i $c Prepare } | Should -Throw '*reboot*'
        $i.ProductType=2
        { Test-BISFPlatform $i $c Prepare } | Should -Throw '*Domain controllers*'
    }
    It 'flags Windows 11 26H1 and 26H2 for VDA compatibility review' {
        $i.ProductType=1
        foreach ($build in @(26300,28000)) {
            $i.Build=$build
            $i.Version="10.0.$build"
            $platform=Get-BISFWindowsRelease $i
            $platform.RequiresCompatibilityReview | Should -BeTrue
        }
    }
    It 'rejects unsupported environment: <Field>=<Value>' -ForEach @(
        @{Field='ProductType';Value=2},@{Field='Build';Value=20348},
        @{Field='Edition';Value='Core'},@{Field='PSVersion';Value='7.6'},
        @{Field='Is64Bit';Value=$false},@{Field='IsAdmin';Value=$false},
        @{Field='Version';Value='6.3.9600'},@{Field='Version';Value='invalid'}
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
    It 'includes inactive profile deletion between temp cleanup and lifecycle when opted in' {
        $c.Cleanup.WindowsTemp=$true
        $c.Cleanup.CurrentUserTemp=$true
        $c.Cleanup.UserProfiles=$true
        $c.Personalization.Enabled=$true
        $c.FinalAction='Shutdown'
        (@(Get-BISFPlan $c Prepare).Id -join ',') | Should -Be 'WindowsTemp,CurrentUserTemp,UserProfiles,Lifecycle,Shutdown'
        (@(Get-BISFPlan $c Personalize).Id) | Should -Not -Contain 'UserProfiles'
    }
    It 'plans reset before client start and completion' {
        $c.ConfigurationManager.CloneTrustedRootKeyReset=$true
        $c.ConfigurationManager.PrepareIdentityReset=$true
        (@(Get-BISFPlan $c Personalize).Id -join ',') | Should -Be 'CloneGuard,CMCloneReset,CMStart,Complete'
    }
}
Describe 'Enabled integration dependencies' {
    BeforeAll {
        . "$root/Modules/Private/Operations.ps1"
        . "$root/Modules/Private/Lifecycle.ps1"
    }
    BeforeEach {
        $c=Read-BISFConfig "$root/GlobalConfig.xml" $root
        Mock Test-BISFPlatform {}
        Mock Test-BISFProtectedLocation {}
        Mock Test-BISFTaskOwnership {}
        Mock Get-BISFLoadedNonSystemProfiles { @() }
        Mock Get-BISFCurrentUserSid { 'S-1-5-21-111-222-333-1002' }
    }
    It 'refuses retained operator seal state even when deferred cleanup is disabled: <Mode>' -ForEach @(@{Mode='Prepare'},@{Mode='Validate'}) {
        $isolated=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $stateDir=Join-Path $isolated 'state'
        $null=New-Item -ItemType Directory -Path $stateDir -Force
        $statePath=Join-Path $stateDir 'operator-seal.json'
        $original='{"Status":"Pending","AcceptanceFixture":true}'
        [IO.File]::WriteAllText($statePath,$original)
        $c.Finalization.RemoveOperatorProfile=$false
        { Test-BISFPreflight $c $Mode @() $isolated "$root/GlobalConfig.xml" $null } | Should -Throw '*operator-seal state*'
        [IO.File]::ReadAllText($statePath) | Should -BeExactly $original
    }
    It 'blocks another interactive profile when the readiness option is enabled' {
        $c.Preflight.BlockOtherLoadedProfiles=$true
        Mock Get-BISFLoadedNonSystemProfiles { [pscustomobject]@{SID='S-1-5-21-111-222-333-1005';Loaded=$true} }
        { Test-BISFPreflight $c Prepare @() $root "$root/GlobalConfig.xml" $null } | Should -Throw '*Other loaded local user profiles*'
    }
    It 'blocks preparation with insufficient system-drive space' {
        $c.Preflight.MinimumSystemDriveFreeGB=15
        Mock Get-BISFSystemDriveStatus { [pscustomobject]@{Drive='C:';FreeGB=9;TotalGB=100} }
        { Test-BISFPreflight $c Prepare @() $root "$root/GlobalConfig.xml" $null } | Should -Throw '*Not enough free space*'
    }
    It 'allows sufficient disk space while keeping user-session checks independent' {
        $c.Preflight.MinimumSystemDriveFreeGB=15
        Mock Get-BISFSystemDriveStatus { [pscustomobject]@{Drive='C:';FreeGB=30;TotalGB=100} }
        { Test-BISFPreflight $c Prepare @() $root "$root/GlobalConfig.xml" $null } | Should -Not -Throw
    }
    It 'does not require client or scheduler commands when their features are disabled' {
        Mock Get-Command { throw 'unneeded dependency query' }
        { Test-BISFPreflight $c Prepare @() $root "$root/GlobalConfig.xml" $null } | Should -Not -Throw
    }
    It 'accepts ScheduledTasks commands implemented as CDXML functions' {
        $c.Personalization.Enabled=$true
        Mock Get-Command {
            if (($CommandType -band [System.Management.Automation.CommandTypes]::Function) -eq 0) { throw 'ScheduledTasks CDXML command is a Function, not a Cmdlet' }
            [pscustomobject]@{Name=$Name;CommandType='Function'}
        }
        { Test-BISFPreflight $c Prepare @(Get-BISFPlan $c Prepare) $root "$root/GlobalConfig.xml" $null } | Should -Not -Throw
    }
}
