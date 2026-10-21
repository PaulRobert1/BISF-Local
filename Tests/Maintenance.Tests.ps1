BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Configuration','Operations','Preflight','Maintenance','Logging','Finalization') { . "$root/Modules/Private/$n.ps1" }
    # Test-only command signatures let Pester mock Windows dependencies on Linux.
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { [CmdletBinding()]param($ClassName,$Filter) throw 'Unmocked Windows CIM operation' }
    }
    if (-not (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue)) {
        function Clear-RecycleBin { [CmdletBinding(SupportsShouldProcess=$true)]param($DriveLetter,[switch]$Force) throw 'Unmocked Windows Recycle Bin operation' }
    }
    $script:createdDismTestModule=$false
    $installedDismCommand=Get-Command 'Dism\Repair-WindowsImage' -ErrorAction SilentlyContinue
    $script:originalDismModules=@(Get-Module -Name Dism)
    $needsDismTestModule=($null -eq $installedDismCommand)
    foreach ($required in 'Online','StartComponentCleanup','NoRestart','LimitAccess') {
        if ($null -eq $installedDismCommand -or -not $installedDismCommand.Parameters.ContainsKey($required)) {
            $needsDismTestModule=$true
        }
    }
    if ($needsDismTestModule) {
        # Older Windows DISM command metadata also needs the test-only signature:
        # mocking capability must not leave the unit tests bound to old switches.
        if ($script:originalDismModules.Count) { Remove-Module -ModuleInfo $script:originalDismModules -Force }
        New-Module -Name Dism -ScriptBlock {
            function Repair-WindowsImage {
                [CmdletBinding()]
                param([switch]$Online,[switch]$StartComponentCleanup,[switch]$NoRestart,[switch]$LimitAccess,
                    [switch]$ResetBase,[switch]$Defer,[switch]$RestoreHealth,$Source)
                throw 'Unmocked Windows servicing operation'
            }
            Export-ModuleMember -Function Repair-WindowsImage
        } | Import-Module -Global -Force
        $script:createdDismTestModule=$true
    }
}
AfterAll {
    if ($script:createdDismTestModule) {
        Remove-Module Dism -Force
        foreach ($module in $script:originalDismModules) { Import-Module -ModuleInfo $module -Global -Force }
    }
}
Describe 'Read-only pre-capture health inventory' {
    BeforeEach { $script:originalSystemDrive=$env:SystemDrive; $env:SystemDrive='C:' }
    AfterEach { $env:SystemDrive=$script:originalSystemDrive }
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
Describe 'Inbox DISM component cleanup capability' {
    BeforeEach {
        $script:inboxManifest=Join-Path $TestDrive 'System32/WindowsPowerShell/v1.0/Modules/Dism/Dism.psd1'
        $script:inboxBase=Split-Path $script:inboxManifest -Parent
        $script:inboxModule=[pscustomobject]@{Name='Dism';ModuleBase=$script:inboxBase;Path=$script:inboxManifest}
        $script:binaryModule=[pscustomobject]@{Name='Dism';ModuleBase=$script:inboxBase;Path=(Join-Path $script:inboxBase 'Microsoft.Dism.PowerShell.dll')}
        $script:cleanupCommand=[pscustomobject]@{
            Name='Repair-WindowsImage';CommandType='Cmdlet';ModuleName='Dism';Module=$script:binaryModule
            Parameters=@{Online=$null;StartComponentCleanup=$null;NoRestart=$null;LimitAccess=$null}
        }
        Mock Get-BISFDismModulePath { $script:inboxManifest }
        Mock Test-BISFNoReparsePath {}
        Mock Test-Path { $true }
        Mock Import-Module { $script:inboxModule }
        Mock Get-Command { $script:cleanupCommand }
    }
    It 'loads only the fixed inbox manifest and verifies the module-qualified cmdlet' {
        $null=Get-BISFComponentCleanupCapability
        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq $script:inboxManifest -and $PassThru }
        Should -Invoke Get-Command -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Dism\Repair-WindowsImage' -and $CommandType -eq 'Cmdlet'
        }
    }
    It 'rejects an absent inbox module before loading another copy' {
        Mock Test-Path { $false }
        { Get-BISFComponentCleanupCapability } | Should -Throw '*inbox DISM*'
        Should -Invoke Import-Module -Times 0 -Exactly
    }
    It 'accepts trusted inbox root-module metadata reported as <RootFile>' -ForEach @(
        @{RootFile='Dism.psm1'},@{RootFile='Microsoft.Dism.PowerShell.dll'}
    ) {
        $script:inboxModule.Path=Join-Path $script:inboxBase $RootFile
        { $null=Get-BISFComponentCleanupCapability } | Should -Not -Throw
        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq $script:inboxManifest }
    }
    It 'rejects a root module reporting a path outside the trusted inbox directory' {
        $script:inboxModule.Path=Join-Path $TestDrive 'other/Dism.psm1'
        { Get-BISFComponentCleanupCapability } | Should -Throw '*inbox DISM*'
    }
    It 'propagates module load failures rather than falling back to another source' {
        Mock Import-Module { throw 'Inbox DISM unavailable' }
        { Get-BISFComponentCleanupCapability } | Should -Throw '*Inbox DISM unavailable*'
    }
    It 'rejects a module loaded from outside the fixed system source' {
        $script:inboxModule.ModuleBase=Join-Path $TestDrive 'other'
        { Get-BISFComponentCleanupCapability } | Should -Throw '*inbox DISM*'
    }
    It 'rejects a function impersonating the native cmdlet' {
        $script:cleanupCommand.CommandType='Function'
        { Get-BISFComponentCleanupCapability } | Should -Throw '*cmdlet*'
    }
    It 'rejects an exported command whose implementing module is outside the inbox directory' {
        $script:binaryModule.Path=Join-Path $TestDrive 'other/Microsoft.Dism.PowerShell.dll'
        { Get-BISFComponentCleanupCapability } | Should -Throw '*inbox DISM*'
    }
    It 'rejects an older DISM command lacking <Required> capability' -ForEach @(
        @{Required='Online'},@{Required='StartComponentCleanup'},@{Required='NoRestart'},@{Required='LimitAccess'}
    ) {
        $script:cleanupCommand.Parameters.Remove($Required)
        { Get-BISFComponentCleanupCapability } | Should -Throw "*$Required*"
    }
    It 'checks the capability during read-only preparation preflight' {
        Mock Test-BISFPlatform {}
        Mock Test-Path { $false }
        Mock Get-BISFComponentCleanupCapability {}
        $c=Read-BISFConfig (Join-Path $root 'Tests/Fixtures/OptInBaseline.xml') $root
        $c.Preflight.BlockOtherLoadedProfiles=$false
        Test-BISFPreflight $c Validate @([pscustomobject]@{Id='Servicing'}) $root (Join-Path $root 'Tests/Fixtures/OptInBaseline.xml') $null
        Should -Invoke Get-BISFComponentCleanupCapability -Times 1 -Exactly
        Should -Invoke Import-Module -Times 0 -Exactly
    }
}
Describe 'Synchronous Windows component store cleanup through inbox DISM' {
    BeforeEach {
        $script:servicingResult=[pscustomobject]@{Online=$true;RestartNeeded=$false}
        Mock Get-BISFComponentCleanupCapability {}
        Mock Get-BISFPendingRebootReasons { @() }
        Mock Get-BISFComponentCleanupElapsedMinutes { 1.0 }
        Mock 'Dism\Repair-WindowsImage' { $script:servicingResult }
        Mock Write-BISFLog {}
    }
    It 'finishes the actual synchronous operation with online cleanup and no restart or downloads' {
        { Invoke-BISFComponentCleanup 75 $null } | Should -Not -Throw
        Should -Invoke Get-BISFComponentCleanupCapability -Times 1 -Exactly
        Should -Invoke 'Dism\Repair-WindowsImage' -Times 1 -Exactly -ParameterFilter {
            $Online -and $StartComponentCleanup -and $NoRestart -and $LimitAccess -and
            -not $ResetBase -and -not $Defer -and -not $RestoreHealth -and -not $Source
        }
        Should -Invoke Get-BISFPendingRebootReasons -Times 2 -Exactly
        Should -Invoke Write-BISFLog -Times 1 -Exactly -ParameterFilter { $Message -like '*completed successfully*' }
    }
    It 'rechecks capability before attempting any servicing mutation' {
        Mock Get-BISFComponentCleanupCapability { throw 'Missing StartComponentCleanup capability' }
        { Invoke-BISFComponentCleanup 75 $null } | Should -Throw '*StartComponentCleanup*'
        Should -Invoke 'Dism\Repair-WindowsImage' -Times 0 -Exactly
    }
    It 'refuses cleanup when the machine already requires a reboot' {
        Mock Get-BISFPendingRebootReasons { 'CBS RebootPending' }
        { Invoke-BISFComponentCleanup 75 $null } | Should -Throw '*pending reboot*'
        Should -Invoke 'Dism\Repair-WindowsImage' -Times 0 -Exactly
    }
    It 'propagates a native servicing failure without recording success' {
        Mock 'Dism\Repair-WindowsImage' { throw 'DISM failed 0x800f081f' }
        { Invoke-BISFComponentCleanup 75 $null } | Should -Throw '*DISM failed*'
        Should -Invoke Write-BISFLog -Times 0 -Exactly -ParameterFilter { $Message -like '*completed successfully*' }
    }
    It 'rejects <Case> completion evidence' -ForEach @(
        @{Case='missing';Result=@()},
        @{Case='multiple';Result=@([pscustomobject]@{Online=$true;RestartNeeded=$false},[pscustomobject]@{Online=$true;RestartNeeded=$false})},
        @{Case='missing Online';Result=[pscustomobject]@{RestartNeeded=$false}},
        @{Case='missing RestartNeeded';Result=[pscustomobject]@{Online=$true}},
        @{Case='string Online';Result=[pscustomobject]@{Online='True';RestartNeeded=$false}},
        @{Case='string RestartNeeded';Result=[pscustomobject]@{Online=$true;RestartNeeded='False'}},
        @{Case='offline';Result=[pscustomobject]@{Online=$false;RestartNeeded=$false}},
        @{Case='restart required';Result=[pscustomobject]@{Online=$true;RestartNeeded=$true}}
    ) {
        $script:servicingResult=$Result
        { Invoke-BISFComponentCleanup 75 $null } | Should -Throw
        Should -Invoke Write-BISFLog -Times 0 -Exactly -ParameterFilter { $Message -like '*completed successfully*' }
    }
    It 'refuses a newly pending reboot even without a generic reboot-block setting' {
        $script:rebootChecks=0
        Mock Get-BISFPendingRebootReasons { $script:rebootChecks++; if ($script:rebootChecks -gt 1) { 'Windows Update RebootRequired' } }
        { Invoke-BISFComponentCleanup 75 $null } | Should -Throw '*pending reboot*'
        Should -Invoke 'Dism\Repair-WindowsImage' -Times 1 -Exactly
        Should -Invoke Write-BISFLog -Times 0 -Exactly -ParameterFilter { $Message -like '*completed successfully*' }
    }
    It 'checks the completion budget after DISM returns and never claims timely success over budget' {
        Mock Get-BISFComponentCleanupElapsedMinutes { 75.1 }
        { Invoke-BISFComponentCleanup 75 $null } | Should -Throw '*completion budget*'
        Should -Invoke 'Dism\Repair-WindowsImage' -Times 1 -Exactly
        Should -Invoke Write-BISFLog -Times 1 -Exactly -ParameterFilter { $Message -like '*not interrupted*' }
        Should -Invoke Write-BISFLog -Times 0 -Exactly -ParameterFilter { $Message -like '*completed successfully*' }
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

