BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($name in 'Configuration','Operations','Lifecycle') { . "$root/Modules/Private/$name.ps1" }
}
Describe 'Checkbox editor configuration writes' {
    BeforeEach {
        $cfg=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.xml')
        [xml]$xml=Get-Content "$root/Tests/Fixtures/OptInBaseline.xml" -Raw
        $xml.BISF.FinalAction='Shutdown'
        $xml.Save($cfg)
        $hash=(Get-FileHash -LiteralPath $cfg).Hash
        Mock Test-BISFProtectedLocation {}
    }
    It 'saves only the chosen flags while preserving other settings and XML comments' {
        { Set-BISFLogCleanupOptions $cfg $root $hash $true $false } | Should -Not -Throw
        $c=Read-BISFConfig $cfg $root
        $c.LogCleanup.WindowsEventLogs | Should -BeTrue
        $c.LogCleanup.BISFLogs | Should -BeFalse
        $c.FinalAction | Should -Be 'Shutdown'
        $c.Cleanup.UserProfiles | Should -BeFalse
        Get-Content $cfg -Raw | Should -Match 'Installed agents only'
    }
    It 'refuses to overwrite configuration edited while the dialog was open' {
        Add-Content -LiteralPath $cfg -Value '<!-- updated by another operator -->'
        $updated=(Get-FileHash -LiteralPath $cfg).Hash
        { Set-BISFLogCleanupOptions $cfg $root $hash $true $true } | Should -Throw '*changed*'
        (Get-FileHash -LiteralPath $cfg).Hash | Should -Be $updated
    }
    It 'never enables shutdown implicitly when either checkbox is selected' {
        (Get-Content $cfg -Raw).Replace('<FinalAction>Shutdown','<FinalAction>None') | Set-Content $cfg
        $before=(Get-FileHash -LiteralPath $cfg).Hash
        { Set-BISFLogCleanupOptions $cfg $root $before $false $true } | Should -Throw '*FinalAction=Shutdown*'
        (Get-FileHash -LiteralPath $cfg).Hash | Should -Be $before
    }
    It 'inserts the optional section in schema order for legacy configuration' {
        $source=[regex]::Replace((Get-Content $cfg -Raw),'(?s)\s*<LogCleanup>.*?</LogCleanup>','')
        $source | Set-Content $cfg
        $before=(Get-FileHash -LiteralPath $cfg).Hash
        { Set-BISFLogCleanupOptions $cfg $root $before $false $true } | Should -Not -Throw
        (Read-BISFConfig $cfg $root).LogCleanup.BISFLogs | Should -BeTrue
    }
    It 'leaves malformed input byte-for-byte intact' {
        Add-Content -LiteralPath $cfg -Value '<broken>'
        $before=(Get-FileHash -LiteralPath $cfg).Hash
        { Set-BISFLogCleanupOptions $cfg $root $before $true $true } | Should -Throw
        (Get-FileHash -LiteralPath $cfg).Hash | Should -Be $before
    }
    It 'preserves the original file if Windows refuses atomic replacement' {
        $stream=[IO.File]::Open($cfg,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            { Set-BISFLogCleanupOptions $cfg $root $hash $true $true } | Should -Throw
            (Get-FileHash -LiteralPath $cfg).Hash | Should -Be $hash
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.tmp').Count | Should -Be 0
        } finally { $stream.Dispose() }
    }
    It 'rejects a redirected config path without changing its target' {
        $link=Join-Path $TestDrive 'config-link.xml'
        New-Item -ItemType SymbolicLink -Path $link -Target $cfg | Out-Null
        { Set-BISFLogCleanupOptions $link $root $hash $true $true } | Should -Throw '*reparse*'
        (Get-FileHash -LiteralPath $cfg).Hash | Should -Be $hash
    }
}
