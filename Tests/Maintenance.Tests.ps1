BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Preflight','Maintenance','Logging') { . "$root/Modules/Private/$n.ps1" }
}
Describe 'Read-only pre-capture health inventory' {
    It 'reports free space for the local system drive using CIM only' {
        Mock Get-CimInstance { [pscustomobject]@{Size=120GB;FreeSpace=24GB} }
        $orig=$env:SystemDrive
        try {
            $env:SystemDrive='C:'
            $r=Get-BISFSystemDriveStatus
            $r.Drive | Should -Be 'C:'
            $r.FreeGB | Should -Be 24
            $r.TotalGB | Should -Be 120
            Should -Invoke Get-CimInstance -Times 1 -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }
        } finally { $env:SystemDrive=$orig }
    }
    It 'refuses a system drive whose capacity cannot be measured' {
        Mock Get-CimInstance { @() }
        { Get-BISFSystemDriveStatus } | Should -Throw '*could not be measured*'
    }
    It 'reports all reboot reasons, including pending file renames' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { [pscustomobject]@{PendingFileRenameOperations=@('\??\C:\temp\file')} }
        $r=@(Get-BISFPendingRebootReasons)
        $r | Should -Contain 'CBS RebootPending'
        $r | Should -Contain 'Windows Update RebootRequired'
        $r | Should -Contain 'PendingFileRenameOperations'
    }
    It 'does not report a pending reboot when all indicators are clear' {
        Mock Test-Path { $false }
        Mock Get-ItemProperty { [pscustomobject]@{} }
        @(Get-BISFPendingRebootReasons).Count | Should -Be 0
    }
    It 'treats an unloaded profile with outstanding references as busy' {
        Mock Get-CimInstance { [pscustomobject]@{SID='S-1-5-21-1-2-3-1011';Loaded=$false;Special=$false;RefCount=1} }
        @(Get-BISFLoadedNonSystemProfiles '').Count | Should -Be 1
    }
    It 'fails closed on unknown lifecycle state for another profile' {
        Mock Get-CimInstance { [pscustomobject]@{SID='S-1-5-21-1-2-3-1011';Loaded=$null;Special=$false} }
        { Get-BISFLoadedNonSystemProfiles '' } | Should -Throw '*lifecycle*'
    }
    It 'reports other loaded user profiles while ignoring the current user and special accounts' {
        Mock Get-CimInstance { @(
            [pscustomobject]@{SID='S-1-5-21-1-2-3-1010';Loaded=$true;Special=$false},
            [pscustomobject]@{SID='S-1-5-21-1-2-3-1011';Loaded=$true;Special=$false},
            [pscustomobject]@{SID='S-1-5-18';Loaded=$true;Special=$true}
        ) }
        $r=@(Get-BISFLoadedNonSystemProfiles 'S-1-5-21-1-2-3-1010')
        $r.Count | Should -Be 1
        $r[0].SID | Should -Be 'S-1-5-21-1-2-3-1011'
    }
}
Describe 'Windows component store cleanup through Microsoft Servicing task' {
    BeforeEach {
        $script:task=[pscustomobject]@{TaskName='StartComponentCleanup';TaskPath='\Microsoft\Windows\Servicing\';State='Ready'}
        Mock Get-ScheduledTask { $script:task }
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{LastRunTime=[datetime]::Now;LastTaskResult=0} }
        Mock Start-ScheduledTask {}
        Mock Start-Sleep {}
        Mock Write-BISFLog {}
    }
    It 'locates the exact built-in Servicing task, not a custom task' {
        $t=Get-BISFComponentCleanupTask
        $t.TaskName | Should -Be 'StartComponentCleanup'
        Should -Invoke Get-ScheduledTask -Times 1 -ParameterFilter { $TaskPath -eq '\Microsoft\Windows\Servicing\' }
    }
    It 'refuses to run a disabled or already-running servicing task' {
        $script:task.State='Disabled'
        { Get-BISFComponentCleanupTask } | Should -Throw '*not ready*'
        $script:task.State='Running'
        { Get-BISFComponentCleanupTask } | Should -Throw '*not ready*'
    }
    It 'fails closed if the task name or task location was changed' {
        $script:task.TaskName='OtherTask'
        { Get-BISFComponentCleanupTask } | Should -Throw '*Expected one*'
        $script:task.TaskName='StartComponentCleanup'
        $script:task.TaskPath='\Other\'
        { Get-BISFComponentCleanupTask } | Should -Throw '*Expected one*'
    }
    It 'successfully starts and awaits a completed servicing maintenance task' {
        $script:infoReads=0
        Mock Get-ScheduledTaskInfo {
            $script:infoReads++
            $last=if ($script:infoReads -eq 1) { [datetime]::Now.AddMinutes(-1) } else { [datetime]::Now }
            [pscustomobject]@{LastRunTime=$last;LastTaskResult=0}
        }
        Invoke-BISFComponentCleanup 2 $null
        Should -Invoke Start-ScheduledTask -Times 1
        Should -Invoke Get-ScheduledTaskInfo -Times 2
    }
    It 'surfaces an error result and refuses a successful seal' {
        $script:infoReads=0
        Mock Get-ScheduledTaskInfo {
            $script:infoReads++
            $last=if ($script:infoReads -eq 1) { [datetime]::Now.AddMinutes(-1) } else { [datetime]::Now }
            [pscustomobject]@{LastRunTime=$last;LastTaskResult=123}
        }
        { Invoke-BISFComponentCleanup 2 $null } | Should -Throw '*result 123*'
    }
    It 'waits for a new run instead of accepting a recent previous success or a queued task' {
        $script:infoReads=0
        $script:recent=[datetime]::Now.AddSeconds(-1)
        $script:newRun=[datetime]::Now
        Mock Get-ScheduledTask {
            $status=if ($script:infoReads -eq 1) { 'Queued' } elseif ($script:infoReads -eq 2) { 'Running' } else { 'Ready' }
            [pscustomobject]@{TaskName='StartComponentCleanup';TaskPath='\Microsoft\Windows\Servicing\';State=$status}
        }
        Mock Get-ScheduledTaskInfo {
            $script:infoReads++
            $last=if ($script:infoReads -le 2) { $script:recent } else { $script:newRun }
            [pscustomobject]@{LastRunTime=$last;LastTaskResult=0}
        }
        Invoke-BISFComponentCleanup 2 $null
        $script:infoReads | Should -Be 4
        Should -Invoke Start-Sleep -Times 2
    }
    It 'times out without proceeding if servicing never starts' {
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{LastRunTime=[datetime]'2000-01-01';LastTaskResult=0} }
        { Invoke-BISFComponentCleanup 0 $null } | Should -Throw '*exceeded*'
    }
}
Describe 'System drive Recycle Bin cleanup opt in' {
    It 'calls Clear-RecycleBin only for the Windows system drive when explicitly invoked' {
        Mock Clear-RecycleBin {}
        Mock Write-BISFLog {}
        $orig=$env:SystemDrive
        try {
            $env:SystemDrive='C:'
            Invoke-BISFRecycleBinCleanup $null
            Should -Invoke Clear-RecycleBin -Times 1 -ParameterFilter { $DriveLetter -eq 'C' -and $Force -and $Confirm -eq $false }
        } finally { $env:SystemDrive=$orig }
    }
}

