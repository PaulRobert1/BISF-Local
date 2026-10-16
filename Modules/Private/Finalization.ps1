# BISF-Local: explicitly opted-in two-phase SYSTEM finalization.
# The operator must sign out normally. No forced logoff, raw folder deletion,
# external vendor tools or direct deletion of an in-use profile.

function Test-BISFOperatorSealSettings {
    param($Config)
    if (-not $Config.Finalization.RemoveOperatorProfile) { return }
    if (-not $Config.Cleanup.UserProfiles) {
        throw 'RemoveOperatorProfile requires Cleanup.UserProfiles=true.'
    }
    if ($Config.FinalAction -ne 'Shutdown') {
        throw 'RemoveOperatorProfile requires FinalAction=Shutdown; SYSTEM will shut down only after profile removal.'
    }
    if ($Config.Personalization.Enabled -or
        $Config.ConfigurationManager.PrepareIdentityReset -or
        $Config.ConfigurationManager.CloneTrustedRootKeyReset) {
        throw 'Operator profile finalization cannot be combined with automatic clone personalization or Configuration Manager identity resets.'
    }
    if ($Config.Citrix.VDA.StopBeforeShutdown) {
        throw 'Operator profile finalization does not support the interactive VDA StopBeforeShutdown operation; keep this option false.'
    }
    if (-not $Config.Preflight.BlockPendingReboot) {
        throw 'Operator profile finalization requires BlockPendingReboot=true.'
    }
}
function Get-BISFOperatorSealTarget {
    param($Config,[string]$ScriptRoot,[string]$ConfigPath,[string[]]$ProtectedPaths=@())
    $sid=Get-BISFCurrentUserSid
    if ($sid -notmatch '^S-1-5-21-([0-9]+-){3}([0-9]+)$' -or [long]$Matches[2] -lt 1000) {
        throw 'Operator sealing requires a normal administrative account SID; built-in and reserved identities are not eligible.'
    }
    if ($sid -in $Config.Cleanup.ExcludedProfileSIDs) {
        throw 'The invoking operator SID is explicitly excluded from profile cleanup.'
    }
    $root=Get-BISFProfilesRoot
    $profiles=@(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$sid'" -ErrorAction Stop)
    if ($profiles.Count -ne 1) { throw "Cannot uniquely locate current operator profile SID $sid." }
    $p=$profiles[0]
    if ($null -eq $p.Special -or $p.Special -or -not (Test-BISFDirectProfilePath $p.LocalPath $root)) {
        throw 'Operator profile is special or outside the expected Windows profile root.'
    }
    Test-BISFNoReparsePath ([string]$p.LocalPath)
    if (-not (Test-Path -LiteralPath $p.LocalPath -PathType Container)) {
        throw 'Operator profile directory does not exist.'
    }
    foreach ($protected in (@($ScriptRoot,$ConfigPath,$Config.Logging.Path)+$ProtectedPaths)) {
        if (Test-BISFPathWithin $protected $p.LocalPath) {
            throw 'The BISF package, config or log path is inside the operator profile scheduled for deletion.'
        }
    }
    [pscustomobject]@{SID=$sid;Path=[string]$p.LocalPath;Root=$root}
}
function Get-BISFOperatorSealStatePath {
    param([string]$ScriptRoot)
    Join-Path $ScriptRoot 'state/operator-seal.json'
}
function Get-BISFOperatorSealTaskMarker {
    param([string]$ScriptRoot,[string]$ConfigPath)
    'BISF-Local/OperatorSeal/v1 | {0} | {1}' -f $ScriptRoot,$ConfigPath
}
function Get-BISFOperatorSealTaskArguments {
    param([string]$ScriptPath,[string]$ConfigPath)
    if (@($ScriptPath,$ConfigPath | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -match '["\r\n]' }).Count -gt 0) {
        throw 'Invalid operator-seal task paths.'
    }
    '-NoProfile -NonInteractive -File "{0}" -Mode Finalize -ConfigPath "{1}"' -f $ScriptPath,$ConfigPath
}
function Test-BISFOperatorSealTaskOwnership {
    param([string]$ScriptRoot,[string]$ConfigPath)
    # Enumerate successfully before treating the reserved root task as absent.
    # Filtering after enumeration avoids using a missing-task lookup error as
    # an excuse to suppress Task Scheduler/RPC/access failures.
    $existing=@(Get-ScheduledTask -ErrorAction Stop | Where-Object {
        $_.TaskName -eq 'BISF-Local-OperatorSeal' -and $_.TaskPath -eq '\'
    })
    if ($existing.Count -gt 0) {
        $expected=Get-BISFOperatorSealTaskMarker $ScriptRoot $ConfigPath
        $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $args=Get-BISFOperatorSealTaskArguments (Join-Path $ScriptRoot 'Invoke-BISF.ps1') $ConfigPath
        if ($existing.Count -ne 1 -or $existing[0].Description -ne $expected -or
            @($existing[0].Actions).Count -ne 1 -or $existing[0].Actions[0].Execute -ne $exe -or
            $existing[0].Actions[0].Arguments -ne $args -or
            $existing[0].Principal.UserId -notin @('SYSTEM','S-1-5-18')) {
            throw 'Refusing an existing operator-seal task that is not owned by this package.'
        }
        throw 'A previous BISF operator-seal task already exists. Resolve or cancel the previous sealing attempt before retrying.'
    }
}
function New-BISFOperatorSealState {
    param($Config,$Target,[string]$ConfigPath,[string]$ExpectedHash)
    if ($ExpectedHash -notmatch '^[A-Fa-f0-9]{64}$' -or
        (Get-BISFFileHash -LiteralPath $ConfigPath).Hash -ne $ExpectedHash) {
        throw 'Configuration changed before operator staging or no confirmed hash was supplied.'
    }
    [pscustomobject]@{
        SchemaVersion=1
        Generation=[guid]::NewGuid().ToString()
        Status='Pending'
        ConfigHash=$ExpectedHash
        Master=Get-BISFIdentity
        OperatorSid=$Target.SID
        OperatorPath=$Target.Path
        ProfilesRoot=$Target.Root
        TimeoutMinutes=[int]$Config.Finalization.TimeoutMinutes
        StagedUtc=[datetime]::UtcNow.ToString('o')
    }
}
function Test-BISFOperatorSealStaging {
    param([string]$ScriptRoot,[string]$ConfigPath,$Config)
    foreach ($path in @($ScriptRoot,$ConfigPath,(Join-Path $ScriptRoot 'Invoke-BISF.ps1'),
            (Join-Path $ScriptRoot 'GlobalConfig.xsd'),(Join-Path $ScriptRoot 'Modules'),(Join-Path $ScriptRoot 'state'))) {
        Test-BISFProtectedLocation $path
    }
    if ($Config.Logging.Enabled) { Test-BISFProtectedLocation $Config.Logging.Path }
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $ScriptRoot 'Modules') -Recurse -Force -ErrorAction Stop) {
        Test-BISFProtectedLocation $f.FullName
    }
    Test-BISFOperatorSealTaskOwnership $ScriptRoot $ConfigPath
    $statePath=Get-BISFOperatorSealStatePath $ScriptRoot
    Test-BISFProtectedLocation $statePath
    if (Test-Path -LiteralPath $statePath) {
        throw 'Existing operator-seal state detected. Resolve the earlier sealing attempt.'
    }
}
function Register-BISFOperatorSeal {
    param([string]$ScriptRoot,[string]$ConfigPath,$Config,$Target,[string]$ExpectedHash)
    # Repeat preflight immediately before staging; never repair/overwrite a prior run.
    Test-BISFOperatorSealStaging $ScriptRoot $ConfigPath $Config
    $statePath=Get-BISFOperatorSealStatePath $ScriptRoot
    $state=New-BISFOperatorSealState $Config $Target $ConfigPath $ExpectedHash
    $registered=$false
    try {
        Write-BISFState $statePath $state
        $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $script=Join-Path $ScriptRoot 'Invoke-BISF.ps1'
        $action=New-ScheduledTaskAction -Execute $exe -Argument (Get-BISFOperatorSealTaskArguments $script $ConfigPath) -WorkingDirectory $ScriptRoot
        $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        $minutes=[int]$Config.Finalization.TimeoutMinutes
        $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes ($minutes+5)) -StartWhenAvailable
        # No trigger: job is started deliberately once by successful Prepare.
        $null=Register-ScheduledTask -TaskName 'BISF-Local-OperatorSeal' -TaskPath '\' -Action $action -Principal $principal -Settings $settings -Description (Get-BISFOperatorSealTaskMarker $ScriptRoot $ConfigPath) -ErrorAction Stop
        $registered=$true
        Start-ScheduledTask -TaskName 'BISF-Local-OperatorSeal' -TaskPath '\' -ErrorAction Stop
    } catch {
        $errorObject=$_
        if ($registered) {
            try { Unregister-ScheduledTask -TaskName 'BISF-Local-OperatorSeal' -TaskPath '\' -Confirm:$false -ErrorAction Stop }
            catch { Write-Warning "Could not unregister failed operator-seal task: $($_.Exception.Message)" }
        }
        try {
            if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop }
        } catch { Write-Warning "Could not clean up failed operator-seal state: $($_.Exception.Message)" }
        throw $errorObject
    }
}
function Read-BISFOperatorSealState {
    param([string]$ScriptRoot)
    $path=Get-BISFOperatorSealStatePath $ScriptRoot
    Test-BISFProtectedLocation $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'No staged operator seal state.' }
    $state=Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    foreach ($field in @('SchemaVersion','Generation','Status','ConfigHash','Master','OperatorSid','OperatorPath','ProfilesRoot','TimeoutMinutes','StagedUtc')) {
        if ($null -eq $state.PSObject.Properties[$field]) { throw "Operator seal state missing $field" }
    }
    if ($state.SchemaVersion -ne 1 -or -not (Test-BISFValidGuid $state.Generation) -or
        $state.Status -ne 'Pending' -or $state.ConfigHash -notmatch '^[A-Fa-f0-9]{64}$' -or
        [int]$state.TimeoutMinutes -lt 1 -or [int]$state.TimeoutMinutes -gt 90 -or
        $state.OperatorSid -notmatch '^S-1-5-21-([0-9]+-){3}[0-9]+$') {
        throw 'Operator seal state invalid or not pending.'
    }
    $state
}
function Test-BISFOperatorSealCandidate {
    param($State,$Config)
    if ([string](Get-BISFCurrentUserSid) -ne 'S-1-5-18') {
        throw 'Operator seal Finalize must run as NT AUTHORITY\SYSTEM.'
    }
    if (-not $Config.Finalization.RemoveOperatorProfile -or $Config.FinalAction -ne 'Shutdown') {
        throw 'Operator seal was disabled or shutdown no longer approved.'
    }
    if ($State.ConfigHash -ne (Get-BISFFileHash -LiteralPath $Config.Path).Hash) {
        throw 'Configuration changed since staging operator seal.'
    }
    $identity=Get-BISFIdentity
    foreach ($field in @('Name','MachineGuid','SmbiosUuid')) {
        if ($identity.$field -ne $State.Master.$field) { throw 'Operator seal refused: machine identity changed; never run finalization on an MCS clone.' }
    }
    $root=Get-BISFProfilesRoot
    if ($root -ne $State.ProfilesRoot) { throw 'Windows profile root changed after staging.' }
    $others=@(Get-BISFLoadedNonSystemProfiles '')
    if ($others.Count -gt 0) { return $false }
    (Get-BISFOperatorSealProfile $State $Config).Ready
}
function Get-BISFOperatorSealProfile {
    param($State,$Config)
    # Return the exact checked CIM object for deletion. Never validate one query
    # and then delete an unchecked replacement returned by a later query.
    $root=Get-BISFProfilesRoot
    if ($root -ne $State.ProfilesRoot) { throw 'Windows profile root changed after staging.' }
    $profiles=@(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$($State.OperatorSid)'" -ErrorAction Stop)
    if ($profiles.Count -ne 1) { throw 'Operator profile missing or ambiguous.' }
    $p=$profiles[0]
    if ([string]$p.SID -ne [string]$State.OperatorSid -or [string]$p.LocalPath -ne [string]$State.OperatorPath) {
        throw 'Operator profile no longer matches the staged SID and local path.'
    }
    if ($null -eq $p.PSObject.Properties['Loaded'] -or $null -eq $p.PSObject.Properties['Special'] -or
        $null -eq $p.Loaded -or $null -eq $p.Special -or $p.Special) {
        throw 'Operator profile flags are missing or special; refusing deletion.'
    }
    if ($State.OperatorSid -in $Config.Cleanup.ExcludedProfileSIDs) { throw 'Operator SID is excluded from cleanup.' }
    if (-not (Test-BISFDirectProfilePath $p.LocalPath $root) -or -not (Test-Path -LiteralPath $p.LocalPath -PathType Container)) {
        throw 'Operator profile directory is missing or outside the registered profile root.'
    }
    $leaf=[IO.Path]::GetFileName(([string]$p.LocalPath).TrimEnd([char[]]'\/'))
    if ($leaf -match '^(Default|Default User|Public|All Users|defaultuser0|WDAGUtilityAccount)$') {
        throw 'Operator profile points at a reserved Windows template directory.'
    }
    # A normal admin SID (RID >= 1000) is allowed to have an Administrator-named
    # profile folder; the generic cleanup continues protecting such folders.
    if ($State.OperatorSid -notmatch '^S-1-5-21-([0-9]+-){3}([0-9]+)$' -or [long]$Matches[2] -lt 1000) {
        throw 'Operator SID is built-in or no longer eligible for deferred deletion.'
    }
    $busy=($p.Loaded -or ($null -ne $p.PSObject.Properties['RefCount'] -and
        $null -ne $p.RefCount -and [long]$p.RefCount -gt 0))
    Test-BISFNoReparsePath $p.LocalPath
    [pscustomobject]@{Ready=(-not $busy);Profile=$p}
}
function Invoke-BISFOperatorSealFinalizer {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
    param([string]$ScriptRoot,[string]$ConfigPath)
    if (-not $PSCmdlet.ShouldProcess($ScriptRoot,'Remove staged operator profile, clean selected logs and shut down')) { return 0 }
    # Do not use the interactive Prepare runner or its startup task here.
    $ScriptRoot=[IO.Path]::GetFullPath($ScriptRoot)
    $ConfigPath=Resolve-BISFPath $ConfigPath $ScriptRoot
    $config=Read-BISFConfig $ConfigPath $ScriptRoot
    # Binding avoids passing an arbitrary path from the state file as code.
    $config | Add-Member NoteProperty Path $ConfigPath
    Test-BISFOperatorSealSettings $config
    $state=Read-BISFOperatorSealState $ScriptRoot
    $logger=New-BISFLogger $config 'Finalize'
    $lock=$null
    try {
        $deadline=[datetime]::UtcNow.AddMinutes([int]$state.TimeoutMinutes)
        Write-BISFLog $logger Info Finalize 'SYSTEM finalizer started; waiting for the administrator to sign out normally. No forced logoff will be used.'
        $ready=$false
        while ([datetime]::UtcNow -lt $deadline) {
            if (Test-BISFOperatorSealCandidate $state $config) { $ready=$true; break }
            Start-Sleep -Seconds 10
        }
        if (-not $ready) { throw 'Operator profile did not fully unload before timeout; shutdown is refused.' }
        $lock=Enter-BISFLock
        # The original Prepare must have committed; no incomplete master journal.
        $journals=Get-BISFJournalStatus $ScriptRoot
        if ($journals.PreparationPending) { throw 'Incomplete Prepare journal: shutdown is refused.' }
        if (@(Get-BISFPendingRebootReasons).Count -gt 0) { throw 'Pending reboot reappeared: shutdown is refused.' }
        if (-not (Test-BISFOperatorSealCandidate $state $config)) { throw 'Profile state changed just before deletion; shutdown refused.' }
        $target=Get-BISFOperatorSealProfile $state $config
        if (-not $target.Ready) { throw 'Operator profile became busy before final deletion; shutdown refused.' }
        Remove-BISFCimUserProfile $target.Profile
        if (@(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$($state.OperatorSid)'" -ErrorAction Stop).Count -gt 0) {
            throw 'Windows still reports the operator profile after deletion.'
        }
        Write-BISFLog $logger Info Finalize ("Operator profile removed: SID={0}; local path={1}" -f $state.OperatorSid,$state.OperatorPath)
        # No restart/shutdown unless registration is cleaned and the pending state
        # is consumed. If cleanup fails, manual recovery is required.
        Unregister-ScheduledTask -TaskName 'BISF-Local-OperatorSeal' -TaskPath '\' -Confirm:$false -ErrorAction Stop
        $statePath=Get-BISFOperatorSealStatePath $ScriptRoot
        Test-BISFProtectedLocation $statePath
        Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop
        Write-BISFLog $logger Info Finalize 'Operator cleanup and staging-state removal succeeded; optional last-stage log cleanup follows. Requesting shutdown afterwards.'
        # Do not write diagnostics between successful log deletion and shutdown.
        # A failed cleanup refuses shutdown and writes an error to the log.
        Invoke-BISFLogCleanup $config
        Stop-Computer -Confirm:$false -ErrorAction Stop
        return 0
    } catch {
        try { Write-BISFLog $logger Error Finalize $_.Exception.Message } catch { Write-Warning $_.Exception.Message }
        return 2
    } finally {
        Exit-BISFLock $lock
        Close-BISFLogger $logger
    }
}

