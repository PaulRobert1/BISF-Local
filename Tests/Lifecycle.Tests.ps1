BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Operations','Lifecycle') { if (Test-Path "$root/Modules/Private/$n.ps1") { . "$root/Modules/Private/$n.ps1" } }
    if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) { function Get-Acl { param($LiteralPath) } }
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { function Get-ScheduledTask { param($TaskPath) } }
}
Describe 'Clone identity and durable state' {
    BeforeEach {
        $master=[pscustomobject]@{Name='MASTER';MachineGuid='11111111-1111-1111-1111-111111111111';SmbiosUuid='22222222-2222-2222-2222-222222222222'}
        $clone=[pscustomobject]@{Name='CLONE1';MachineGuid=$master.MachineGuid;SmbiosUuid='33333333-3333-3333-3333-333333333333'}
    }
    It 'refuses the master and a renamed machine with unchanged identifiers' {
        { Test-BISFCloneIdentity $master $master } | Should -Throw
        $clone.SmbiosUuid=$master.SmbiosUuid
        { Test-BISFCloneIdentity $master $clone } | Should -Throw
    }
    It 'accepts changed name plus a changed valid identifier' {
        { Test-BISFCloneIdentity $master $clone } | Should -Not -Throw
    }
    It 'does not trust invalid or all-zero identifiers' {
        $clone.SmbiosUuid='00000000-0000-0000-0000-000000000000'
        { Test-BISFCloneIdentity $master $clone } | Should -Throw
    }
    It 'matches completion to the full clone identity and generation' {
        $s=[pscustomobject]@{Generation='g';Completion=[pscustomobject]@{Generation='g';Identity=$clone}}
        Test-BISFCompletion $s $clone | Should -BeTrue
        $s.Completion.Generation='old'
        Test-BISFCompletion $s $clone | Should -BeFalse
    }
    It 'rejects malformed state rather than treating it as first boot' {
        $p=Join-Path $TestDrive 'bad.json'
        '{"SchemaVersion":1}' | Set-Content $p
        { Read-BISFState $p } | Should -Throw
        '{broken' | Set-Content $p
        { Read-BISFState $p } | Should -Throw
    }
    It 'atomically replaces state and reads the new generation' {
        Mock Test-BISFProtectedLocation {}
        Mock Set-BISFPrivateAcl {}
        $p=Join-Path $TestDrive 'state/run.json'
        $s=New-BISFState $master ('a'*64) $true
        Write-BISFState $p $s
        $s.Generation=[guid]::NewGuid().ToString()
        $s.Status='Prepared'
        Write-BISFState $p $s
        (Read-BISFState $p).Generation | Should -Be $s.Generation
        @(Get-ChildItem (Split-Path $p) -Filter '*.tmp').Count | Should -Be 0
    }
    It 'locks applying runs and releases the lock' {
        $l=Enter-BISFLock
        try { $l.Acquired | Should -BeTrue } finally { Exit-BISFLock $l }
        $l2=Enter-BISFLock
        try { $l2.Acquired | Should -BeTrue } finally { Exit-BISFLock $l2 }
    }
}
Describe 'Protected locations and startup ownership' {
    It 'rejects remote task dependencies' {
        { Test-BISFProtectedLocation '\\server\share\package' } | Should -Throw '*local*'
    }
    It 'rejects untrusted write grants but accepts read-only grants' {
        $rule=[pscustomobject]@{Sid='S-1-5-32-545';Rights=2;Allow=$true;InheritOnly=$false}
        { Test-BISFAclRules 'S-1-5-18' @($rule) $false } | Should -Throw '*writable*'
        $rule.Rights=131209
        { Test-BISFAclRules 'S-1-5-18' @($rule) $false } | Should -Not -Throw
    }
    It 'rejects untrusted owners and ancestor deletion grants' {
        { Test-BISFAclRules 'S-1-5-21-123' @() $false } | Should -Throw '*owner*'
        $r=[pscustomobject]@{Sid='S-1-5-32-545';Rights=64;Allow=$true;InheritOnly=$false}
        { Test-BISFAclRules 'S-1-5-18' @($r) $true } | Should -Throw '*writable*'
    }
    It 'quotes host arguments without bypassing policy' {
        $a=Get-BISFTaskArguments 'C:\Program Files\BISF\Invoke-BISF.ps1' 'C:\Program Files\BISF\GlobalConfig.xml'
        $a | Should -Be '-NoProfile -NonInteractive -File "C:\Program Files\BISF\Invoke-BISF.ps1" -Mode Personalize -ConfigPath "C:\Program Files\BISF\GlobalConfig.xml"'
        { Get-BISFTaskArguments 'C:\bad"\script.ps1' 'C:\c.xml' } | Should -Throw
    }
    It 'rejects an unrelated task with the reserved name' {
        Mock Get-ScheduledTask { [pscustomobject]@{TaskName='BISF-Local-Personalize';Description='Someone else'} }
        { Test-BISFTaskOwnership 'C:\BISF' 'C:\BISF\GlobalConfig.xml' } | Should -Throw '*unrelated*'
    }
}
