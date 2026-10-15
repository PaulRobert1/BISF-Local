BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path $PSScriptRoot -Parent
    $file = Join-Path $root 'Modules/Private/Configuration.ps1'
    if (Test-Path $file) { . $file }
    $log = Join-Path $root 'Modules/Private/Logging.ps1'
    if (Test-Path $log) { . $log }
}
Describe 'Configuration and logging contract' {
    BeforeEach {
        $cfgPath = Join-Path $TestDrive 'GlobalConfig.xml'
        if (Test-Path "$root/GlobalConfig.xml") { Copy-Item "$root/GlobalConfig.xml" $cfgPath }
    }
    It 'loads real booleans and resolves logs against the script root' {
        Push-Location $TestDrive
        try { $c = Read-BISFConfig $cfgPath $root } finally { Pop-Location }
        $c.Logging.Enabled | Should -BeTrue
        $c.Cleanup.WindowsTemp | Should -BeFalse
        $c.Logging.Path | Should -Be (Join-Path $root 'logs')
        $c.FinalAction | Should -Be 'None'
    }
    It 'rejects malformed and unknown settings: <Kind>' -ForEach @(
        @{Kind='unknown'; Old='<Logging>'; New='<Surprise/><Logging>'},
        @{Kind='duplicate'; Old='<Enabled>true</Enabled>'; New='<Enabled>true</Enabled><Enabled>false</Enabled>'},
        @{Kind='boolean'; Old='<Enabled>true</Enabled>'; New='<Enabled>maybe</Enabled>'},
        @{Kind='blank'; Old='<Path>.\logs</Path>'; New='<Path> </Path>'},
        @{Kind='enum'; Old='<FinalAction>None</FinalAction>'; New='<FinalAction>Reboot</FinalAction>'},
        @{Kind='version'; Old='SchemaVersion="1"'; New='SchemaVersion="2"'}
    ) {
        (Get-Content $cfgPath -Raw).Replace($Old,$New) | Set-Content $cfgPath
        { Read-BISFConfig $cfgPath $root } | Should -Throw
    }
    It 'rejects DTD entities' {
        '<!DOCTYPE BISF [<!ENTITY x "test">]><BISF SchemaVersion="1">&x;</BISF>' | Set-Content $cfgPath
        { Read-BISFConfig $cfgPath $root } | Should -Throw
    }
    It 'does not create anything when logging is disabled even for errors' {
        $c = [pscustomobject]@{Logging=[pscustomobject]@{Enabled=$false;Path="$TestDrive/absent"}}
        $l = New-BISFLogger $c Validate
        Write-BISFLog $l Error Test 'failure'
        Close-BISFLogger $l
        Test-Path "$TestDrive/absent" | Should -BeFalse
    }
    It 'creates distinct UTF8 logs in the requested folder' {
        $c = [pscustomobject]@{Logging=[pscustomobject]@{Enabled=$true;Path="$TestDrive/custom"}}
        $l = New-BISFLogger $c Validate
        $l2 = New-BISFLogger $c Prepare
        Write-BISFLog $l Info Test 'Completed café'
        Close-BISFLogger $l
        Close-BISFLogger $l2
        $l.LogFile | Should -Not -Be $l2.LogFile
        Get-Content $l.LogFile -Raw -Encoding UTF8 | Should -Match '\[Info\].*Test.*Completed café'
    }
    It 'fails without fallback when the requested folder is a file' {
        'file' | Set-Content "$TestDrive/occupied"
        $c = [pscustomobject]@{Logging=[pscustomobject]@{Enabled=$true;Path="$TestDrive/occupied"}}
        { New-BISFLogger $c Validate } | Should -Throw
    }
    It 'propagates a failed log write' {
        $l=[pscustomobject]@{Enabled=$true;LogFile="$TestDrive/no-parent/log.txt"}
        { Write-BISFLog $l Error Test 'failed' } | Should -Throw
    }
}
