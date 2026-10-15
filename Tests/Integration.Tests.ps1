BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Configuration','Logging','Preflight','Operations','Lifecycle','Citrix','Profiles','Maintenance','Finalization','Runner') { . "$root/Modules/Private/$n.ps1" }
    foreach ($n in 'Enter-BISFJournal','Clear-BISFJournal','Get-BISFJournalStatus') {
        if (-not (Get-Command $n -ErrorAction SilentlyContinue)) { Set-Item -Path ('Function:'+ $n) -Value {} }
    }
    if (-not (Get-Command Stop-Computer -ErrorAction SilentlyContinue)) { function Stop-Computer { [CmdletBinding(SupportsShouldProcess)]param() } }
    if (-not (Get-Command Start-Service -ErrorAction SilentlyContinue)) { function Start-Service { param($Name) } }
}
Describe 'Full workflow safety and results' {
    BeforeEach {
        $cfg=Join-Path $TestDrive ([guid]::NewGuid().ToString()+'.xml')
        (Get-Content "$root/GlobalConfig.xml" -Raw).Replace('<Enabled>true</Enabled>','<Enabled>false</Enabled>') | Set-Content $cfg
        $script:trace=New-Object 'System.Collections.Generic.List[string]'
        $script:pending=$false; $script:lastCompletion=$null
        Mock Enter-BISFJournal { $script:pending=$true; 'journal' }
        Mock Clear-BISFJournal { $script:pending=$false }
        Mock Get-BISFJournalStatus { [pscustomobject]@{PreparationPending=$false;PersonalizationPending=$false} }
        $master=[pscustomobject]@{Name='MASTER';MachineGuid='11111111-1111-1111-1111-111111111111';SmbiosUuid='22222222-2222-2222-2222-222222222222'}
        $clone=[pscustomobject]@{Name='CLONE';MachineGuid=$master.MachineGuid;SmbiosUuid='33333333-3333-3333-3333-333333333333'}
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$master;CMInstalled=$true} }
        Mock Test-BISFPreflight {}
        Mock Get-BISFPendingRebootReasons { @() }
        Mock Get-BISFCitrixReadiness { [pscustomobject]@{VDA=$null;WEM=$null} }
        Mock Test-BISFProtectedLocation {}
        Mock Write-BISFState { $script:trace.Add('state:'+$State.Status) }
        Mock Register-BISFStartupTask { $script:trace.Add('task') }
        Mock Invoke-BISFCMPrepare { $script:trace.Add('prepare'); 'Running' }
        Mock Invoke-BISFCMCloneReset { $script:trace.Add('reset') }
        Mock Restore-BISFCMService { $script:trace.Add('restore') }
        Mock Start-Service { $script:trace.Add('start') }
        Mock Wait-BISFService {}
        Mock Stop-Computer { $script:trace.Add('shutdown') }
    }
    It 'validates without image mutations or log creation when disabled' {
        $r=Invoke-BISFLocal -ConfigPath $cfg -ScriptRoot $root
        $r.ExitCode | Should -Be 0
        $script:trace.Count | Should -Be 0
        Test-Path (Join-Path $root 'logs') | Should -BeFalse
    }
    It 'previews selected operations without mutations' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true').Replace('<FinalAction>None','<FinalAction>Shutdown') | Set-Content $cfg
        $r=Invoke-BISFLocal $cfg $root Prepare -WhatIf
        $r.ExitCode | Should -Be 0
        $r.Results.Status | Should -Contain 'Preview'
        $script:trace.Count | Should -Be 0
    }
    It 'shows eligible user profiles in Validate and WhatIf without deleting anything' {
        (Get-Content $cfg -Raw).Replace('<UserProfiles>false','<UserProfiles>true') | Set-Content $cfg
        Mock Get-BISFUserProfilePlan { [pscustomobject]@{
            Root='C:\Users'
            CurrentSid='S-1-5-21-111-222-333-1002'
            ExcludedSIDs=@()
            Entries=@([pscustomobject]@{SID='S-1-5-21-111-222-333-1001';LocalPath='C:\Users\test';Status='Remove';Reason='Inactive'})
        } }
        Mock Invoke-BISFUserProfileCleanup { throw 'Should not delete anything in preview modes' }
        (Invoke-BISFLocal $cfg $root Validate).ExitCode | Should -Be 0
        (Invoke-BISFLocal $cfg $root Prepare -WhatIf).ExitCode | Should -Be 0
        Should -Invoke Invoke-BISFUserProfileCleanup -Times 0
    }
    It 'refuses destructive preparation if a non-admin profile is still loaded' {
        (Get-Content $cfg -Raw).Replace('<UserProfiles>false','<UserProfiles>true') | Set-Content $cfg
        Mock Get-BISFUserProfilePlan { [pscustomobject]@{
            Root='C:\Users'
            CurrentSid='S-1-5-21-111-222-333-1002'
            ExcludedSIDs=@()
            Entries=@([pscustomobject]@{SID='S-1-5-21-111-222-333-1001';LocalPath='C:\Users\test';Status='Blocked';Reason='Profile still loaded'})
        } }
        Mock Invoke-BISFUserProfileCleanup { throw 'Should not delete a loaded profile' }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 1
        $r.Error | Should -Match 'non-exempt profiles are loaded'
        Should -Invoke Invoke-BISFUserProfileCleanup -Times 0
        $script:trace.Count | Should -Be 0
    }
    It 'invokes native profile cleanup only during applying Prepare' {
        (Get-Content $cfg -Raw).Replace('<UserProfiles>false','<UserProfiles>true') | Set-Content $cfg
        Mock Get-BISFUserProfilePlan { [pscustomobject]@{
            Root='C:\Users'
            CurrentSid='S-1-5-21-111-222-333-1002'
            ExcludedSIDs=@()
            Entries=@([pscustomobject]@{SID='S-1-5-21-111-222-333-1001';LocalPath='C:\Users\test';Status='Remove';Reason='Inactive'})
        } }
        Mock Invoke-BISFUserProfileCleanup { $script:trace.Add('profiles') }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 0
        ($script:trace -join ',') | Should -Be 'profiles'
        Should -Invoke Invoke-BISFUserProfileCleanup -Times 1
    }
    It 'stages SYS operator profile cleanup without immediate shutdown or forced logoff' {
        [xml]$xml=Get-Content $cfg -Raw
        $xml.BISF.Cleanup.UserProfiles='true'
        $xml.BISF.Finalization.RemoveOperatorProfile='true'
        $xml.BISF.FinalAction='Shutdown'
        $xml.Save($cfg)
        Mock Get-BISFOperatorSealTarget { [pscustomobject]@{SID='S-1-5-21-111-222-333-1001';Path='C:\Users\Operator';Root='C:\Users'} }
        Mock Get-BISFUserProfilePlan { [pscustomobject]@{
            Root='C:\Users'
            CurrentSid='S-1-5-21-111-222-333-1001'
            ExcludedSIDs=@()
            Entries=@([pscustomobject]@{SID='S-1-5-21-111-222-333-1001';LocalPath='C:\Users\Operator';Status='Protected';Reason='Current user'})
        } }
        Mock Invoke-BISFUserProfileCleanup { $script:trace.Add('other-profiles') }
        Mock Register-BISFOperatorSeal { $script:trace.Add('stage') }
        Mock Stop-Computer { throw 'Must not shut down before administrator signs out' }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 0
        ($script:trace -join ',') | Should -Be 'other-profiles,stage'
        $r.Results.Status | Should -Contain 'Staged'
        Should -Invoke Stop-Computer -Times 0
    }
    It 'keeps operator finalizer and servicing read-only in Validate/WhatIf' {
        [xml]$xml=Get-Content $cfg -Raw
        $xml.BISF.Cleanup.UserProfiles='true'
        $xml.BISF.Finalization.RemoveOperatorProfile='true'
        $xml.BISF.FinalAction='Shutdown'
        $xml.BISF.Servicing.ComponentCleanup='true'
        $xml.Save($cfg)
        Mock Get-BISFOperatorSealTarget { [pscustomobject]@{SID='S-1-5-21-111-222-333-1001';Path='C:\Users\Operator';Root='C:\Users'} }
        Mock Get-BISFUserProfilePlan { [pscustomobject]@{Root='C:\Users';CurrentSid='S-1-5-21-111-222-333-1001';ExcludedSIDs=@();Entries=@()} }
        Mock Invoke-BISFComponentCleanup { throw 'Must not run servicing in previews' }
        Mock Register-BISFOperatorSeal { throw 'Must not stage SYSTEM worker in previews' }
        (Invoke-BISFLocal $cfg $root Validate).ExitCode | Should -Be 0
        (Invoke-BISFLocal $cfg $root Prepare -WhatIf).ExitCode | Should -Be 0
        Should -Invoke Invoke-BISFComponentCleanup -Times 0
        Should -Invoke Register-BISFOperatorSeal -Times 0
        $script:trace.Count | Should -Be 0
    }
    It 'stops later profile deletion if Windows servicing fails' {
        [xml]$xml=Get-Content $cfg -Raw
        $xml.BISF.Servicing.ComponentCleanup='true'
        $xml.BISF.Cleanup.UserProfiles='true'
        $xml.Save($cfg)
        Mock Get-BISFUserProfilePlan { [pscustomobject]@{Root='C:\Users';CurrentSid='S-1-5-21-111-222-333-1001';ExcludedSIDs=@();Entries=@()} }
        Mock Invoke-BISFComponentCleanup { throw 'servicing failure' }
        Mock Invoke-BISFUserProfileCleanup { throw 'Should not delete profiles after servicing fails' }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 2
        Should -Invoke Invoke-BISFUserProfileCleanup -Times 0
    }
    It 'preflight failure prevents every requested mutation' {
        Mock Test-BISFPreflight { throw 'missing prerequisite' }
        $r=Invoke-BISFLocal $cfg $root Prepare
        $r.ExitCode | Should -Be 1
        $script:trace.Count | Should -Be 0
    }
    It 'stops after failed preparation without successful state or shutdown' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true').Replace('<FinalAction>None','<FinalAction>Shutdown') | Set-Content $cfg
        Mock Invoke-BISFCMPrepare { throw 'reset failure' }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 2
        $script:trace | Should -Not -Contain 'shutdown'
        $script:trace | Should -Not -Contain 'state:Prepared'
        $script:trace | Should -Contain 'state:Failed'
    }
    It 'commits a successful generation before requesting shutdown' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true').Replace('<FinalAction>None','<FinalAction>Shutdown') | Set-Content $cfg
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 0
        ($script:trace -join ',') | Should -Be 'state:Preparing,prepare,state:Prepared,shutdown'
    }
    It 'restores the service and invalidates state if shutdown fails' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true').Replace('<FinalAction>None','<FinalAction>Shutdown') | Set-Content $cfg
        Mock Stop-Computer { throw 'shutdown denied' }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 2
        $script:trace | Should -Contain 'restore'
        $script:trace | Should -Contain 'state:Failed'
    }
    It 'refuses personalization on the master before any mutation' {
        Mock Read-BISFState { New-BISFState $master ((Get-FileHash $cfg).Hash) $false }
        $r=Invoke-BISFLocal $cfg $root Personalize
        $r.ExitCode | Should -Be 1
        $script:trace.Count | Should -Be 0
    }
    It 'skips a completed clone' {
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState {
            $s=New-BISFState $master ((Get-FileHash $cfg).Hash) $false
            $s.Status='Prepared'; $s.Completion=[pscustomobject]@{Generation=$s.Generation;Identity=$clone}; $s
        }
        $r=Invoke-BISFLocal $cfg $root Personalize
        $r.ExitCode | Should -Be 0
        $r.Results.Status | Should -Contain 'Skipped'
        $script:trace.Count | Should -Be 0
    }
    It 'resets before starting the client then records completion' {
        (Get-Content $cfg -Raw).Replace('<CloneTrustedRootKeyReset>false','<CloneTrustedRootKeyReset>true') | Set-Content $cfg
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState { $s=New-BISFState $master ((Get-FileHash $cfg).Hash) $false; $s.Status='Prepared'; $s }
        $r=Invoke-BISFLocal $cfg $root Personalize -Confirm:$false
        $r.ExitCode | Should -Be 0
        ($script:trace -join ',') | Should -Be 'reset,start,state:Prepared'
    }
    It 'cannot personalize with changed configuration' {
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState { $s=New-BISFState $master ('0'*64) $false; $s.Status='Prepared'; $s }
        $r=Invoke-BISFLocal $cfg $root Personalize
        $r.ExitCode | Should -Be 1
        $script:trace.Count | Should -Be 0
    }
    It 'does not apply if logging initialization fails' {
        Mock New-BISFLogger { throw 'log denied' }
        $r=Invoke-BISFLocal $cfg $root Prepare
        $r.ExitCode | Should -Be 1
        $script:trace.Count | Should -Be 0
    }
    It 'reports a log write failure without recursive errors or shutdown' {
        Mock Write-BISFLog { throw 'log device lost' }
        $r=Invoke-BISFLocal $cfg $root Prepare
        $r.ExitCode | Should -Be 1
        $r.Error | Should -Match 'log device lost'
        $script:trace.Count | Should -Be 0
    }
    It 'declining any operation prevents the entire plan and shutdown' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true').Replace('<FinalAction>None','<FinalAction>Shutdown') | Set-Content $cfg
        Mock Confirm-BISFOperation { $false }
        $r=Invoke-BISFLocal $cfg $root Prepare
        $r.ExitCode | Should -Be 2
        $r.Results.Status | Should -Contain 'Skipped'
        $script:trace.Count | Should -Be 0
    }
    It 'task registration failure invalidates state and restores the client' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true').Replace('<Personalization>','<Personalization>').Replace('<Enabled>false</Enabled>','<Enabled>true</Enabled>') | Set-Content $cfg
        Mock New-BISFLogger { [pscustomobject]@{Enabled=$false;LogFile=$null} }
        Mock Register-BISFStartupTask { throw 'task registration failed' }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 2
        $script:trace | Should -Contain 'restore'
        $script:trace | Should -Contain 'state:Failed'
        $script:trace | Should -Not -Contain 'state:Prepared'
    }
    It 'a late log failure suppresses shutdown and invalidates preparation' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true').Replace('<FinalAction>None','<FinalAction>Shutdown') | Set-Content $cfg
        Mock Write-BISFLog { if ($Operation -eq 'Lifecycle' -and $Message -eq 'Ready for state commit.') { throw 'late log failure' } }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 2
        $script:trace | Should -Not -Contain 'shutdown'
        $script:trace | Should -Contain 'state:Failed'
    }
    It 'previews personalization without reset or completion writes' {
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState { $s=New-BISFState $master ((Get-FileHash $cfg).Hash) $false; $s.Status='Prepared'; $s }
        $r=Invoke-BISFLocal $cfg $root Personalize -WhatIf
        $r.ExitCode | Should -Be 0
        $script:trace.Count | Should -Be 0
    }
    It 'a failed clone reset never starts the client or records completion' {
        (Get-Content $cfg -Raw).Replace('<CloneTrustedRootKeyReset>false','<CloneTrustedRootKeyReset>true') | Set-Content $cfg
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState { $s=New-BISFState $master ((Get-FileHash $cfg).Hash) $false; $s.Status='Prepared'; $s }
        Mock Invoke-BISFCMCloneReset { throw 'CIM failed' }
        $r=Invoke-BISFLocal $cfg $root Personalize -Confirm:$false
        $r.ExitCode | Should -Be 2
        $script:trace.Count | Should -Be 0
    }
    It 'does not leave completion recorded when logging fails after completion' {
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState { $s=New-BISFState $master ((Get-FileHash $cfg).Hash) $false; $s.Status='Prepared'; $s }
        Mock Write-BISFState { $script:lastCompletion=$State.Completion }
        Mock Write-BISFLog { if ($Operation -eq 'Complete' -and $Message -eq 'Ready for state commit.') { throw 'log lost' } }
        $r=Invoke-BISFLocal $cfg $root Personalize -Confirm:$false
        $r.ExitCode | Should -Be 2
        $script:lastCompletion | Should -BeNullOrEmpty
    }
    It 'rejects an unsafe lifecycle state file before clone actions' {
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState { $s=New-BISFState $master ((Get-FileHash $cfg).Hash) $false; $s.Status='Prepared'; $s }
        Mock Test-BISFProtectedLocation { if ($Path -like '*lifecycle.json') { throw 'state writable by nonadmin' } }
        $r=Invoke-BISFLocal $cfg $root Personalize -Confirm:$false
        $r.ExitCode | Should -Be 1
        $script:trace.Count | Should -Be 0
    }
    It 'performs no fallible log writes after requesting shutdown' {
        (Get-Content $cfg -Raw).Replace('<FinalAction>None','<FinalAction>Shutdown') | Set-Content $cfg
        Mock Write-BISFLog { if ($script:trace -contains 'shutdown') { throw 'too late to abort' } }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 0
        ($script:trace -join ',') | Should -Be 'shutdown'
    }
    It 'retains a pending guard if shutdown and state invalidation both fail' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true').Replace('<FinalAction>None','<FinalAction>Shutdown') | Set-Content $cfg
        Mock Stop-Computer { throw 'power request failed' }
        Mock Write-BISFState { if ($State.Status -eq 'Failed') { throw 'disk inaccessible' } }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 2
        $script:pending | Should -BeTrue
    }
    It 'blocks clones captured with an incomplete preparation journal' {
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState { $s=New-BISFState $master ((Get-FileHash $cfg).Hash) $false; $s.Status='Prepared'; $s }
        Mock Get-BISFJournalStatus { [pscustomobject]@{PreparationPending=$true;PersonalizationPending=$false} }
        $r=Invoke-BISFLocal $cfg $root Personalize -Confirm:$false
        $r.ExitCode | Should -Be 1
        $script:trace.Count | Should -Be 0
    }
    It 'a failed final journal clear leaves clone blocked without restoring services after shutdown' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true').Replace('<FinalAction>None','<FinalAction>Shutdown') | Set-Content $cfg
        Mock Clear-BISFJournal { throw 'cannot clear journal' }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 2
        $script:pending | Should -BeTrue
        $script:trace | Should -Contain 'shutdown'
        $script:trace | Should -Not -Contain 'restore'
    }
    It 'retries a clone whose completion write succeeded but journal clear failed previously' {
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState {
            $s=New-BISFState $master ((Get-FileHash $cfg).Hash) $false
            $s.Status='Prepared'; $s.Completion=[pscustomobject]@{Generation=$s.Generation;Identity=$clone}; $s
        }
        Mock Get-BISFJournalStatus { [pscustomobject]@{PreparationPending=$false;PersonalizationPending=$true} }
        $r=Invoke-BISFLocal $cfg $root Personalize -Confirm:$false
        $r.ExitCode | Should -Be 0
        $script:trace | Should -Contain 'state:Prepared'
        $script:pending | Should -BeFalse
    }
    It 'does not report completion when the durable state commit fails' {
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$clone;CMInstalled=$true} }
        Mock Read-BISFState { $s=New-BISFState $master ((Get-FileHash $cfg).Hash) $false; $s.Status='Prepared'; $s }
        Mock Write-BISFState { if ($null -ne $State.Completion) { throw 'state write failed' } }
        $r=Invoke-BISFLocal $cfg $root Personalize -Confirm:$false
        $r.ExitCode | Should -Be 2
        @($r.Results | Where-Object { $_.Id -eq 'Complete' -and $_.Status -eq 'Completed' }).Count | Should -Be 0
    }
    It 'rejects concurrent apply lock acquisition before mutation' {
        Mock Enter-BISFLock { throw 'Another run active' }
        $r=Invoke-BISFLocal $cfg $root Prepare
        $r.ExitCode | Should -Be 1
        $script:trace.Count | Should -Be 0
    }
}

Describe 'Citrix final shutdown boundary' {
    BeforeEach {
        $cfg=Join-Path $TestDrive ([guid]::NewGuid().ToString()+'.xml')
        [xml]$xml=Get-Content "$root/GlobalConfig.xml" -Raw
        $xml.BISF.Logging.Enabled='false'
        $xml.BISF.Citrix.VDA.StopBeforeShutdown='true'
        $xml.BISF.FinalAction='Shutdown'
        $xml.Save($cfg)
        $script:trace=New-Object 'System.Collections.Generic.List[string]'
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test';Build=26100;Identity=[pscustomobject]@{Name='MASTER'};CMInstalled=$false} }
        Mock Test-BISFPreflight {}
        Mock Get-BISFCitrixReadiness { [pscustomobject]@{VDA=$null;WEM=[pscustomobject]@{Version='2507';CachePath="$TestDrive/cache";CacheExists=$true}} }
        Mock Get-BISFVDARunningState { 'Running' }
        Mock Stop-BISFVDA { $script:trace.Add('vda-stop') }
        Mock Restore-BISFVDA { $script:trace.Add('vda-restore:'+$PreviousState) }
        Mock Stop-Computer { $script:trace.Add('shutdown') }
        Mock Write-BISFLog { if ($script:trace -contains 'vda-stop') { $script:trace.Add('late-log') } }
    }
    It 'warns on absent WEM cache in Validate without stopping a service or requesting shutdown' {
        Mock Get-BISFCitrixReadiness {
            [pscustomobject]@{
                VDA=$null
                WEM=[pscustomobject]@{
                    Version='2507';CachePath="$TestDrive/cache";CacheExists=$false
                    CacheStatus='DirectoryMissing';HostState='Running'
                    LocalAgentCachePresent=$false;LocalAgentDatabasePresent=$false
                }
            }
        }
        $script:observedLogs=New-Object 'System.Collections.Generic.List[string]'
        Mock Write-BISFLog { $script:observedLogs.Add("$Level|$Operation|$Message") }
        $r=Invoke-BISFLocal $cfg $root Validate
        $r.ExitCode | Should -Be 0
        ($script:observedLogs -join [Environment]::NewLine) | Should -Match 'Warning\|CitrixWEM\|.*cacheStatus=DirectoryMissing'
        $script:trace.Count | Should -Be 0
        Should -Invoke Stop-BISFVDA -Times 0
        Should -Invoke Stop-Computer -Times 0
    }
    It 'does not stop or shut down in Validate or WhatIf' {
        (Invoke-BISFLocal $cfg $root Validate).ExitCode | Should -Be 0
        (Invoke-BISFLocal $cfg $root Prepare -WhatIf).ExitCode | Should -Be 0
        $script:trace.Count | Should -Be 0
    }
    It 'stops immediately before power with no intervening log writes' {
        (Invoke-BISFLocal $cfg $root Prepare -Confirm:$false).ExitCode | Should -Be 0
        ($script:trace -join ',') | Should -Be 'vda-stop,shutdown'
        Should -Invoke Restore-BISFVDA -Times 0
    }
    It 'restores a running VDA after a failed shutdown request' {
        Mock Stop-Computer { throw 'power denied' }
        $r=Invoke-BISFLocal $cfg $root Prepare -Confirm:$false
        $r.ExitCode | Should -Be 2
        $r.Error | Should -Be 'power denied'
        $script:trace | Should -Contain 'vda-restore:Running'
    }
    It 'attempts recovery even when service stop partially fails' {
        Mock Stop-BISFVDA { throw 'stop timed out' }
        (Invoke-BISFLocal $cfg $root Prepare -Confirm:$false).ExitCode | Should -Be 2
        $script:trace | Should -Contain 'vda-restore:Running'
        Should -Invoke Stop-Computer -Times 0
    }
    It 'preserves originally stopped state on recovery' {
        Mock Get-BISFVDARunningState { 'Stopped' }
        Mock Stop-Computer { throw 'power denied' }
        (Invoke-BISFLocal $cfg $root Prepare -Confirm:$false).ExitCode | Should -Be 2
        $script:trace | Should -Contain 'vda-restore:Stopped'
    }
    It 'does not stop the VDA if earlier cleanup fails' {
        (Get-Content $cfg -Raw).Replace('<WindowsTemp>false','<WindowsTemp>true') | Set-Content $cfg
        Mock Get-BISFTempRoots { [pscustomobject]@{WindowsTemp="$TestDrive/temp"} }
        Mock Get-BISFCleanupCandidates { throw 'cleanup failed' }
        (Invoke-BISFLocal $cfg $root Prepare -Confirm:$false).ExitCode | Should -Be 2
        Should -Invoke Stop-BISFVDA -Times 0
        Should -Invoke Stop-Computer -Times 0
    }
    It 'protects the detected WEM cache from temp cleanup' {
        (Get-Content $cfg -Raw).Replace('<WindowsTemp>false','<WindowsTemp>true') | Set-Content $cfg
        Mock Get-BISFTempRoots { [pscustomobject]@{WindowsTemp="$TestDrive/temp"} }
        Mock Get-BISFCleanupCandidates {}
        Mock Remove-BISFTempFiles {}
        (Invoke-BISFLocal $cfg $root Prepare -Confirm:$false).ExitCode | Should -Be 0
        Should -Invoke Get-BISFCleanupCandidates -Times 1 -ParameterFilter { $ProtectedPaths -contains "$TestDrive/cache" }
    }
    It 'does not restore after accepted shutdown even if journal finalization fails' {
        (Get-Content $cfg -Raw).Replace('<PrepareIdentityReset>false','<PrepareIdentityReset>true') | Set-Content $cfg
        Mock Enter-BISFJournal { 'journal' }
        Mock Clear-BISFJournal { throw 'journal failure' }
        Mock Write-BISFState {}
        Mock Invoke-BISFCMPrepare { 'Stopped' }
        Mock Restore-BISFCMService {}
        (Invoke-BISFLocal $cfg $root Prepare -Confirm:$false).ExitCode | Should -Be 2
        Should -Invoke Restore-BISFVDA -Times 0
        Should -Invoke Restore-BISFCMService -Times 0
    }
}
