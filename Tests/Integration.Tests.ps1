BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Configuration','Logging','Preflight','Operations','Lifecycle','Runner') { . "$root/Modules/Private/$n.ps1" }
    if (-not (Get-Command Stop-Computer -ErrorAction SilentlyContinue)) { function Stop-Computer { [CmdletBinding(SupportsShouldProcess)]param() } }
    if (-not (Get-Command Start-Service -ErrorAction SilentlyContinue)) { function Start-Service { param($Name) } }
}
Describe 'Full workflow safety and results' {
    BeforeEach {
        $cfg=Join-Path $TestDrive ([guid]::NewGuid().ToString()+'.xml')
        (Get-Content "$root/GlobalConfig.xml" -Raw).Replace('<Enabled>true</Enabled>','<Enabled>false</Enabled>') | Set-Content $cfg
        $script:trace=New-Object 'System.Collections.Generic.List[string]'
        $master=[pscustomobject]@{Name='MASTER';MachineGuid='11111111-1111-1111-1111-111111111111';SmbiosUuid='22222222-2222-2222-2222-222222222222'}
        $clone=[pscustomobject]@{Name='CLONE';MachineGuid=$master.MachineGuid;SmbiosUuid='33333333-3333-3333-3333-333333333333'}
        Mock Get-BISFInventory { [pscustomobject]@{Caption='Test Windows';Build=26100;Identity=$master;CMInstalled=$true} }
        Mock Test-BISFPreflight {}
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
        Mock Write-BISFLog { if ($Operation -eq 'Lifecycle' -and $Message -eq 'Completed.') { throw 'late log failure' } }
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
        Mock Write-BISFLog { if ($Operation -eq 'Complete' -and $Message -eq 'Completed.') { throw 'log lost' } }
        $r=Invoke-BISFLocal $cfg $root Personalize -Confirm:$false
        $r.ExitCode | Should -Be 2
        $script:lastCompletion | Should -BeNullOrEmpty
    }
    It 'rejects concurrent apply lock acquisition before mutation' {
        Mock Enter-BISFLock { throw 'Another run active' }
        $r=Invoke-BISFLocal $cfg $root Prepare
        $r.ExitCode | Should -Be 1
        $script:trace.Count | Should -Be 0
    }
}
