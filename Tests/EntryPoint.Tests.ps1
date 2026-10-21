BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $hostExecutable=(Get-Process -Id $PID).Path
    function Invoke-TestEntryPoint {
        param([string]$Package,[string[]]$Arguments=@())
        $output=& $hostExecutable -NoLogo -NoProfile -NonInteractive -File (Join-Path $Package 'Invoke-BISF.ps1') @Arguments 2>&1 | Out-String
        [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=$output}
    }
}
Describe 'Normal launch initializes permissions before loading the preparation runtime' {
    BeforeEach {
        $package=Join-Path $TestDrive ('package with spaces '+[guid]::NewGuid().ToString('N'))
        $null=New-Item -ItemType Directory -Path (Join-Path $package 'Modules') -Force
        Copy-Item -LiteralPath (Join-Path $root 'Invoke-BISF.ps1') -Destination $package
        '<test/>' | Set-Content (Join-Path $package 'GlobalConfig.xml')
        @'
Write-Host 'INSTALL_IMPORT'
function Initialize-BISFInstallation {
    param($ScriptRoot,$ConfigPath)
    if (-not [IO.Path]::IsPathRooted($ScriptRoot) -or -not [IO.File]::Exists($ConfigPath)) { throw 'Invalid installation paths' }
    if (Test-Path (Join-Path $ScriptRoot 'fail-install')) { throw 'Installation permission setup failed' }
    Write-Host 'INSTALL_COMPLETE'
}
Export-ModuleMember -Function Initialize-BISFInstallation
'@ | Set-Content (Join-Path $package 'Modules/BISF.Installation.psm1')
        @'
Write-Host 'RUNTIME_IMPORT'
function Invoke-BISFLocal {
    param($ConfigPath,$ScriptRoot,$Mode,$WhatIf,$Confirm)
    Write-Host ('RUN:'+ $Mode)
    [pscustomobject]@{ExitCode=37}
}
function Invoke-BISFOperatorSealFinalizer { param($ScriptRoot,$ConfigPath,$WhatIf,$Confirm) Write-Host 'FINALIZE'; 37 }
function Invoke-BISFCloneVerification { param($ScriptRoot,$ConfigPath) Write-Host 'VERIFY' }
Export-ModuleMember -Function Invoke-BISFLocal,Invoke-BISFOperatorSealFinalizer,Invoke-BISFCloneVerification
'@ | Set-Content (Join-Path $package 'Modules/BISF.Local.psm1')
    }
    It 'runs package initialization automatically and then Prepare with no arguments' {
        $r=Invoke-TestEntryPoint $package
        $r.ExitCode | Should -Be 37
        $r.Output | Should -Match '(?s)INSTALL_IMPORT.*INSTALL_COMPLETE.*RUNTIME_IMPORT.*RUN:Prepare'
    }
    It 'does not load the preparation runtime if installation setup fails' {
        '' | Set-Content (Join-Path $package 'fail-install')
        $r=Invoke-TestEntryPoint $package
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'Installation permission setup failed'
        $r.Output | Should -Not -Match 'RUNTIME_IMPORT'
    }
    It 'does not initialize permissions for <Label>' -ForEach @(
        @{Label='Validate';Arguments=@('-Mode','Validate');WantCode=37;WantOutput='RUN:Validate'},
        @{Label='WhatIf';Arguments=@('-Mode','Prepare','-WhatIf');WantCode=37;WantOutput='RUN:Prepare'},
        @{Label='Personalize';Arguments=@('-Mode','Personalize');WantCode=37;WantOutput='RUN:Personalize'},
        @{Label='Finalize';Arguments=@('-Mode','Finalize');WantCode=37;WantOutput='FINALIZE'},
        @{Label='VerifyClone';Arguments=@('-Mode','VerifyClone');WantCode=0;WantOutput='VERIFY'}
    ) {
        $r=Invoke-TestEntryPoint -Package $package -Arguments $Arguments
        $r.ExitCode | Should -Be $WantCode
        $r.Output | Should -Match $WantOutput
        $r.Output | Should -Not -Match 'INSTALL_IMPORT|INSTALL_COMPLETE'
    }
}
Describe 'Automatic operator sign-out only after successful preparation returns' {
    BeforeEach {
        $package=Join-Path $TestDrive ('automatic-signout-'+[guid]::NewGuid().ToString('N'))
        $null=New-Item -ItemType Directory -Path (Join-Path $package 'Modules') -Force
        Copy-Item -LiteralPath (Join-Path $root 'Invoke-BISF.ps1') -Destination $package
        '<test/>' | Set-Content (Join-Path $package 'GlobalConfig.xml')
        @'
function Initialize-BISFInstallation { param($ScriptRoot,$ConfigPath) }
Export-ModuleMember -Function Initialize-BISFInstallation
'@ | Set-Content (Join-Path $package 'Modules/BISF.Installation.psm1')
        @'
function Invoke-BISFLocal {
    param($ConfigPath,$ScriptRoot,$Mode,$WhatIf,$Confirm)
    Write-Host 'RUNNER_ENTER'
    try {
        $r=[pscustomobject]@{ExitCode=0;OperatorSignOut=[pscustomobject]@{Generation='11111111-2222-3333-4444-555555555555';SID='S-1-5-21-111-222-333-1001';SessionId=3;WorkerProcessId=4321;WorkerStartedUtc='2026-10-21T12:00:00.0000000Z'}}
        if (Test-Path (Join-Path $ScriptRoot 'failed')) { $r.ExitCode=2 }
        if (Test-Path (Join-Path $ScriptRoot 'missing-context')) { $r.PSObject.Properties.Remove('OperatorSignOut') }
        if (Test-Path (Join-Path $ScriptRoot 'null-context')) { $r.OperatorSignOut=$null }
        return $r
    } finally { Write-Host 'RUNNER_RELEASED_LOCK' }
}
function Invoke-BISFOperatorSignOut {
    param($ScriptRoot,$ConfigPath,$Context)
    if ($ScriptRoot -ne (Split-Path -Parent $PSScriptRoot) -or $ConfigPath -ne (Join-Path $ScriptRoot 'GlobalConfig.xml')) { throw 'Incorrect package/config routing' }
    if ($Context.Generation -ne '11111111-2222-3333-4444-555555555555' -or $Context.SID -ne 'S-1-5-21-111-222-333-1001' -or $Context.SessionId -ne 3 -or $Context.WorkerProcessId -ne 4321 -or $Context.WorkerStartedUtc -ne '2026-10-21T12:00:00.0000000Z') { throw 'Incorrect sign-out context' }
    Write-Host 'SIGNOUT_REQUEST'
    if (Test-Path (Join-Path $ScriptRoot 'fail-signout')) { throw 'Native sign-out request denied' }
}
Export-ModuleMember -Function Invoke-BISFLocal,Invoke-BISFOperatorSignOut
'@ | Set-Content (Join-Path $package 'Modules/BISF.Local.psm1')
    }
    It 'requests sign-out exactly once after the successful runner releases its lock' {
        $r=Invoke-TestEntryPoint $package
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match '(?s)RUNNER_ENTER.*RUNNER_RELEASED_LOCK.*SIGNOUT_REQUEST'
        ([regex]::Matches($r.Output,'SIGNOUT_REQUEST')).Count | Should -Be 1
    }
    It 'does not request sign-out for <Label>' -ForEach @(
        @{Label='failed preparation';Marker='failed';Arguments=@();WantCode=2},
        @{Label='Validate';Marker='';Arguments=@('-Mode','Validate');WantCode=0},
        @{Label='WhatIf';Marker='';Arguments=@('-Mode','Prepare','-WhatIf');WantCode=0},
        @{Label='Personalize';Marker='';Arguments=@('-Mode','Personalize');WantCode=0},
        @{Label='missing context';Marker='missing-context';Arguments=@();WantCode=0},
        @{Label='null context';Marker='null-context';Arguments=@();WantCode=0}
    ) {
        if ($Marker) { '' | Set-Content (Join-Path $package $Marker) }
        $r=Invoke-TestEntryPoint -Package $package -Arguments $Arguments
        $r.ExitCode | Should -Be $WantCode
        $r.Output | Should -Not -Match 'SIGNOUT_REQUEST'
    }
    It 'reports preparation complete and finalization pending when sign-out fails' {
        '' | Set-Content (Join-Path $package 'fail-signout')
        $r=Invoke-TestEntryPoint $package
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'Preparation completed'
        $r.Output | Should -Match 'finalization remains pending'
        $r.Output | Should -Match 'Native sign-out request denied'
        ([regex]::Matches($r.Output,'SIGNOUT_REQUEST')).Count | Should -Be 1
    }
}
