# BIS-F Local — opt-in image maintenance and read-only pre-capture diagnostics.
# Uses only PowerShell/CIM and the inbox Microsoft DISM PowerShell cmdlet.

function Get-BISFPendingRebootReasons {
    $reasons=New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons.Add('CBS RebootPending') }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons.Add('Windows Update RebootRequired') }
    $session=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
    if ($null -ne $session.PSObject.Properties['PendingFileRenameOperations'] -and
        @($session.PendingFileRenameOperations).Count -gt 0) {
        $reasons.Add('PendingFileRenameOperations')
    }
    $reasons.ToArray()
}
function Get-BISFSystemDriveStatus {
    $drive=[string]$env:SystemDrive
    if ($drive -notmatch '^[A-Za-z]:$') { throw 'SystemDrive must be a local DOS drive.' }
    $disks=@(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction Stop)
    if ($disks.Count -ne 1 -or $null -eq $disks[0].FreeSpace -or $null -eq $disks[0].Size) {
        throw "System drive $drive could not be measured."
    }
    [pscustomobject]@{
        Drive=$drive
        FreeGB=[math]::Round(([double]$disks[0].FreeSpace / 1GB),2)
        TotalGB=[math]::Round(([double]$disks[0].Size / 1GB),2)
    }
}
function Get-BISFLoadedNonSystemProfiles {
    param([string]$CurrentSid)
    foreach ($profile in Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop) {
        if ($null -eq $profile.PSObject.Properties['Special'] -or $null -eq $profile.Special) {
            throw 'Unknown Windows profile lifecycle flags.'
        }
        if ($profile.Special) { continue }
        if ($null -eq $profile.PSObject.Properties['SID'] -or [string]::IsNullOrWhiteSpace([string]$profile.SID) -or
            $null -eq $profile.PSObject.Properties['Loaded'] -or $null -eq $profile.Loaded) {
            throw 'Unknown Windows profile lifecycle identity or loaded state.'
        }
        if ([string]$profile.SID -eq $CurrentSid) { continue }
        $referenced=($null -ne $profile.PSObject.Properties['RefCount'] -and
            $null -ne $profile.RefCount -and [long]$profile.RefCount -gt 0)
        if ($profile.Loaded -or $referenced) { $profile }
    }
}
function Test-BISFPreparationProfiles {
    param($Config)
    if ($Config.Preflight.BlockOtherLoadedProfiles -and
        @(Get-BISFLoadedNonSystemProfiles (Get-BISFCurrentUserSid)).Count -gt 0) {
        throw 'Other loaded or referenced local user profiles appeared; preparation and shutdown are refused.'
    }
}
function Get-BISFProfileManagementServices {
    @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
        Where-Object { $_.Name -match '^(frxsvc|ctxprofile)$' -or $_.DisplayName -match '^Citrix Profile Management' } |
        Select-Object Name,DisplayName,State,StartMode)
}
function Get-BISFDismModulePath {
    $system=[Environment]::GetFolderPath([Environment+SpecialFolder]::System)
    if ([string]::IsNullOrWhiteSpace($system) -or -not [IO.Path]::IsPathRooted($system)) {
        throw 'Cannot locate the Windows system directory for the inbox DISM module.'
    }
    Join-Path $system 'WindowsPowerShell/v1.0/Modules/Dism/Dism.psd1'
}
function Get-BISFComponentCleanupCapability {
    $manifest=Get-BISFDismModulePath
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf -ErrorAction Stop)) {
        throw 'Required inbox DISM PowerShell module is missing.'
    }
    Test-BISFNoReparsePath $manifest
    $expectedBase=[IO.Path]::GetFullPath((Split-Path $manifest -Parent)).TrimEnd([char[]]'\/')
    $modules=@(Import-Module -Name $manifest -PassThru -Force -ErrorAction Stop)
    # The exact manifest is imported above, but PowerShell can report its trusted
    # script or binary RootModule as Path instead of the manifest itself.
    if ($modules.Count -ne 1 -or $modules[0].Name -ne 'Dism' -or
        -not ([IO.Path]::GetFullPath([string]$modules[0].ModuleBase).TrimEnd([char[]]'\/')).Equals($expectedBase,[StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$modules[0].Path)).TrimEnd([char[]]'\/')).Equals($expectedBase,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Loaded module does not match the fixed inbox DISM source.'
    }
    $commands=@(Get-Command -Name 'Dism\Repair-WindowsImage' -CommandType Cmdlet -ErrorAction Stop)
    if ($commands.Count -ne 1 -or [string]$commands[0].CommandType -ne 'Cmdlet' -or
        $commands[0].Name -ne 'Repair-WindowsImage' -or $commands[0].ModuleName -ne 'Dism') {
        throw 'Required inbox DISM Repair-WindowsImage cmdlet is unavailable.'
    }
    $command=$commands[0]
    # Exported binary cmdlets may report the DLL rather than the manifest path.
    if ($null -eq $command.Module -or
        -not ([IO.Path]::GetFullPath([string]$command.Module.ModuleBase).TrimEnd([char[]]'\/')).Equals($expectedBase,[StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$command.Module.Path)).TrimEnd([char[]]'\/')).Equals($expectedBase,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Repair-WindowsImage is not from the fixed inbox DISM directory.'
    }
    foreach ($required in 'Online','StartComponentCleanup','NoRestart','LimitAccess') {
        if ($null -eq $command.Parameters -or -not $command.Parameters.ContainsKey($required)) {
            throw "Inbox DISM Repair-WindowsImage lacks required $required capability; this Windows image cannot use component cleanup."
        }
    }
    $command
}
function Get-BISFComponentCleanupElapsedMinutes {
    param([Diagnostics.Stopwatch]$Stopwatch)
    $Stopwatch.Elapsed.TotalMinutes
}
function Invoke-BISFComponentCleanup {
    param([ValidateRange(1,2147483647)][int]$TimeoutMinutes,$Logger)
    # Never infer completion from Task Scheduler summaries or remove servicing
    # files directly. DISM returns synchronously; no ResetBase or repair source.
    $null=Get-BISFComponentCleanupCapability
    if (@(Get-BISFPendingRebootReasons).Count -gt 0) {
        throw 'A pending reboot blocks component cleanup; reboot the master and retry.'
    }
    Write-BISFLog $Logger Info Servicing ("Starting synchronous inbox DISM component cleanup. Servicing is not interrupted; the {0}-minute completion budget is checked only after DISM returns. No automatic restart or Windows Update access is allowed." -f $TimeoutMinutes)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $result=@(Dism\Repair-WindowsImage -Online -StartComponentCleanup -NoRestart -LimitAccess -ErrorAction Stop)
        $watch.Stop()
        $elapsed=Get-BISFComponentCleanupElapsedMinutes $watch
        if ($elapsed -gt $TimeoutMinutes) {
            throw "Servicing component cleanup exceeded the $TimeoutMinutes-minute completion budget after returning; refusing further image preparation. The operation was not interrupted or cancelled."
        }
        if ($result.Count -ne 1 -or $null -eq $result[0]) {
            throw 'DISM component cleanup did not return exactly one completion result.'
        }
        $image=$result[0]
        $online=$image.PSObject.Properties['Online']
        $restart=$image.PSObject.Properties['RestartNeeded']
        if ($null -eq $online -or $null -eq $restart -or
            $online.Value -isnot [bool] -or $restart.Value -isnot [bool]) {
            throw 'DISM component cleanup returned malformed Online/RestartNeeded completion evidence.'
        }
        if (-not $online.Value) { throw 'DISM component cleanup did not confirm the online Windows image.' }
        if ($restart.Value) { throw 'DISM component cleanup requires a reboot; further preparation and shutdown are refused.' }
        # This operation-specific gate always applies, even when the generic
        # Preflight.BlockPendingReboot setting was disabled by the operator.
        if (@(Get-BISFPendingRebootReasons).Count -gt 0) {
            throw 'A pending reboot appeared after DISM component cleanup; further preparation and shutdown are refused.'
        }
        Write-BISFLog $Logger Info Servicing ("DISM component cleanup completed successfully in {0:N2} minutes; the online image reported no restart requirement." -f $elapsed)
    } finally { $watch.Stop() }
}
function Invoke-BISFRecycleBinCleanup {
    param($Logger)
    $drive=[string]$env:SystemDrive
    if ($drive -notmatch '^[A-Za-z]:$') { throw 'SystemDrive must be a local DOS drive.' }
    Clear-RecycleBin -DriveLetter $drive.Substring(0,1) -Force -Confirm:$false -ErrorAction Stop
    Write-BISFLog $Logger Info RecycleBin "Requested Windows Recycle Bin cleanup for $drive through Clear-RecycleBin."
}

