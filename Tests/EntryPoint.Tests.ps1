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
