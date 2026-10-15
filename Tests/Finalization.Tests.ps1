BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Configuration','Logging','Operations','Lifecycle','Profiles','Maintenance','LogCleanup','Finalization','Runner') {
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
    It 'refuses an operator profile containing the detected WEM cache' {
        $users=Join-Path $TestDrive 'Users'
        $operator=Join-Path $users 'operator'
        New-Item -ItemType Directory -Path $operator -Force | Out-Null
        Mock Get-BISFCurrentUserSid { 'S-1-5-21-111-222-333-1005' }
        Mock Get-BISFProfilesRoot { $users }
        Mock Get-CimInstance { [pscustomobject]@{Special=$false;LocalPath=$operator} }
        { Get-BISFOperatorSealTarget $c $root (Join-Path $root 'GlobalConfig.xml') -ProtectedPaths @((Join-Path $operator 'WEM')) } | Should -Throw '*inside*operator profile*'
    }
}
Describe 'Operator staging prerequisites before any preparation' {
    BeforeEach {
        . "$root/Modules/Private/Preflight.ps1"
        $c=Read-BISFConfig (Join-Path $root 'GlobalConfig.xml') $root
        $c.Cleanup.UserProfiles=$true
        $c.Finalization.RemoveOperatorProfile=$true
        $c.FinalAction='Shutdown'
        Mock Test-BISFPlatform {}
        Mock Get-BISFLoadedNonSystemProfiles { @() }
        Mock Get-BISFCurrentUserSid { 'S-1-5-21-111-222-333-1005' }
        Mock Test-BISFOperatorSealTaskOwnership {}
        Mock Get-Command {}
        Mock Test-BISFProtectedLocation {}
    }
    It 'checks the <Leaf> trust boundary before preparation' -ForEach @(@{Leaf='Modules'},@{Leaf='GlobalConfig.xsd'}) {
        Mock Test-BISFProtectedLocation { if ((Split-Path -Leaf $Path) -eq $Leaf) { throw 'Untrusted dependency' } }
        { Test-BISFPreflight $c Prepare @(Get-BISFPlan $c Prepare) $root (Join-Path $root 'GlobalConfig.xml') $null } | Should -Throw '*Untrusted dependency*'
    }
    It 'refuses retained operator state during preflight rather than after ordinary cleanup' {
        Mock Test-Path { $LiteralPath -like '*operator-seal.json' }
        { Test-BISFPreflight $c Prepare @(Get-BISFPlan $c Prepare) $root (Join-Path $root 'GlobalConfig.xml') $null } | Should -Throw '*Existing operator-seal state*'
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
    It 'permits a normal RID >=1000 operator even when its profile directory is named Administrator' {
        $adminNamed=Join-Path $script:rootPath 'Administrator'
        New-Item -ItemType Directory -Path $adminNamed | Out-Null
        $script:p.LocalPath=$adminNamed
        $script:state.OperatorPath=$adminNamed
        Test-BISFOperatorSealCandidate $script:state $script:c | Should -BeTrue
    }
    It 'refuses an operator whose profile becomes special or points at a template directory' {
        $script:p.Special=$true
        { Test-BISFOperatorSealCandidate $script:state $script:c } | Should -Throw '*special*'
        $script:p.Special=$false
        $template=Join-Path $script:rootPath 'Default'
        New-Item -ItemType Directory -Path $template | Out-Null
        $script:p.LocalPath=$template
        $script:state.OperatorPath=$template
        { Test-BISFOperatorSealCandidate $script:state $script:c } | Should -Throw '*template*'
    }
    It 'waits while an unloaded profile retains a nonzero reference count' {
        $script:p.RefCount=1
        Test-BISFOperatorSealCandidate $script:state $script:c | Should -BeFalse
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
        $script:boundaryRoot=Join-Path $TestDrive ('Users-'+[guid]::NewGuid().ToString('N'))
        $script:boundaryPath=Join-Path $script:boundaryRoot 'operator'
        New-Item -ItemType Directory -Path $script:boundaryPath -Force | Out-Null
        $script:boundaryProfile=[pscustomobject]@{SID='S-1-5-21-111-222-333-1001';LocalPath=$script:boundaryPath;Loaded=$false;Special=$false;RefCount=0}
        Mock Read-BISFOperatorSealState { [pscustomobject]@{OperatorSid='S-1-5-21-111-222-333-1001';OperatorPath=$script:boundaryPath;ProfilesRoot=$script:boundaryRoot;TimeoutMinutes=1} }
        Mock New-BISFLogger { [pscustomobject]@{Enabled=$false;LogFile=$null} }
        Mock Test-BISFOperatorSealCandidate { $true }
        Mock Get-BISFJournalStatus { [pscustomobject]@{PreparationPending=$false;PersonalizationPending=$false} }
        Mock Get-BISFPendingRebootReasons { @() }
        Mock Get-CimInstance {
            if ($script:profilesRemaining) { $script:boundaryProfile }
        }
        Mock Remove-BISFCimUserProfile { $script:trace.Add('delete'); $script:profilesRemaining=$false }
        Mock Unregister-ScheduledTask { $script:trace.Add('unregister') }
        Mock Test-BISFProtectedLocation {}
        Mock Remove-Item { $script:trace.Add('state-delete') }
        Mock Write-BISFLog {}
        Mock Enter-BISFLock { 'lock' }
        Mock Exit-BISFLock {}
        Mock Stop-Computer { $script:trace.Add('shutdown') }
        Mock Invoke-BISFLogCleanup {}
    }
    It 'deletes the verified profile and cleans task/state BEFORE accepting shutdown' {
        $result=Invoke-BISFOperatorSealFinalizer $root $script:cfg
        $result | Should -Be 0
        ($script:trace -join ',') | Should -Be 'delete,unregister,state-delete,shutdown'
    }
    It 'performs explicitly enabled log cleanup after profile deletion and before shutdown' {
        $script:trace.Clear()
        Mock Invoke-BISFLogCleanup { $script:trace.Add('logs') }
        $r=Invoke-BISFOperatorSealFinalizer $root $script:cfg
        $r | Should -Be 0
        ($script:trace -join ',') | Should -Be 'delete,unregister,state-delete,logs,shutdown'
    }
    It 'refuses shutdown if log cleanup fails after an operator profile was removed' {
        Mock Invoke-BISFLogCleanup { throw 'Event Log cleanup denied' }
        $r=Invoke-BISFOperatorSealFinalizer $root $script:cfg
        $r | Should -Be 2
        $script:trace | Should -Not -Contain 'shutdown'
        $script:trace | Should -Contain 'delete'
    }
    It 'refuses shutdown when profile provider fails to delete' {
        Mock Remove-BISFCimUserProfile { throw 'Provider refused deletion' }
        (Invoke-BISFOperatorSealFinalizer $root $script:cfg) | Should -Be 2
        $script:trace | Should -Not -Contain 'shutdown'
    }
    It 'revalidates the actual deletion object when <Field> changes after the candidate check' -ForEach @(
        @{Field='SID';Value='S-1-5-21-111-222-333-1009'},
        @{Field='LocalPath';Value='C:\Users\somebody-else'},
        @{Field='Loaded';Value=$true},@{Field='Special';Value=$true},@{Field='RefCount';Value=1}
    ) {
        $script:boundaryProfile.$Field=$Value
        (Invoke-BISFOperatorSealFinalizer $root $script:cfg) | Should -Be 2
        $script:trace | Should -Not -Contain 'delete'
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

