# BIS-F Local — opt-in image maintenance and read-only pre-capture diagnostics.
# Uses only PowerShell/CIM and Microsoft-built-in Windows scheduled tasks.

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
    @(
        Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
            Where-Object {
                $_.Special -eq $false -and $_.Loaded -eq $true -and
                -not [string]::IsNullOrWhiteSpace([string]$_.SID) -and
                [string]$_.SID -ne $CurrentSid
            }
    )
}
function Get-BISFProfileManagementServices {
    @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
        Where-Object { $_.Name -match '^(frxsvc|ctxprofile)$' -or $_.DisplayName -match '^Citrix Profile Management' } |
        Select-Object Name,DisplayName,State,StartMode)
}
function Get-BISFComponentCleanupTask {
    $task=@(Get-ScheduledTask -TaskPath '\Microsoft\Windows\Servicing\' -TaskName 'StartComponentCleanup' -ErrorAction Stop)
    if ($task.Count -ne 1 -or $task[0].TaskName -ne 'StartComponentCleanup' -or
        $task[0].TaskPath -ne '\Microsoft\Windows\Servicing\') {
        throw 'Expected one Microsoft Windows Servicing StartComponentCleanup task.'
    }
    if ($task[0].State -in @('Disabled','Running')) {
        throw "Servicing StartComponentCleanup task not ready: $($task[0].State)"
    }
    $task[0]
}
function Invoke-BISFComponentCleanup {
    param([int]$TimeoutMinutes,$Logger)
    # The built-in task honors Windows Servicing's component-management rules,
    # unlike deleting files under WinSxS/SoftwareDistribution. No ResetBase.
    $task=Get-BISFComponentCleanupTask
    $begin=[datetime]::Now.AddSeconds(-5)
    Write-BISFLog $Logger Info Servicing 'Starting built-in Microsoft Windows Servicing StartComponentCleanup scheduled task.'
    Start-ScheduledTask -InputObject $task -ErrorAction Stop
    $deadline=[datetime]::UtcNow.AddMinutes($TimeoutMinutes)
    $started=$false
    while ([datetime]::UtcNow -lt $deadline) {
        $current=Get-ScheduledTask -TaskName 'StartComponentCleanup' -TaskPath '\Microsoft\Windows\Servicing\' -ErrorAction Stop
        $info=Get-ScheduledTaskInfo -TaskName 'StartComponentCleanup' -TaskPath '\Microsoft\Windows\Servicing\' -ErrorAction Stop
        if ($null -ne $info.LastRunTime -and [datetime]$info.LastRunTime -ge $begin) { $started=$true }
        if ($started -and [string]$current.State -ne 'Running') {
            if ([int]$info.LastTaskResult -ne 0) {
                throw "Servicing component cleanup returned Task Scheduler result $($info.LastTaskResult)."
            }
            Write-BISFLog $Logger Info Servicing 'Built-in component cleanup completed successfully.'
            return
        }
        Start-Sleep -Seconds 10
    }
    throw "Servicing component cleanup exceeded $TimeoutMinutes minutes; refusing further image preparation."
}
function Invoke-BISFRecycleBinCleanup {
    param($Logger)
    $drive=[string]$env:SystemDrive
    if ($drive -notmatch '^[A-Za-z]:$') { throw 'SystemDrive must be a local DOS drive.' }
    Clear-RecycleBin -DriveLetter $drive.Substring(0,1) -Force -Confirm:$false -ErrorAction Stop
    Write-BISFLog $Logger Info RecycleBin "Requested Windows Recycle Bin cleanup for $drive through Clear-RecycleBin."
}
