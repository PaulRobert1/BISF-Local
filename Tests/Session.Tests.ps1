BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    . "$root/Modules/Private/Profiles.ps1"
    . "$root/Modules/Private/Session.ps1"
}
Describe 'Verified operator interactive session' {
    BeforeEach {
        $script:operatorSid='S-1-5-21-111-222-333-1001'
        Mock Get-BISFNativeProcessSession {
            [pscustomobject]@{UserInteractive=$true;SessionId=3;SID=$script:operatorSid}
        }
        Mock Get-BISFNativeSessionOwner {
            [pscustomobject]@{SID=$script:operatorSid;ConnectionState=0}
        }
    }
    It 'returns the matching active desktop session and SID' {
        $session=Get-BISFOperatorSession -ExpectedSid $script:operatorSid
        $session.SessionId | Should -Be 3
        $session.SID | Should -Be $script:operatorSid
        Should -Invoke Get-BISFNativeSessionOwner -Times 1 -Exactly -ParameterFilter { $SessionId -eq 3 }
    }
    It 'refuses a noninteractive process' {
        Mock Get-BISFNativeProcessSession { [pscustomobject]@{UserInteractive=$false;SessionId=3;SID=$script:operatorSid} }
        { Get-BISFOperatorSession -ExpectedSid $script:operatorSid } | Should -Throw '*interactive*'
        Should -Invoke Get-BISFNativeSessionOwner -Times 0 -Exactly
    }
    It 'refuses service session zero' {
        Mock Get-BISFNativeProcessSession { [pscustomobject]@{UserInteractive=$true;SessionId=0;SID=$script:operatorSid} }
        { Get-BISFOperatorSession -ExpectedSid $script:operatorSid } | Should -Throw '*session*'
        Should -Invoke Get-BISFNativeSessionOwner -Times 0 -Exactly
    }
    It 'refuses a changed process token SID' {
        Mock Get-BISFNativeProcessSession { [pscustomobject]@{UserInteractive=$true;SessionId=3;SID='S-1-5-21-111-222-333-1002'} }
        { Get-BISFOperatorSession -ExpectedSid $script:operatorSid } | Should -Throw '*SID*'
    }
    It 'refuses alternate credentials belonging to a different desktop user' {
        Mock Get-BISFNativeSessionOwner { [pscustomobject]@{SID='S-1-5-21-111-222-333-1002';ConnectionState=0} }
        { Get-BISFOperatorSession -ExpectedSid $script:operatorSid } | Should -Throw '*session owner*'
    }
    It 'refuses a disconnected desktop session' {
        Mock Get-BISFNativeSessionOwner { [pscustomobject]@{SID=$script:operatorSid;ConnectionState=4} }
        { Get-BISFOperatorSession -ExpectedSid $script:operatorSid } | Should -Throw '*active*'
    }
    It 'does not guess the session owner after native query failure' {
        Mock Get-BISFNativeSessionOwner { throw 'WTS query denied' }
        { Get-BISFOperatorSession -ExpectedSid $script:operatorSid } | Should -Throw '*WTS query denied*'
    }
    It 'refuses an absent or ambiguous native session result' {
        Mock Get-BISFNativeSessionOwner { @() }
        { Get-BISFOperatorSession -ExpectedSid $script:operatorSid } | Should -Throw
        Mock Get-BISFNativeSessionOwner { @([pscustomobject]@{SID=$script:operatorSid;ConnectionState=0},[pscustomobject]@{SID=$script:operatorSid;ConnectionState=0}) }
        { Get-BISFOperatorSession -ExpectedSid $script:operatorSid } | Should -Throw
    }
}
Describe 'Normal operator sign-out request' {
    BeforeEach {
        $script:operatorSid='S-1-5-21-111-222-333-1001'
        Mock Get-BISFOperatorSession { [pscustomobject]@{SessionId=3;SID=$script:operatorSid} }
        Mock Invoke-BISFNativeOperatorSignOut {}
    }
    It 'revalidates the operator before requesting only normal sign-out' {
        Request-BISFOperatorSignOut -ExpectedSid $script:operatorSid -ExpectedSessionId 3
        Should -Invoke Get-BISFOperatorSession -Times 1 -Exactly -ParameterFilter { $ExpectedSid -eq $script:operatorSid }
        Should -Invoke Invoke-BISFNativeOperatorSignOut -Times 1 -Exactly
    }
    It 'refuses a changed session ID without requesting sign-out' {
        { Request-BISFOperatorSignOut -ExpectedSid $script:operatorSid -ExpectedSessionId 4 } | Should -Throw '*session*changed*'
        Should -Invoke Invoke-BISFNativeOperatorSignOut -Times 0 -Exactly
    }
    It 'never requests sign-out after failed revalidation' {
        Mock Get-BISFOperatorSession { throw 'Session owner changed' }
        { Request-BISFOperatorSignOut -ExpectedSid $script:operatorSid -ExpectedSessionId 3 } | Should -Throw '*Session owner changed*'
        Should -Invoke Invoke-BISFNativeOperatorSignOut -Times 0 -Exactly
    }
    It 'propagates native sign-out rejection rather than claiming success' {
        Mock Invoke-BISFNativeOperatorSignOut { throw 'Windows rejected normal sign-out: native error 5' }
        { Request-BISFOperatorSignOut -ExpectedSid $script:operatorSid -ExpectedSessionId 3 } | Should -Throw '*native error 5*'
    }
}
Describe 'Native session boundaries without Windows actions' {
    It 'compiles the Windows session interop declarations without calling them' {
        Initialize-BISFSessionNative
        ('BISF.Local.SessionNative' -as [type]) | Should -Not -BeNullOrEmpty
    }
    It 'exposes only a parameterless normal logoff action with no caller-selectable flags' {
        Initialize-BISFSessionNative
        $method=('BISF.Local.SessionNative' -as [type]).GetMethod('RequestNormalLogoff')
        $method | Should -Not -BeNullOrEmpty
        $method.GetParameters().Count | Should -Be 0
        $method.ReturnType.FullName | Should -Be 'System.Void'
    }
    It 'fixes native flags to normal logoff and a planned application maintenance reason' {
        $source=Get-Content "$root/Modules/Private/Session.ps1" -Raw
        # This exact native safety boundary must never acquire force, reboot or shutdown flags.
        $source | Should -Match 'ExitWindowsEx\(0,\s*0x80040001U\)'
    }
}
