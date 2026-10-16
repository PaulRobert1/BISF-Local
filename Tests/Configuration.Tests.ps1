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
    It 'reads a real configuration hash under WhatIf without changing caller preference or bytes' {
        $expected=(Get-FileHash -LiteralPath $cfgPath -Algorithm SHA256).Hash
        $prior=$WhatIfPreference
        try {
            $WhatIfPreference=$true
            (Get-BISFFileHash -LiteralPath $cfgPath).Hash | Should -Be $expected
            $WhatIfPreference | Should -BeTrue
        } finally { $WhatIfPreference=$prior }
        (Get-FileHash -LiteralPath $cfgPath -Algorithm SHA256).Hash | Should -Be $expected
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
    It 'defaults profile cleanup to disabled when an older XML omits it' {
        (Get-Content $cfgPath -Raw).Replace('<UserProfiles>false</UserProfiles>','') | Set-Content $cfgPath
        $config=Read-BISFConfig $cfgPath $root
        $config.Cleanup.UserProfiles | Should -BeFalse
        $config.Cleanup.ExcludedProfileSIDs.Count | Should -Be 0
    }
    It 'accepts explicit profile cleanup and protected SID list without affecting temp file age' {
        $body=(Get-Content $cfgPath -Raw).Replace('<UserProfiles>false</UserProfiles>','<UserProfiles>true</UserProfiles>')
        $body=$body.Replace('<RecycleBin>false</RecycleBin>','<RecycleBin>false</RecycleBin><ExcludedProfileSIDs><SID>S-1-5-21-111-222-333-1001</SID></ExcludedProfileSIDs>')
        $body | Set-Content $cfgPath
        $config=Read-BISFConfig $cfgPath $root
        $config.Cleanup.UserProfiles | Should -BeTrue
        $config.Cleanup.ExcludedProfileSIDs.Count | Should -Be 1
        $config.Cleanup.ExcludedProfileSIDs[0] | Should -Be 'S-1-5-21-111-222-333-1001'
        $config.Cleanup.MinimumAgeDays | Should -Be 7
    }
    It 'rejects malformed SID exclusions in strict XML' {
        (Get-Content $cfgPath -Raw).Replace('<RecycleBin>false</RecycleBin>','<RecycleBin>false</RecycleBin><ExcludedProfileSIDs><SID>NOT-A-SID</SID></ExcludedProfileSIDs>') | Set-Content $cfgPath
        { Read-BISFConfig $cfgPath $root } | Should -Throw '*Invalid ExcludedProfileSIDs*'
    }
    It 'parses safe maintenance defaults without changing older XML compatibility' {
        $c=Read-BISFConfig $cfgPath $root
        $c.Cleanup.RecycleBin | Should -BeFalse
        $c.Servicing.ComponentCleanup | Should -BeFalse
        $c.Servicing.TimeoutMinutes | Should -Be 75
        $c.Finalization.RemoveOperatorProfile | Should -BeFalse
        $c.Finalization.TimeoutMinutes | Should -Be 30
        $c.Preflight.BlockOtherLoadedProfiles | Should -BeTrue
    }
    It 'accepts legacy XML with optional maintenance sections absent and defaults to non-destructive' {
        $xml=Get-Content $cfgPath -Raw
        $xml=[regex]::Replace($xml,'(?s)\s*<Servicing>.*?</Servicing>','')
        $xml=[regex]::Replace($xml,'(?s)\s*<Finalization>.*?</Finalization>','')
        $xml=$xml.Replace('    <RecycleBin>false</RecycleBin>','')
        $xml=$xml.Replace('    <BlockOtherLoadedProfiles>true</BlockOtherLoadedProfiles>','')
        $xml=$xml.Replace('    <MinimumSystemDriveFreeGB>0</MinimumSystemDriveFreeGB>','')
        $xml | Set-Content $cfgPath
        $c=Read-BISFConfig $cfgPath $root
        $c.Servicing.ComponentCleanup | Should -BeFalse
        $c.Cleanup.RecycleBin | Should -BeFalse
        $c.Finalization.RemoveOperatorProfile | Should -BeFalse
        $c.Preflight.BlockOtherLoadedProfiles | Should -BeFalse
    }
    It 'defaults log cleanup switches to false and accepts existing XML without LogCleanup' {
        $c=Read-BISFConfig $cfgPath $root
        $c.LogCleanup.WindowsEventLogs | Should -BeFalse
        $c.LogCleanup.BISFLogs | Should -BeFalse
        $source=Get-Content $cfgPath -Raw
        $source=[regex]::Replace($source,'(?s)\s*<LogCleanup>.*?</LogCleanup>','')
        $source | Set-Content $cfgPath
        $legacy=Read-BISFConfig $cfgPath $root
        $legacy.LogCleanup.WindowsEventLogs | Should -BeFalse
        $legacy.LogCleanup.BISFLogs | Should -BeFalse
    }
    It 'accepts explicit Windows log and BISF-only log deletion switches' {
        $source=(Get-Content $cfgPath -Raw).Replace('<WindowsEventLogs>false</WindowsEventLogs>','<WindowsEventLogs>true</WindowsEventLogs>')
        $source=$source.Replace('<BISFLogs>false</BISFLogs>','<BISFLogs>true</BISFLogs>')
        $source | Set-Content $cfgPath
        $c=Read-BISFConfig $cfgPath $root
        $c.LogCleanup.WindowsEventLogs | Should -BeTrue
        $c.LogCleanup.BISFLogs | Should -BeTrue
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
