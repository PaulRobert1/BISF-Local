# BISF-Local — explicit master-only log hygiene.
# This module intentionally excludes Security auditing and arbitrary Citrix/WEM logs.
# Windows Event Logs are cleared through supported .NET APIs, not by deleting .evtx files.

function Get-BISFEventLogCleanupChannels {
    # Fixed allowlist. Never enumerate and delete every event channel.
    @('Application','System','Setup')
}
function Test-BISFLogCleanupSettings {
    param($Config)
    if (-not $Config.LogCleanup.WindowsEventLogs -and -not $Config.LogCleanup.BISFLogs) { return }
    if ($Config.FinalAction -ne 'Shutdown') {
        throw 'Log cleanup is a last-step master seal operation and requires FinalAction=Shutdown.'
    }
}
function Test-BISFLogCleanupPreflight {
    param($Config,[string]$ScriptRoot)
    Test-BISFLogCleanupSettings $Config
    if ($Config.LogCleanup.WindowsEventLogs) {
        $null=Get-Command Get-WinEvent -CommandType Cmdlet -ErrorAction Stop
        foreach ($channel in Get-BISFEventLogCleanupChannels) {
            # Only test presence/access; do not read, delete or export records.
            $null=Get-WinEvent -ListLog $channel -ErrorAction Stop
        }
    }
    if ($Config.LogCleanup.BISFLogs) {
        $dir=[IO.Path]::GetFullPath([string]$Config.Logging.Path)
        $root=[IO.Path]::GetPathRoot($dir)
        if (-not [IO.Path]::IsPathRooted($dir) -or $dir -match '^\\\\' -or
            $dir.TrimEnd([char[]]'\/').Equals($root.TrimEnd([char[]]'\/'),[StringComparison]::OrdinalIgnoreCase)) {
            throw 'BISF log cleanup requires a dedicated, non-root local log folder.'
        }
        Test-BISFNoReparsePath $dir
        # Also validate the nearest existing ancestor if the logger will create
        # this folder later. A missing directory is not an ACL exemption.
        Test-BISFProtectedLocation $dir
    }
}
function Clear-BISFEventLogChannel {
    param([Parameter(Mandatory=$true)][string]$Channel)
    if ($Channel -cnotin @(Get-BISFEventLogCleanupChannels)) {
        throw "Refusing to clear an event channel outside the allowlist: $Channel"
    }
    [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($Channel)
}
function Remove-BISFLogArtifact {
    param([Parameter(Mandatory=$true)][string]$Path)
    # Called only after name/path/ACL/link verification by Remove-BISFLocalLogs.
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
}
function Remove-BISFLocalLogs {
    param([Parameter(Mandatory=$true)][string]$LogDirectory)
    $dir=[IO.Path]::GetFullPath($LogDirectory)
    if (-not (Test-Path -LiteralPath $dir)) { return }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        throw 'BISF log directory is not a directory.'
    }
    Test-BISFNoReparsePath $dir
    Test-BISFProtectedLocation $dir
    # Only files produced by New-BISFLogger. Do not remove arbitrary .log/.etl/.evtx,
    # or Citrix/WEM/FSLogix logs (those are managed by their own providers).
    $namePattern='^BISF-(Validate|Prepare|Personalize|Finalize|VerifyClone)-[0-9]{8}-[0-9]{6}-[a-fA-F0-9]{32}\.log$'
    foreach ($item in Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) {
        if ($item.PSIsContainer -or $item.Name -cnotmatch $namePattern) { continue }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if (-not (Test-BISFPathWithin $item.FullName $dir)) { throw 'BISF log file escaped the configured logging directory.' }
        Test-BISFNoReparsePath $item.FullName
        # Re-read immediately before deletion to reject replacement/symlink races.
        $current=Get-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
        if ($current.PSIsContainer -or ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $current.Name -cnotmatch $namePattern) { throw 'BISF log candidate changed before deletion.' }
        Remove-BISFLogArtifact $current.FullName
    }
}
function Invoke-BISFLogCleanup {
    param($Config)
    Test-BISFLogCleanupSettings $Config
    if ($Config.LogCleanup.WindowsEventLogs) {
        # Fixed set of non-Security channels. Windows may write new events after
        # clearing; this is final-stage hygiene, not a guarantee of empty logs.
        foreach ($channel in Get-BISFEventLogCleanupChannels) {
            Clear-BISFEventLogChannel $channel
        }
    }
    if ($Config.LogCleanup.BISFLogs) {
        Remove-BISFLocalLogs $Config.Logging.Path
    }
}

