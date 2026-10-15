BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Configuration','Logging','Operations','Lifecycle','Profiles','Maintenance','Finalization') {
        . "$root/Modules/Private/$n.ps1"
    }
}
Describe 'Two-phase operator seal configuration and trust boundaries' {
    BeforeEach {
        $c=Read-BISFConfig (Join-Path $root 'GlobalConfig.xml') $root
        $c.Finalization.RemoveOperatorProfile=$true
        $c.Cleanup.UserProfiles=$true
        $c.FinalAction='Shutdown'
        $c.Preflight.BlockPendingReboot=$true
    }
    It 'requires opt-in profile cleanup' {
        $c.Cleanup.UserProfiles=$false
        { Test-BISFOperatorSealSettings $c } | Should -Throw '*UserProfiles*'
    }
    It 'requires an actual final shutdown, not an unattended profile deletion' {
        $c.FinalAction='None'
        { Test-BISFOperatorSealSettings $c } | Should -Throw '*FinalAction*'
    }
    It 'refuses clone-personalization and Configuration Manager identity changes' {
        $c.Personalization.Enabled=$true
        { Test-BISFOperatorSealSettings $c } | Should -Throw '*cannot be combined*'
        $c.Personalization.Enabled=$false
        $c.ConfigurationManager.PrepareIdentityReset=$true
        { Test-BISFOperatorSealSettings $c } | Should -Throw '*cannot be combined*'
    }
    It 'refuses premature VDA stopping and bypassed pending-reboot safeguards' {
        $c.Citrix.VDA.StopBeforeShutdown=$true
        { Test-BISFOperatorSealSettings $c } | Should -Throw '*StopBeforeShutdown*'
        $c.Citrix.VDA.StopBeforeShutdown=$false
        $c.Preflight.BlockPendingReboot=$false
        { Test-BISFOperatorSealSettings $c } | Should -Throw '*BlockPendingReboot*'
    }
    It 'uses a fixed quoted PowerShell action with no execution policy bypass' {
        $args=Get-BISFOperatorSealTaskArguments 'C:\Install\BISF\Invoke-BISF.ps1' 'C:\Install\BISF\GlobalConfig.xml'
        $args | Should -Match 'Mode Finalize'
        $args | Should -Not -Match 'ExecutionPolicy|bypass|cmd.exe'
        { Get-BISFOperatorSealTaskArguments 'C:\broken"name.ps1' 'C:\config.xml' } | Should -Throw
    }
    It 'refuses to overwrite an existing reserved task without trusting its owner' {
        Mock Get-ScheduledTask {
            [pscustomobject]@{
                Description='Unrelated task';TaskName='BISF-Local-OperatorSeal';Actions=@()
                Principal=[pscustomobject]@{UserId='S-1-5-18'}
            }
        }
        { Test-BISFOperatorSealTaskOwnership 'C:\Install\BISF' 'C:\Install\BISF\GlobalConfig.xml' } | Should -Throw
    }
    It 'refuses built-in administrator RID 500 even when that account is running Prepare' {
        Mock Get-BISFCurrentUserSid { 'S-1-5-21-111-222-333-500' }
        { Get-BISFOperatorSealTarget $c 'C:\Install\BISF' 'C:\Install\BISF\GlobalConfig.xml' } | Should -Throw '*built-in*'
    }
    It 'refuses to stage if the current profile has an explicit SID exclusion' {
        $c.Cleanup.ExcludedProfileSIDs=@('S-1-5-21-111-222-333-1005')
        Mock Get-BISFCurrentUserSid { 'S-1-5-21-111-222-333-1005' }
        { Get-BISFOperatorSealTarget $c 'C:\Install\BISF' 'C:\Install\BISF\GlobalConfig.xml' } | Should -Throw '*excluded*'
    }
}
Describe 'SYSTEM finalizer operator profile safety rules' {
    BeforeEach {
        $script:rootPath=Join-Path $TestDrive ('Profiles-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:rootPath | Out-Null
        $script:userPath=Join-Path $script:rootPath 'Operator'
        New-Item -ItemType Directory -Path $script:userPath | Out-Null
        $script:state=[pscustomobject]@{
            OperatorSid='S-1-5-21-111-222-333-1001'
            OperatorPath=$script:userPath
            ProfilesRoot=$script:rootPath
            Master=[pscustomobject]@{Name='MASTER';MachineGuid='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';SmbiosUuid='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'}
            ConfigHash='a'*64
        }
        $script:p=[pscustomobject]@{SID=$script:state.OperatorSid;LocalPath=$script:userPath;Loaded=$false;Special=$false;RefCount=0}
        $script:c=Read-BISFConfig (Join-Path $root 'GlobalConfig.xml') $root
        $script:c.Finalization.RemoveOperatorProfile=$true
        $script:c.FinalAction='Shutdown'
        $script:c | Add-Member NoteProperty Path (Join-Path $root 'GlobalConfig.xml')
        $script:state.ConfigHash=(Get-FileHash -LiteralPath $script:c.Path).Hash
        Mock Get-BISFCurrentUserSid { 'S-1-5-18' }
        Mock Get-BISFIdentity { $script:state.Master }
        Mock Get-BISFProfilesRoot { $script:rootPath }
        Mock Get-BISFLoadedNonSystemProfiles { @() }
        Mock Get-CimInstance { $script:p }
    }
    It 'never permits finalization from an interactive administrator account' {
        Mock Get-BISFCurrentUserSid { 'S-1-5-21-111-222-333-1001' }
        { Test-BISFOperatorSealCandidate $script:state $script:c } | Should -Throw '*SYSTEM*'
    }
    It 'waits instead of deleting while any non-system profile is loaded' {
        Mock Get-BISFLoadedNonSystemProfiles { [pscustomobject]@{SID=$script:state.OperatorSid;Loaded=$true;Special=$false} }
        Test-BISFOperatorSealCandidate $script:state $script:c | Should -BeFalse
    }
    It 'refuses finalization on a provisioned clone with a changed machine identity' {
        Mock Get-BISFIdentity { [pscustomobject]@{Name='CLONE';MachineGuid='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';SmbiosUuid='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'} }
        { Test-BISFOperatorSealCandidate $script:state $script:c } | Should -Throw '*machine identity changed*'
    }
    It 'accepts only an eligible unloaded profile at the original path' {
        Test-BISFOperatorSealCandidate $script:state $script:c | Should -BeTrue
        $script:p.LocalPath=Join-Path $script:rootPath 'Other'
        { Test-BISFOperatorSealCandidate $script:state $script:c } | Should -Throw '*no longer matches*'
    }
    It 'fails on changed configuration or disabled finalization' {
        $script:state.ConfigHash='b'*64
        { Test-BISFOperatorSealCandidate $script:state $script:c } | Should -Throw '*Configuration changed*'
        $script:state.ConfigHash=(Get-FileHash $script:c.Path).Hash
        $script:c.Finalization.RemoveOperatorProfile=$false
        { Test-BISFOperatorSealCandidate $script:state $script:c } | Should -Throw '*disabled*'
    }
}
Describe 'Finalization shutdown boundary' {
    BeforeEach {
        $script:cfg=Join-Path $TestDrive ('Config-'+[guid]::NewGuid().ToString('N')+'.xml')
        [xml]$xml=Get-Content (Join-Path $root 'GlobalConfig.xml') -Raw
        $xml.BISF.Cleanup.UserProfiles='true'
        $xml.BISF.Finalization.RemoveOperatorProfile='true'
        $xml.BISF.FinalAction='Shutdown'
        $xml.BISF.Logging.Enabled='false'
        $xml.Save($script:cfg)
        $script:trace=New-Object 'System.Collections.Generic.List[string]'
        $script:profilesRemaining=$true
        Mock Read-BISFOperatorSealState { [pscustomobject]@{OperatorSid='S-1-5-21-111-222-333-1001';OperatorPath='C:\Users\operator';TimeoutMinutes=1} }
        Mock New-BISFLogger { [pscustomobject]@{Enabled=$false;LogFile=$null} }
        Mock Test-BISFOperatorSealCandidate { $true }
        Mock Get-BISFJournalStatus { [pscustomobject]@{PreparationPending=$false;PersonalizationPending=$false} }
        Mock Get-BISFPendingRebootReasons { @() }
        Mock Get-CimInstance {
            if ($script:profilesRemaining) { [pscustomobject]@{SID='S-1-5-21-111-222-333-1001'} }
        }
        Mock Remove-BISFCimUserProfile { $script:trace.Add('delete'); $script:profilesRemaining=$false }
        Mock Unregister-ScheduledTask { $script:trace.Add('unregister') }
        Mock Test-BISFProtectedLocation {}
        Mock Remove-Item { $script:trace.Add('state-delete') }
        Mock Write-BISFLog {}
        Mock Enter-BISFLock { 'lock' }
        Mock Exit-BISFLock {}
        Mock Stop-Computer { $script:trace.Add('shutdown') }
    }
    It 'deletes the verified profile and cleans task/state BEFORE accepting shutdown' {
        $result=Invoke-BISFOperatorSealFinalizer $root $script:cfg
        $result | Should -Be 0
        ($script:trace -join ',') | Should -Be 'delete,unregister,state-delete,shutdown'
    }
    It 'refuses shutdown when profile provider fails to delete' {
        Mock Remove-BISFCimUserProfile { throw 'Provider refused deletion' }
        (Invoke-BISFOperatorSealFinalizer $root $script:cfg) | Should -Be 2
        $script:trace | Should -Not -Contain 'shutdown'
    }
    It 'refuses shutdown when preparation is incomplete' {
        Mock Get-BISFJournalStatus { [pscustomobject]@{PreparationPending=$true;PersonalizationPending=$false} }
        (Invoke-BISFOperatorSealFinalizer $root $script:cfg) | Should -Be 2
        $script:trace | Should -Not -Contain 'delete'
    }
    It 'refuses shutdown if servicing leaves a pending reboot' {
        Mock Get-BISFPendingRebootReasons { @('Windows Update RebootRequired') }
        (Invoke-BISFOperatorSealFinalizer $root $script:cfg) | Should -Be 2
        $script:trace | Should -Not -Contain 'delete'
    }
    It 'refuses shutdown when scheduled task deregistration fails' {
        Mock Unregister-ScheduledTask { throw 'Task not removable' }
        (Invoke-BISFOperatorSealFinalizer $root $script:cfg) | Should -Be 2
        $script:trace | Should -Not -Contain 'shutdown'
    }
}
