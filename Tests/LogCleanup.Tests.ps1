BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Configuration','Operations','Lifecycle','Logging','LogCleanup') {
        . "$root/Modules/Private/$n.ps1"
    }
}
Describe 'Opt-in log cleanup XML and strict selection' {
    BeforeEach {
        Mock Get-BISFEventLogInventory {
            foreach($n in 'Application','System','Setup','Vendor/Operational','Security'){
                [pscustomobject]@{LogName=$n;IsEnabled=$true;LogType='Operational'}
            }
            [pscustomobject]@{LogName='Disabled';IsEnabled=$false;LogType='Operational'}
            [pscustomobject]@{LogName='Analytic';IsEnabled=$true;LogType='Analytic'}
        }
        Mock Get-BISFEventLogMetadata {Get-BISFEventLogInventory|Where-Object LogName -eq $Channel}
        $c=Read-BISFConfig "$root/Tests/Fixtures/OptInBaseline.xml" $root
    }
    It 'defaults both cleanup switches to disabled' {
        $c.LogCleanup.WindowsEventLogs | Should -BeFalse
        $c.LogCleanup.BISFLogs | Should -BeFalse
        @(Get-BISFEventLogCleanupChannels) | Should -Be @('Application','Setup','System','Vendor/Operational')
    }
    It 'does not automatically clear logs during ordinary master preparation' {
        Mock Clear-BISFEventLogChannel { throw 'Must not clear Windows event logs' }
        Mock Remove-BISFLocalLogs { throw 'Must not delete local diagnostics' }
        { Invoke-BISFLogCleanup $c } | Should -Not -Throw
        Should -Invoke Clear-BISFEventLogChannel -Times 0
        Should -Invoke Remove-BISFLocalLogs -Times 0
    }
    It 'requires explicit FinalAction Shutdown when any log deletion is opted in' {
        $c.LogCleanup.WindowsEventLogs=$true
        { Test-BISFLogCleanupSettings $c } | Should -Throw '*FinalAction=Shutdown*'
        $c.LogCleanup.WindowsEventLogs=$false
        $c.LogCleanup.BISFLogs=$true
        { Test-BISFLogCleanupSettings $c } | Should -Throw '*FinalAction=Shutdown*'
    }
    It 'never accepts Security or ineligible channels' {
        { Clear-BISFEventLogChannel 'Security' } | Should -Throw '*allowlist*'
        { Clear-BISFEventLogChannel 'Analytic' } | Should -Throw '*allowlist*'
    }
    It 'uses eligible Windows and vendor channels and optional own logs only when selected' {
        $c.FinalAction='Shutdown'
        $c.LogCleanup.WindowsEventLogs=$true
        $c.LogCleanup.BISFLogs=$true
        $script:channels=New-Object 'System.Collections.Generic.List[string]'
        $script:own=0
        Mock Clear-BISFEventLogChannel { $script:channels.Add($Channel) }
        Mock Remove-BISFLocalLogs { $script:own++ }
        Invoke-BISFLogCleanup $c
        ($script:channels -join ',') | Should -Be 'Application,Setup,System,Vendor/Operational'
        $script:own | Should -Be 1
    }
    It 'preserves permission-protected logs with a warning and clears writable channels' {
        $c.FinalAction='Shutdown';$c.LogCleanup.WindowsEventLogs=$true
        Mock Clear-BISFEventLogChannel {if($Channel -eq 'Application'){throw (New-Object UnauthorizedAccessException('Read-only channel'))}}
        Mock Write-BISFLog {}
        {Invoke-BISFLogCleanup $c}|Should -Not -Throw
        Should -Invoke Clear-BISFEventLogChannel -Times 4
        Should -Invoke Write-BISFLog -Times 1 -ParameterFilter {$Level -eq 'Warning' -and $Message -match 'permission-protected'}
        Should -Invoke Write-BISFLog -Times 3 -ParameterFilter {$Level -eq 'Info'}
    }
    It 'attempts remaining channels after a failure and blocks shutdown with retained evidence' {
        $c.FinalAction='Shutdown';$c.LogCleanup.WindowsEventLogs=$true
        Mock Clear-BISFEventLogChannel {if($Channel -eq 'Application'){throw 'denied'}}
        Mock Write-BISFLog {}
        {Invoke-BISFLogCleanup $c}|Should -Throw '*shutdown blocked*'
        Should -Invoke Clear-BISFEventLogChannel -Times 4
        Should -Invoke Write-BISFLog -Times 1 -ParameterFilter {$Level -eq 'Error'}
        Should -Invoke Write-BISFLog -Times 3 -ParameterFilter {$Level -eq 'Info'}
    }
    It 'refuses log clearing without a readable target event channel' {
        $c.FinalAction='Shutdown'
        $c.LogCleanup.WindowsEventLogs=$true
        Mock Get-WinEvent { throw 'Setup log not available' }
        { Test-BISFLogCleanupPreflight $c $root } | Should -Throw '*Setup log not available*'
    }
    It 'checks trust for a missing log directory before a logger can create it' {
        $c.FinalAction='Shutdown'
        $c.LogCleanup.BISFLogs=$true
        $c.Logging.Path=Join-Path $TestDrive 'missing-logs'
        Mock Test-BISFProtectedLocation { throw 'Unsafe log ancestor' }
        { Test-BISFLogCleanupPreflight $c $root } | Should -Throw '*Unsafe log ancestor*'
    }
}
Describe 'BISF-only generated log removal and path protection' {
    BeforeEach {
        $script:dir=Join-Path $TestDrive ('BISF-Logs-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:dir | Out-Null
        Mock Test-BISFProtectedLocation {}
        $script:removed=New-Object 'System.Collections.Generic.List[string]'
        Mock Remove-BISFLogArtifact { $script:removed.Add($Path) }
    }
    It 'deletes ONLY BISF generated names, never unrelated application or Citrix logs' {
        $valid='BISF-Prepare-20261015-103015-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.log'
        $current='BISF-Finalize-20261015-103016-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.log'
        $invalid=@('CitrixWEM.log','application.evtx','BISF-Security.log','BISF-Prepare-foo.log')
        foreach ($name in @($valid,$current)+$invalid) {
            'fixture' | Set-Content -LiteralPath (Join-Path $script:dir $name)
        }
        Remove-BISFLocalLogs $script:dir
        $script:removed.Count | Should -Be 2
        ($script:removed | ForEach-Object { [IO.Path]::GetFileName($_) }) | Should -Contain $valid
        ($script:removed | ForEach-Object { [IO.Path]::GetFileName($_) }) | Should -Contain $current
        foreach ($name in $invalid) { $script:removed | Should -Not -Contain (Join-Path $script:dir $name) }
    }
    It 'does not delete anything if the log directory does not exist' {
        $missing=Join-Path $script:dir 'missing'
        Remove-BISFLocalLogs $missing
        Should -Invoke Remove-BISFLogArtifact -Times 0
    }
    It 'refuses the log folder if it is a symlink' {
        $dest=Join-Path $TestDrive ('dest-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dest | Out-Null
        $link=Join-Path $script:dir 'link'
        New-Item -ItemType SymbolicLink -Path $link -Target $dest | Out-Null
        { Remove-BISFLocalLogs $link } | Should -Throw '*reparse*'
        Should -Invoke Remove-BISFLogArtifact -Times 0
    }
}
Describe 'Optional checkbox GUI source parse' {
    It 'parses Configure-BISF-LogCleanup.ps1 in PowerShell without running its UI' {
        $file=Join-Path $root 'Configure-BISF-LogCleanup.ps1'
        $source=Get-Content -LiteralPath $file -Raw -ErrorAction Stop
        $tokens=$null;$parseErrors=$null
        $null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $source | Should -Match 'System\.Windows\.Forms\.CheckBox'
        $source | Should -Match 'Set-BISFLogCleanupOptions'
    }
}

