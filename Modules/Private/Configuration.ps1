# BIS-F Local, unofficial derivative. Modified 2026-10-12. GPL-3.0; see LICENSE.
function Get-BISFFileHash {
    param([Parameter(Mandatory=$true)][string]$LiteralPath)
    # Hash the local bytes directly: Windows PowerShell Get-FileHash delegates
    # to provider reads whose module-scoped WhatIf can suppress the result.
    $stream=$null;$algorithm=$null
    try {
        $stream=[IO.File]::OpenRead($LiteralPath)
        $algorithm=[Security.Cryptography.SHA256]::Create()
        $hash=[BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','')
        [pscustomobject]@{Algorithm='SHA256';Hash=$hash;Path=[IO.Path]::GetFullPath($LiteralPath)}
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $algorithm) { $algorithm.Dispose() }
    }
}
function Resolve-BISFPath {
    param([string]$Path, [string]$ScriptRoot)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Path must not be blank.' }
    $value = $Path.Trim()
    if ($value -match '[\x00-\x1f"*?]' -or $value -match '^[A-Za-z]:[^\\/]' -or $value -match '::' -or $value -match '^\\\\[?.]\\') {
        throw 'Invalid filesystem path.'
    }
    if ($value.Contains(':') -and $value -notmatch '^[A-Za-z]:[\\/]') { throw 'Provider paths are not allowed.' }
    if ([IO.Path]::DirectorySeparatorChar -eq '/') { $value = $value.Replace('\','/') }
    if (-not [IO.Path]::IsPathRooted($value)) { $value = Join-Path $ScriptRoot $value }
    [IO.Path]::GetFullPath($value)
}
function Read-BISFConfig {
    param([string]$ConfigPath, [string]$ScriptRoot)
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.ValidationType = [Xml.ValidationType]::Schema
    $settings.Schemas.XmlResolver = $null
    [void]$settings.Schemas.Add($null, (Join-Path $ScriptRoot 'GlobalConfig.xsd'))
    $reader = $null
    try {
        $reader = [Xml.XmlReader]::Create($ConfigPath, $settings)
        $doc = New-Object Xml.XmlDocument
        $doc.XmlResolver = $null
        $doc.Load($reader)
    } finally { if ($null -ne $reader) { $reader.Dispose() } }
    $b = $doc.BISF
    $citrix = [pscustomobject]@{
        VDA = [pscustomobject]@{Enabled=$false;StopBeforeShutdown=$false}
        WEM = [pscustomobject]@{Enabled=$false}
    }
    if ($null -ne $doc.SelectSingleNode('/BISF/Citrix')) {
        $citrix.VDA.Enabled = [Xml.XmlConvert]::ToBoolean($b.Citrix.VDA.Enabled.Trim())
        $citrix.VDA.StopBeforeShutdown = [Xml.XmlConvert]::ToBoolean($b.Citrix.VDA.StopBeforeShutdown.Trim())
        $citrix.WEM.Enabled = [Xml.XmlConvert]::ToBoolean($b.Citrix.WEM.Enabled.Trim())
    }
    $userProfiles=$false
    if ($null -ne $doc.SelectSingleNode('/BISF/Cleanup/UserProfiles')) {
        $userProfiles=[Xml.XmlConvert]::ToBoolean($b.Cleanup.UserProfiles.Trim())
    }
    $excludedProfileSIDs=@($doc.SelectNodes('/BISF/Cleanup/ExcludedProfileSIDs/SID') | ForEach-Object { ([string]$_.InnerText).Trim() })
    foreach ($sid in $excludedProfileSIDs) {
        if ($sid -notmatch '^S-1-(5-21-([0-9]+-){3}[0-9]+|12-1-([0-9]+-){3}[0-9]+)$') {
            throw "Invalid ExcludedProfileSIDs SID: $sid"
        }
    }
    $recycleBin=$false
    if ($null -ne $doc.SelectSingleNode('/BISF/Cleanup/RecycleBin')) {
        $recycleBin=[Xml.XmlConvert]::ToBoolean($b.Cleanup.RecycleBin.Trim())
    }
    $blockOtherProfiles=$false
    if ($null -ne $doc.SelectSingleNode('/BISF/Preflight/BlockOtherLoadedProfiles')) {
        $blockOtherProfiles=[Xml.XmlConvert]::ToBoolean($b.Preflight.BlockOtherLoadedProfiles.Trim())
    }
    $minFreeGB=0
    if ($null -ne $doc.SelectSingleNode('/BISF/Preflight/MinimumSystemDriveFreeGB')) {
        $minFreeGB=[int]$b.Preflight.MinimumSystemDriveFreeGB
    }
    $servicing=[pscustomobject]@{ComponentCleanup=$false;TimeoutMinutes=75}
    if ($null -ne $doc.SelectSingleNode('/BISF/Servicing')) {
        $servicing.ComponentCleanup=[Xml.XmlConvert]::ToBoolean($b.Servicing.ComponentCleanup.Trim())
        $servicing.TimeoutMinutes=[int]$b.Servicing.TimeoutMinutes
    }
    $logCleanup=[pscustomobject]@{WindowsEventLogs=$false;BISFLogs=$false}
    if ($null -ne $doc.SelectSingleNode('/BISF/LogCleanup')) {
        $logCleanup.WindowsEventLogs=[Xml.XmlConvert]::ToBoolean($b.LogCleanup.WindowsEventLogs.Trim())
        $logCleanup.BISFLogs=[Xml.XmlConvert]::ToBoolean($b.LogCleanup.BISFLogs.Trim())
    }
    $finalization=[pscustomobject]@{RemoveOperatorProfile=$false;TimeoutMinutes=30}
    if ($null -ne $doc.SelectSingleNode('/BISF/Finalization')) {
        $finalization.RemoveOperatorProfile=[Xml.XmlConvert]::ToBoolean($b.Finalization.RemoveOperatorProfile.Trim())
        $finalization.TimeoutMinutes=[int]$b.Finalization.TimeoutMinutes
    }
    [pscustomobject]@{
        Citrix = $citrix
        SchemaVersion = 1
        Logging = [pscustomobject]@{
            Enabled = [Xml.XmlConvert]::ToBoolean($b.Logging.Enabled.Trim())
            Path = Resolve-BISFPath $b.Logging.Path $ScriptRoot
        }
        Cleanup = [pscustomobject]@{
            WindowsTemp = [Xml.XmlConvert]::ToBoolean($b.Cleanup.WindowsTemp.Trim())
            CurrentUserTemp = [Xml.XmlConvert]::ToBoolean($b.Cleanup.CurrentUserTemp.Trim())
            UserProfiles = [bool]$userProfiles
            ExcludedProfileSIDs = [string[]]$excludedProfileSIDs
            RecycleBin = [bool]$recycleBin
            MinimumAgeDays = [int]$b.Cleanup.MinimumAgeDays
        }
        Servicing = $servicing
        LogCleanup = $logCleanup
        Finalization = $finalization
        ConfigurationManager = [pscustomobject]@{
            PrepareIdentityReset = [Xml.XmlConvert]::ToBoolean($b.ConfigurationManager.PrepareIdentityReset.Trim())
            CloneTrustedRootKeyReset = [Xml.XmlConvert]::ToBoolean($b.ConfigurationManager.CloneTrustedRootKeyReset.Trim())
        }
        Personalization = [pscustomobject]@{ Enabled = [Xml.XmlConvert]::ToBoolean($b.Personalization.Enabled.Trim()) }
        Preflight = [pscustomobject]@{
            BlockPendingReboot = [Xml.XmlConvert]::ToBoolean($b.Preflight.BlockPendingReboot.Trim())
            MinimumSystemDriveFreeGB = [int]$minFreeGB
            BlockOtherLoadedProfiles = [bool]$blockOtherProfiles
        }
        FinalAction = [string]$b.FinalAction
    }
}

function Set-BISFLogCleanupOptions {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,[string]$ScriptRoot,
        [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedHash,
        [bool]$WindowsEventLogs,[bool]$BISFLogs
    )
    # Shared with the checkbox editor so save behavior is tested without a UI.
    # Work on a same-directory temporary file; never truncate the original XML.
    $ConfigPath=Resolve-BISFPath $ConfigPath $ScriptRoot
    $schema=Join-Path $ScriptRoot 'GlobalConfig.xsd'
    Test-BISFNoReparsePath $ConfigPath
    Test-BISFProtectedLocation $ConfigPath
    Test-BISFProtectedLocation $schema
    if ((Get-BISFFileHash -LiteralPath $ConfigPath).Hash -ne $ExpectedHash) {
        throw 'Configuration changed while the editor was open. Reopen the editor before saving.'
    }
    $config=Read-BISFConfig $ConfigPath $ScriptRoot
    if (($WindowsEventLogs -or $BISFLogs) -and $config.FinalAction -ne 'Shutdown') {
        throw 'Log cleanup requires explicit FinalAction=Shutdown; the editor will not enable shutdown.'
    }
    $settings=New-Object Xml.XmlReaderSettings
    $settings.XmlResolver=$null
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
    $doc=New-Object Xml.XmlDocument
    $doc.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($ConfigPath,$settings)
    try { $doc.Load($reader) } finally { $reader.Dispose() }
    $node=$doc.SelectSingleNode('/BISF/LogCleanup')
    if ($null -eq $node) {
        $node=$doc.CreateElement('LogCleanup')
        $null=$doc.DocumentElement.InsertBefore($node,$doc.SelectSingleNode('/BISF/ConfigurationManager'))
    }
    foreach ($name in @('WindowsEventLogs','BISFLogs')) {
        $child=$node.SelectSingleNode($name)
        if ($null -eq $child) { $child=$doc.CreateElement($name); $null=$node.AppendChild($child) }
        $value=if ($name -eq 'WindowsEventLogs') { $WindowsEventLogs } else { $BISFLogs }
        $child.InnerText=([string]$value).ToLowerInvariant()
    }
    $dir=Split-Path -Parent $ConfigPath
    Test-BISFProtectedLocation $dir
    $tmp=Join-Path $dir ([guid]::NewGuid().ToString('N')+'.tmp')
    try {
        $doc.Save($tmp)
        $null=Read-BISFConfig $tmp $ScriptRoot
        # Recheck after serialization/validation. Only administrators can replace
        # files in this protected directory; concurrent administrative changes
        # still require exclusive operational control during a seal.
        Test-BISFNoReparsePath $ConfigPath
        Test-BISFProtectedLocation $ConfigPath
        if ((Get-BISFFileHash -LiteralPath $ConfigPath).Hash -ne $ExpectedHash) {
            throw 'Configuration changed before saving. Reopen the editor.'
        }
        [IO.File]::Replace($tmp,$ConfigPath,[NullString]::Value)
    } finally {
        if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }
    }
}

