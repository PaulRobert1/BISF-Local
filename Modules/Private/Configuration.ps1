# BIS-F Local, unofficial derivative. Modified 2026-10-12. GPL-3.0; see LICENSE.
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
        VDA = [pscustomobject]@{Enabled=$false;ExpectedRelease='2507';StopBeforeShutdown=$false}
        WEM = [pscustomobject]@{Enabled=$false;ExpectedRelease='2507'}
    }
    if ($null -ne $doc.SelectSingleNode('/BISF/Citrix')) {
        $citrix.VDA.Enabled = [Xml.XmlConvert]::ToBoolean($b.Citrix.VDA.Enabled.Trim())
        $citrix.VDA.ExpectedRelease = [string]$b.Citrix.VDA.ExpectedRelease
        $citrix.VDA.StopBeforeShutdown = [Xml.XmlConvert]::ToBoolean($b.Citrix.VDA.StopBeforeShutdown.Trim())
        $citrix.WEM.Enabled = [Xml.XmlConvert]::ToBoolean($b.Citrix.WEM.Enabled.Trim())
        $citrix.WEM.ExpectedRelease = [string]$b.Citrix.WEM.ExpectedRelease
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
            MinimumAgeDays = [int]$b.Cleanup.MinimumAgeDays
        }
        ConfigurationManager = [pscustomobject]@{
            PrepareIdentityReset = [Xml.XmlConvert]::ToBoolean($b.ConfigurationManager.PrepareIdentityReset.Trim())
            CloneTrustedRootKeyReset = [Xml.XmlConvert]::ToBoolean($b.ConfigurationManager.CloneTrustedRootKeyReset.Trim())
        }
        Personalization = [pscustomobject]@{ Enabled = [Xml.XmlConvert]::ToBoolean($b.Personalization.Enabled.Trim()) }
        Preflight = [pscustomobject]@{ BlockPendingReboot = [Xml.XmlConvert]::ToBoolean($b.Preflight.BlockPendingReboot.Trim()) }
        FinalAction = [string]$b.FinalAction
    }
}
