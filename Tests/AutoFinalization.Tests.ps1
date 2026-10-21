BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($name in 'Configuration','Logging','Operations','Lifecycle','Profiles','Maintenance','LogCleanup','Session','Finalization') {
        . "$root/Modules/Private/$name.ps1"
    }
    # Only supply absent Windows command signatures so Pester can mock them.
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        function Get-ScheduledTask { [CmdletBinding()]param([string]$TaskName,[string]$TaskPath) }
    }
    if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
        function Unregister-ScheduledTask { [CmdletBinding(SupportsShouldProcess)]param([string]$TaskName,[string]$TaskPath) }
    }
    if (-not (Get-Command New-ScheduledTaskAction -ErrorAction SilentlyContinue)) {
        function New-ScheduledTaskAction { [CmdletBinding()]param($Execute,$Argument,$WorkingDirectory) }
        function New-ScheduledTaskPrincipal { [CmdletBinding()]param($UserId,$LogonType,$RunLevel) }
        function New-ScheduledTaskSettingsSet { [CmdletBinding()]param($MultipleInstances,$ExecutionTimeLimit,[switch]$StartWhenAvailable) }
        function Register-ScheduledTask { [CmdletBinding()]param($TaskName,$TaskPath,$Action,$Principal,$Settings,$Description) }
        function Start-ScheduledTask { [CmdletBinding()]param($TaskName,$TaskPath) }
    }
}

Describe 'SYSTEM task staging and failed acknowledgement recovery' {
    BeforeAll { $savedSystemRoot=$env:SystemRoot;$env:SystemRoot=Join-Path $TestDrive 'Windows' }
    AfterAll { $env:SystemRoot=$savedSystemRoot }
    BeforeEach {
        $script:stageTrace=New-Object 'System.Collections.Generic.List[string]'
        $script:stageConfig=[pscustomobject]@{Finalization=[pscustomobject]@{TimeoutMinutes=30}}
        $script:stageState=[pscustomobject]@{Generation='11111111-2222-3333-4444-555555555555'}
        Mock Test-BISFOperatorSealStaging {}
        Mock New-BISFOperatorSealState { $script:stageState }
        Mock Write-BISFState { $script:stageTrace.Add('write-state') }
        Mock New-ScheduledTaskAction { 'action' }
        Mock New-ScheduledTaskPrincipal { 'principal' }
        Mock New-ScheduledTaskSettingsSet { 'settings' }
        Mock Register-ScheduledTask { $script:stageTrace.Add('register') }
        Mock Start-ScheduledTask { $script:stageTrace.Add('start') }
        Mock Wait-BISFOperatorSealReady { $script:stageTrace.Add('acknowledged');$script:stageState }
        Mock Unregister-ScheduledTask { $script:stageTrace.Add('unregister') }
        Mock Test-Path { $true }
        Mock Remove-Item { $script:stageTrace.Add('remove-state') }
    }
    It 'returns a single acknowledged state after the worker starts' {
        $result=@(Register-BISFOperatorSeal $root (Join-Path $root 'GlobalConfig.xml') $script:stageConfig $null -ExpectedHash ('A'*64))
        $result.Count | Should -Be 1
        $result[0].Generation | Should -Be $script:stageState.Generation
        ($script:stageTrace -join ',') | Should -Be 'write-state,register,start,acknowledged'
    }
    It 'retains task and state after accepted startup if readiness fails' {
        Mock Wait-BISFOperatorSealReady { throw 'Worker acknowledgement timeout' }
        { Register-BISFOperatorSeal $root (Join-Path $root 'GlobalConfig.xml') $script:stageConfig $null -ExpectedHash ('A'*64) } | Should -Throw '*acknowledgement timeout*'
        ($script:stageTrace -join ',') | Should -Be 'write-state,register,start'
        Should -Invoke Unregister-ScheduledTask -Times 0
        Should -Invoke Remove-Item -Times 0
    }
    It 'cleans only this staging attempt when Task Scheduler rejects startup' {
        Mock Start-ScheduledTask { throw 'Task start rejected' }
        { Register-BISFOperatorSeal $root (Join-Path $root 'GlobalConfig.xml') $script:stageConfig $null -ExpectedHash ('A'*64) } | Should -Throw '*start rejected*'
        ($script:stageTrace -join ',') | Should -Be 'write-state,register,unregister,remove-state'
        Should -Invoke Wait-BISFOperatorSealReady -Times 0
    }
}

Describe 'Acknowledged worker validation and bounded readiness wait' {
    BeforeAll {
        $savedSystemRoot=$env:SystemRoot
        $env:SystemRoot=Join-Path $TestDrive 'Windows'
    }
    AfterAll { $env:SystemRoot=$savedSystemRoot }
    BeforeEach {
        $script:workerStarted=[datetime]::UtcNow.AddMinutes(-1)
        $script:readyState=[pscustomobject]@{
            Generation='11111111-2222-3333-4444-555555555555'
            WorkerReady=[pscustomobject]@{
                Generation='11111111-2222-3333-4444-555555555555';ProcessId=4321
                StartedUtc=$script:workerStarted.ToString('o');AcknowledgedUtc=[datetime]::UtcNow.ToString('o')
            }
        }
        Mock Test-BISFOperatorSealTaskOwnership { [pscustomobject]@{State='Running'} }
        Mock Read-BISFOperatorSealState { $script:readyState }
        Mock Get-Process {
            [pscustomobject]@{SessionId=0;StartTime=$script:workerStarted;Path=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')}
        }
        Mock Start-Sleep {}
    }
    It 'returns the acknowledged generation only while its exact SYSTEM worker and task are running' {
        $result=Wait-BISFOperatorSealReady $root (Join-Path $root 'GlobalConfig.xml') $script:readyState.Generation -TimeoutSeconds 1
        $result.Generation | Should -Be $script:readyState.Generation
        $result.WorkerReady.ProcessId | Should -Be 4321
        Should -Invoke Start-Sleep -Times 0
        Should -Invoke Test-BISFOperatorSealTaskOwnership -Times 1 -ParameterFilter { $AllowExisting }
    }
    It 'refuses a changed seal generation' {
        { Wait-BISFOperatorSealReady $root (Join-Path $root 'GlobalConfig.xml') '99999999-2222-3333-4444-555555555555' -TimeoutSeconds 1 } | Should -Throw '*generation changed*'
    }
    It 'refuses a stale acknowledgement from a different generation' {
        $script:readyState.WorkerReady.Generation='99999999-2222-3333-4444-555555555555'
        { Wait-BISFOperatorSealReady $root (Join-Path $root 'GlobalConfig.xml') $script:readyState.Generation -TimeoutSeconds 1 } | Should -Throw '*does not match*'
    }
    It 'refuses an acknowledgement with no live worker process' {
        Mock Get-Process { throw 'Worker no longer exists' }
        { Wait-BISFOperatorSealReady $root (Join-Path $root 'GlobalConfig.xml') $script:readyState.Generation -TimeoutSeconds 1 } | Should -Throw '*no longer exists*'
    }
    It 'refuses a reused worker PID' {
        $script:readyState.WorkerReady.StartedUtc=$script:workerStarted.AddHours(-1).ToString('o')
        { Test-BISFOperatorSealWorkerReady $script:readyState } | Should -Throw '*no longer the expected*'
    }
    It 'refuses the wrong worker executable or session: <Kind>' -ForEach @(
        @{Kind='executable';Path='C:\Other\powershell.exe';Session=0},
        @{Kind='session';Path=$null;Session=3}
    ) {
        $script:badWorkerPath=$Path;$script:badWorkerSession=$Session
        Mock Get-Process {
            $path=if($script:badWorkerPath){$script:badWorkerPath}else{Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'}
            [pscustomobject]@{SessionId=$script:badWorkerSession;StartTime=$script:workerStarted;Path=$path}
        }
        { Test-BISFOperatorSealWorkerReady $script:readyState } | Should -Throw '*no longer the expected*'
    }
    It 'refuses a task that stopped after acknowledging readiness' {
        Mock Test-BISFOperatorSealTaskOwnership { [pscustomobject]@{State='Ready'} }
        { Wait-BISFOperatorSealReady $root (Join-Path $root 'GlobalConfig.xml') $script:readyState.Generation -TimeoutSeconds 1 } | Should -Throw '*no longer running*'
    }
    It 'refuses an altered task instead of trusting its reserved name' {
        Mock Test-BISFOperatorSealTaskOwnership { throw 'Task is not owned by this package' }
        { Wait-BISFOperatorSealReady $root (Join-Path $root 'GlobalConfig.xml') $script:readyState.Generation -TimeoutSeconds 1 } | Should -Throw '*not owned*'
    }
    It 'times out without accepting a task that never acknowledged' {
        $script:readyState.PSObject.Properties.Remove('WorkerReady')
        { Wait-BISFOperatorSealReady $root (Join-Path $root 'GlobalConfig.xml') $script:readyState.Generation -TimeoutSeconds 1 } | Should -Throw '*did not acknowledge*'
        Should -Invoke Start-Sleep -Times 1
    }
    It 'refuses malformed acknowledgement metadata' {
        $script:readyState.WorkerReady.PSObject.Properties.Remove('StartedUtc')
        { Test-BISFOperatorSealWorkerReady $script:readyState } | Should -Throw '*missing StartedUtc*'
    }
}

Describe 'Final interactive revalidation before operator sign-out' {
    BeforeEach {
        $script:signOutContext=[pscustomobject]@{
            Generation='11111111-2222-3333-4444-555555555555';SID='S-1-5-21-111-222-333-1001'
            SessionId=3;WorkerProcessId=4321;WorkerStartedUtc='2026-10-21T12:00:00.0000000Z'
        }
        $script:signOutState=[pscustomobject]@{
            Generation=$script:signOutContext.Generation;OperatorSid=$script:signOutContext.SID
            ConfigHash=('A'*64);Master=[pscustomobject]@{Name='MASTER';MachineGuid='master-guid';SmbiosUuid='master-uuid'}
            ProfilesRoot='C:\Users'
            WorkerReady=[pscustomobject]@{ProcessId=4321;StartedUtc=$script:signOutContext.WorkerStartedUtc}
        }
        Mock Test-BISFProtectedLocation {}
        Mock Read-BISFConfig { [pscustomobject]@{Finalization=[pscustomobject]@{RemoveOperatorProfile=$true};FinalAction='Shutdown'} }
        Mock Test-BISFOperatorSealSettings {}
        Mock Read-BISFOperatorSealState { $script:signOutState }
        Mock Get-BISFFileHash { [pscustomobject]@{Hash=('A'*64)} }
        Mock Get-BISFIdentity { $script:signOutState.Master }
        Mock Get-BISFProfilesRoot { 'C:\Users' }
        Mock Get-BISFOperatorSealProfile { [pscustomobject]@{Ready=$false} }
        Mock Test-BISFOperatorSealTaskOwnership { [pscustomobject]@{State='Running'} }
        Mock Test-BISFOperatorSealWorkerReady {}
        Mock Get-BISFJournalStatus { [pscustomobject]@{PreparationPending=$false} }
        Mock Get-BISFPendingRebootReasons { @() }
        Mock Get-BISFLoadedNonSystemProfiles { @() }
        Mock Request-BISFOperatorSignOut {}
        Mock Stop-Computer { throw 'Interactive sign-out must never shut down directly' }
    }
    It 'requests only the captured operator session after all final checks succeed' {
        Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -Confirm:$false
        Should -Invoke Request-BISFOperatorSignOut -Times 1 -ParameterFilter { $ExpectedSid -eq $script:signOutContext.SID -and $ExpectedSessionId -eq 3 }
        Should -Invoke Stop-Computer -Times 0
    }
    It 'refuses a changed preparation context' {
        $script:signOutState.Generation='99999999-2222-3333-4444-555555555555'
        { Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -Confirm:$false } | Should -Throw '*no longer matches*'
        Should -Invoke Request-BISFOperatorSignOut -Times 0
    }
    It 'refuses changed configuration' {
        Mock Get-BISFFileHash { [pscustomobject]@{Hash=('B'*64)} }
        { Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -Confirm:$false } | Should -Throw '*Configuration changed*'
        Should -Invoke Request-BISFOperatorSignOut -Times 0
    }
    It 'refuses a replacement worker after preparation returned' {
        $script:signOutState.WorkerReady.ProcessId=9876
        { Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -Confirm:$false } | Should -Throw '*finalizer changed*'
        Should -Invoke Request-BISFOperatorSignOut -Times 0
    }
    It 'refuses a worker that is no longer running' {
        Mock Test-BISFOperatorSealTaskOwnership { [pscustomobject]@{State='Ready'} }
        { Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -Confirm:$false } | Should -Throw '*not running*'
        Should -Invoke Request-BISFOperatorSignOut -Times 0
    }
    It 'refuses a new pending reboot before sign-out' {
        Mock Get-BISFPendingRebootReasons { @('Windows Update') }
        { Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -Confirm:$false } | Should -Throw '*requires a reboot*'
        Should -Invoke Request-BISFOperatorSignOut -Times 0
    }
    It 'rechecks worker liveness after potentially slow final profile queries' {
        $script:workerStopped=$false
        Mock Test-BISFOperatorSealTaskOwnership {
            $state=if($script:workerStopped){'Ready'}else{'Running'}
            [pscustomobject]@{State=$state}
        }
        Mock Get-BISFLoadedNonSystemProfiles { $script:workerStopped=$true;@() }
        { Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -Confirm:$false } | Should -Throw '*not running*'
        Should -Invoke Request-BISFOperatorSignOut -Times 0
    }
    It 'refuses a second loaded user before sign-out' {
        Mock Get-BISFLoadedNonSystemProfiles { [pscustomobject]@{SID='somebody-else'} }
        { Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -Confirm:$false } | Should -Throw '*Another user profile*'
        Should -Invoke Request-BISFOperatorSignOut -Times 0
    }
    It 'surfaces a rejected native sign-out without an interactive shutdown fallback' {
        Mock Request-BISFOperatorSignOut { throw 'Windows rejected sign-out' }
        { Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -Confirm:$false } | Should -Throw '*Windows rejected*'
        Should -Invoke Stop-Computer -Times 0
    }
    It 'does not read state or sign out in preview mode' {
        Invoke-BISFOperatorSignOut $root (Join-Path $root 'GlobalConfig.xml') $script:signOutContext -WhatIf
        Should -Invoke Read-BISFOperatorSealState -Times 0
        Should -Invoke Request-BISFOperatorSignOut -Times 0
    }
}

Describe 'SYSTEM acknowledgement before automatic operator sign-out' {
    BeforeEach {
        $script:trace=New-Object 'System.Collections.Generic.List[string]'
        $script:busy=$true
        $script:written=$null
        $script:seal=[pscustomobject]@{
            SchemaVersion=1;Generation='11111111-2222-3333-4444-555555555555';Status='Pending'
            ConfigHash=('A'*64);Master=[pscustomobject]@{Name='MASTER';MachineGuid='master-guid';SmbiosUuid='master-uuid'}
            OperatorSid='S-1-5-21-111-222-333-1001';OperatorPath='C:\Users\Operator'
            ProfilesRoot='C:\Users';TimeoutMinutes=1;StagedUtc=[datetime]::UtcNow.ToString('o')
        }
        Mock Read-BISFConfig {
            [pscustomobject]@{
                Finalization=[pscustomobject]@{RemoveOperatorProfile=$true;TimeoutMinutes=1}
                FinalAction='Shutdown';Cleanup=[pscustomobject]@{ExcludedProfileSIDs=@()}
            }
        }
        Mock Test-BISFOperatorSealSettings {}
        Mock Read-BISFOperatorSealState { $script:seal }
        Mock New-BISFLogger { [pscustomobject]@{Enabled=$false;LogFile=$null} }
        Mock Write-BISFLog {}
        Mock Get-BISFCurrentUserSid { 'S-1-5-18' }
        Mock Get-BISFFileHash { [pscustomobject]@{Hash=('A'*64)} }
        Mock Get-BISFIdentity { $script:seal.Master }
        Mock Get-BISFProfilesRoot { 'C:\Users' }
        Mock Get-BISFLoadedNonSystemProfiles {
            if ($script:busy -and $CurrentSid -ne $script:seal.OperatorSid) { [pscustomobject]@{SID=$script:seal.OperatorSid} }
        }
        Mock Get-BISFOperatorSealProfile { [pscustomobject]@{Ready=(-not $script:busy);Profile=[pscustomobject]@{SID=$script:seal.OperatorSid}} }
        Mock Get-BISFJournalStatus { [pscustomobject]@{PreparationPending=$false;PersonalizationPending=$false} }
        Mock Get-BISFPendingRebootReasons { @() }
        Mock Write-BISFState { $script:written=$State; $script:trace.Add('acknowledge') }
        Mock Start-Sleep { $script:trace.Add('wait-for-unload');$script:busy=$false }
        Mock Enter-BISFLock { $script:trace.Add('lock');'lock' }
        Mock Exit-BISFLock { if($null -ne $Lock){$script:trace.Add('unlock')} }
        Mock Remove-BISFCimUserProfile { $script:trace.Add('delete-profile') }
        Mock Assert-BISFUserProfileRemoved { $script:trace.Add('verify-removal') }
        Mock Unregister-ScheduledTask { $script:trace.Add('remove-task') }
        Mock Test-BISFProtectedLocation {}
        Mock Remove-Item { $script:trace.Add('remove-state') }
        Mock Invoke-BISFLogCleanup { $script:trace.Add('clean-logs') }
        Mock Stop-Computer { $script:trace.Add('shutdown') }
    }
    It 'acknowledges the staged generation while the operator is loaded, before waiting or acquiring the lock' {
        (Invoke-BISFOperatorSealFinalizer $root (Join-Path $root 'GlobalConfig.xml')) | Should -Be 0
        ($script:trace -join ',') | Should -Be 'acknowledge,wait-for-unload,lock,delete-profile,verify-removal,remove-task,remove-state,clean-logs,shutdown,unlock'
        $script:written.WorkerReady.Generation | Should -Be $script:seal.Generation
        $script:written.WorkerReady.ProcessId | Should -BeGreaterThan 0
    }
    It 'does not wait, delete or shut down when publishing readiness fails' {
        Mock Write-BISFState { throw 'Acknowledgement could not be saved' }
        (Invoke-BISFOperatorSealFinalizer $root (Join-Path $root 'GlobalConfig.xml')) | Should -Be 2
        Should -Invoke Start-Sleep -Times 0
        Should -Invoke Remove-BISFCimUserProfile -Times 0
        Should -Invoke Stop-Computer -Times 0
    }
    It 'does not acknowledge if the master identity no longer matches' {
        Mock Get-BISFIdentity { [pscustomobject]@{Name='CLONE';MachineGuid='clone-guid';SmbiosUuid='clone-uuid'} }
        (Invoke-BISFOperatorSealFinalizer $root (Join-Path $root 'GlobalConfig.xml')) | Should -Be 2
        Should -Invoke Write-BISFState -Times 0
        Should -Invoke Stop-Computer -Times 0
    }
    It 'refuses readiness immediately if a reboot is pending' {
        Mock Get-BISFPendingRebootReasons { @('Windows Update RebootRequired') }
        (Invoke-BISFOperatorSealFinalizer $root (Join-Path $root 'GlobalConfig.xml')) | Should -Be 2
        Should -Invoke Write-BISFState -Times 0
        Should -Invoke Start-Sleep -Times 0
        Should -Invoke Stop-Computer -Times 0
    }
    It 'refuses readiness immediately if preparation has not committed' {
        Mock Get-BISFJournalStatus { [pscustomobject]@{PreparationPending=$true} }
        (Invoke-BISFOperatorSealFinalizer $root (Join-Path $root 'GlobalConfig.xml')) | Should -Be 2
        Should -Invoke Write-BISFState -Times 0
        Should -Invoke Start-Sleep -Times 0
        Should -Invoke Stop-Computer -Times 0
    }
    It 'does not acknowledge when another user profile remains loaded' {
        Mock Get-BISFLoadedNonSystemProfiles { [pscustomobject]@{SID='S-1-5-21-111-222-333-1002'} }
        Mock Start-Sleep { throw 'Should have refused before waiting' }
        (Invoke-BISFOperatorSealFinalizer $root (Join-Path $root 'GlobalConfig.xml')) | Should -Be 2
        Should -Invoke Write-BISFState -Times 0
        Should -Invoke Start-Sleep -Times 0
        Should -Invoke Stop-Computer -Times 0
    }
    It 'keeps preview free of acknowledgement, sign-out and shutdown side effects' {
        (Invoke-BISFOperatorSealFinalizer $root (Join-Path $root 'GlobalConfig.xml') -WhatIf) | Should -Be 0
        $script:trace.Count | Should -Be 0
        Should -Invoke Read-BISFOperatorSealState -Times 0
    }
}
