BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path $PSScriptRoot -Parent
    foreach ($name in 'Preflight','Operations') {
        if (Test-Path "$root/Modules/Private/$name.ps1") { . "$root/Modules/Private/$name.ps1" }
    }
    # Windows-only boundaries; real operations are mocked below on Linux.
    if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) { function Get-Service { param($Name) } }
    if (-not (Get-Command Stop-Service -ErrorAction SilentlyContinue)) { function Stop-Service { param($Name) } }
    if (-not (Get-Command Start-Service -ErrorAction SilentlyContinue)) { function Start-Service { param($Name) } }
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { function Get-CimInstance { param($Namespace,$ClassName) } }
    if (-not (Get-Command Remove-CimInstance -ErrorAction SilentlyContinue)) { function Remove-CimInstance { param([Parameter(ValueFromPipeline)]$InputObject) process {} } }
}
Describe 'Bounded temporary cleanup' {
    BeforeEach {
        $temp = New-Item -ItemType Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
        Mock Get-BISFTempRoots { [pscustomobject]@{WindowsTemp=$temp.FullName;CurrentUserTemp="$TestDrive/user"} }
        'old' | Set-Content "$temp/old.txt"
        (Get-Item "$temp/old.txt").LastWriteTimeUtc=[DateTime]::UtcNow.AddDays(-10)
        'young' | Set-Content "$temp/young.txt"
    }
    It 'removes only old files and preserves excluded trees' {
        New-Item -ItemType Directory "$temp/protected" | Out-Null
        'keep' | Set-Content "$temp/protected/keep.txt"
        (Get-Item "$temp/protected/keep.txt").LastWriteTimeUtc=[DateTime]::UtcNow.AddDays(-10)
        $c=@(Get-BISFCleanupCandidates $temp.FullName 7 @("$temp/protected"))
        Remove-BISFTempFiles $c
        Test-Path "$temp/old.txt" | Should -BeFalse
        Test-Path "$temp/young.txt" | Should -BeTrue
        Test-Path "$temp/protected/keep.txt" | Should -BeTrue
    }
    It 'rejects an arbitrary deletion root' {
        { Get-BISFCleanupCandidates $TestDrive 7 @() } | Should -Throw '*approved*'
    }
    It 'does not follow directory links or delete files replaced with links' {
        New-Item -ItemType Directory "$TestDrive/outside" -Force | Out-Null
        'keep' | Set-Content "$TestDrive/outside/keep.txt"
        (Get-Item "$TestDrive/outside/keep.txt").LastWriteTimeUtc=[DateTime]::UtcNow.AddDays(-10)
        New-Item -ItemType SymbolicLink -Path "$temp/link" -Target "$TestDrive/outside" | Out-Null
        $c=@(Get-BISFCleanupCandidates $temp.FullName 7 @())
        Remove-Item "$temp/old.txt"
        New-Item -ItemType SymbolicLink -Path "$temp/old.txt" -Target "$TestDrive/outside/keep.txt" | Out-Null
        { Remove-BISFTempFiles $c } | Should -Throw '*reparse*'
        Test-Path "$TestDrive/outside/keep.txt" | Should -BeTrue
    }
    It 'rechecks age before deleting a changed file' {
        $c=@(Get-BISFCleanupCandidates $temp.FullName 7 @())
        (Get-Item "$temp/old.txt").LastWriteTimeUtc=[DateTime]::UtcNow
        { Remove-BISFTempFiles $c } | Should -Throw '*changed*'
        Test-Path "$temp/old.txt" | Should -BeTrue
    }
    It 'rejects a linked cleanup root' {
        New-Item -ItemType Directory "$TestDrive/outside" -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path "$TestDrive/user" -Target "$TestDrive/outside" | Out-Null
        { Get-BISFCleanupCandidates "$TestDrive/user" 7 @() } | Should -Throw '*reparse*'
    }
}
Describe 'Configuration Manager operations' {
    BeforeEach {
        $script:trace=New-Object 'System.Collections.Generic.List[string]'
        Mock Get-Service { [pscustomobject]@{Status='Running'} }
        Mock Stop-Service { $script:trace.Add('stop') }
        Mock Start-Service { $script:trace.Add('start') }
        if (Get-Command Wait-BISFService -ErrorAction SilentlyContinue) { Mock Wait-BISFService {} }
        if (Get-Command Remove-BISFSmsCertificates -ErrorAction SilentlyContinue) { Mock Remove-BISFSmsCertificates { $script:trace.Add('certs') } }
        Mock Remove-Item { $script:trace.Add('ini') }
        Mock Test-Path { $true }
        $env:SystemRoot=$TestDrive
    }
    It 'stops the client before deleting only SMS identity' {
        $previous=Invoke-BISFCMPrepare
        $previous | Should -Be 'Running'
        ($script:trace -join ',') | Should -Be 'stop,certs,ini'
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq "$TestDrive/SMSCFG.ini" }
    }
    It 'restores running service state if deletion fails' {
        Mock Remove-BISFSmsCertificates { throw 'certificate failed' }
        { Invoke-BISFCMPrepare } | Should -Throw '*certificate failed*'
        ($script:trace -join ',') | Should -Be 'stop,start'
    }
    It 'uses CIM for trusted root keys and propagates provider failure' {
        Mock Get-CimInstance { throw 'provider unavailable' }
        { Invoke-BISFCMCloneReset } | Should -Throw '*provider unavailable*'
        Should -Invoke Get-CimInstance -Times 1 -ParameterFilter { $Namespace -eq 'root\ccm\locationservices' -and $ClassName -eq 'TrustedRootKey' }
    }
    It 'treats an empty successful CIM query as a no-op' {
        Mock Get-CimInstance { @() }
        Mock Remove-CimInstance { throw 'must not delete' }
        { Invoke-BISFCMCloneReset } | Should -Not -Throw
        Should -Invoke Remove-CimInstance -Times 0
    }
}
