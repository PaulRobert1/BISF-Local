BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($n in 'Operations','Profiles','Configuration','Logging','Runner') { . "$root/Modules/Private/$n.ps1" }
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { function Get-CimInstance { param($ClassName,$Filter) } }
    if (-not (Get-Command Remove-CimInstance -ErrorAction SilentlyContinue)) { function Remove-CimInstance { param($InputObject) } }
    function New-TestProfile {
        param([string]$SID,[string]$Path,[bool]$Loaded=$false,[bool]$Special=$false,[int]$RefCount=0)
        [pscustomobject]@{SID=$SID;LocalPath=$Path;Loaded=$Loaded;Special=$Special;RefCount=$RefCount}
    }
}
Describe 'Citrix MCS user profile inventory and safe deletion' {
    BeforeEach {
        $script:profileRoot=Join-Path $TestDrive ('Users-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:profileRoot | Out-Null
        $script:userSid='S-1-5-21-111-222-333-1001'
        $script:currentSid='S-1-5-21-111-222-333-1002'
        $script:profiles=@()
        $script:deleted=New-Object 'System.Collections.Generic.List[string]'
        Mock Get-BISFProfilesRoot { $script:profileRoot }
        Mock Get-BISFCurrentUserSid { $script:currentSid }
        Mock Get-CimInstance {
            if ($Filter) {
                @($script:profiles | Where-Object { "SID='$($_.SID)'" -eq $Filter })
            } else { $script:profiles }
        }
        Mock Remove-BISFCimUserProfile { $script:deleted.Add($Profile.SID) }
        Mock Write-BISFLog {}
    }
    It 'selects inactive, registered, non-special profiles from the configured Users root' {
        $folder=Join-Path $script:profileRoot 'testuser'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $folder)
        $plan=Get-BISFUserProfilePlan
        $plan.Entries.Count | Should -Be 1
        $plan.Entries[0].Status | Should -Be 'Remove'
        $plan.Entries[0].SID | Should -Be $script:userSid
    }
    It 'protects the currently logged-on administrator even when inactive' {
        $folder=Join-Path $script:profileRoot 'operator'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile $script:currentSid $folder)
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Protected'
    }
    It 'protects the built-in administrator SID regardless of the profile folder name' {
        $folder=Join-Path $script:profileRoot 'localized-admin'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile 'S-1-5-21-111-222-333-500' $folder)
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Protected'
    }
    It 'protects special system accounts and non-user SIDs' {
        $folder=Join-Path $script:profileRoot 'system-foo'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile 'S-1-5-18' $folder $false $true)
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Protected'
        $script:profiles=@(New-TestProfile 'S-1-5-80-123' $folder)
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Protected'
    }
    It 'protects explicitly excluded SIDs, including other administrator accounts' {
        $folder=Join-Path $script:profileRoot 'admin2'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $folder)
        (Get-BISFUserProfilePlan -ExcludedSIDs @($script:userSid)).Entries[0].Status | Should -Be 'Protected'
    }
    It 'protects names used by template and built-in profile directories' {
        $folder=Join-Path $script:profileRoot 'Default'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $folder)
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Protected'
    }
    It 'refuses paths outside or below a subdirectory of the configured profile root' {
        $outside=Join-Path $TestDrive ('elsewhere-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outside | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $outside)
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Protected'
        $nested=Join-Path (Join-Path $script:profileRoot 'nested') 'child'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $nested)
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Protected'
    }
    It 'protects missing profile directories rather than erasing orphaned registry records' {
        $script:profiles=@(New-TestProfile $script:userSid (Join-Path $script:profileRoot 'missing'))
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Protected'
    }
    It 'blocks preparation if an unprotected user profile is loaded' {
        $folder=Join-Path $script:profileRoot 'session'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $folder $true)
        $plan=Get-BISFUserProfilePlan
        $plan.Entries[0].Status | Should -Be 'Blocked'
        Should -Invoke Remove-BISFCimUserProfile -Times 0
    }
    It 'blocks a profile with a nonzero reference count despite Loaded=false' {
        $folder=Join-Path $script:profileRoot 'session'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $folder $false $false 2)
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Blocked'
    }
    It 'calls the Windows profile provider, never raw folder deletion' {
        $folder=Join-Path $script:profileRoot 'testuser'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $folder)
        $plan=Get-BISFUserProfilePlan
        Invoke-BISFUserProfileCleanup $plan $null
        $script:deleted.Count | Should -Be 1
        $script:deleted[0] | Should -Be $script:userSid
        Should -Invoke Remove-BISFCimUserProfile -Times 1 -Exactly -ParameterFilter {
            $Profile.SID -eq 'S-1-5-21-111-222-333-1001'
        }
    }
    It 'refuses deletion if the profile becomes loaded after initial preview' {
        $folder=Join-Path $script:profileRoot 'testuser'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $folder)
        $plan=Get-BISFUserProfilePlan
        $script:profiles[0].Loaded=$true
        { Invoke-BISFUserProfileCleanup $plan $null } | Should -Throw '*changed since preview*'
        $script:deleted.Count | Should -Be 0
    }
    It 'refuses deletion if a SID is reassigned to another profile folder' {
        $folder=Join-Path $script:profileRoot 'testuser'
        $another=Join-Path $script:profileRoot 'differentuser'
        New-Item -ItemType Directory -Path $folder | Out-Null
        New-Item -ItemType Directory -Path $another | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $folder)
        $plan=Get-BISFUserProfilePlan
        $script:profiles[0].LocalPath=$another
        { Invoke-BISFUserProfileCleanup $plan $null } | Should -Throw '*changed since preview*'
        $script:deleted.Count | Should -Be 0
    }
    It 'refuses duplicate provider SIDs instead of acting on an ambiguous profile' {
        $folder=Join-Path $script:profileRoot 'testuser'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@((New-TestProfile $script:userSid $folder),(New-TestProfile $script:userSid $folder))
        { Get-BISFUserProfilePlan } | Should -Throw '*Duplicate*'
        $script:deleted.Count | Should -Be 0
    }
    It 'does not swallow CIM errors during removal' {
        $folder=Join-Path $script:profileRoot 'testuser'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@(New-TestProfile $script:userSid $folder)
        $plan=Get-BISFUserProfilePlan
        Mock Remove-BISFCimUserProfile { throw 'profile provider denied deletion' }
        { Invoke-BISFUserProfileCleanup $plan $null } | Should -Throw '*provider denied*'
    }
    It 'blocks unknown Loaded and Special flags instead of assuming inactive' {
        $folder=Join-Path $script:profileRoot 'testuser'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $script:profiles=@([pscustomobject]@{SID=$script:userSid;LocalPath=$folder;Loaded=$null;Special=$false;RefCount=0})
        (Get-BISFUserProfilePlan).Entries[0].Status | Should -Be 'Blocked'
    }
}
