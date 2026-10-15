# BIS-F Local, unofficial GPL-3.0 derivative. Profile cleanup for quiescent MCS masters.
# Never delete C:\Users trees directly: the Windows profile provider removes the
# registered profile and its metadata. No third-party binaries or policy changes.
function Get-BISFCurrentUserSid {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or $null -eq $identity.User) { throw 'Unable to determine the current Windows user SID.' }
    [string]$identity.User.Value
}
function Get-BISFProfilesRoot {
    $key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $settings=Get-ItemProperty -LiteralPath $key -Name ProfilesDirectory -ErrorAction Stop
    $value=[Environment]::ExpandEnvironmentVariables(([string]$settings.ProfilesDirectory).Trim())
    # Fail closed on UNC, drive-relative, unresolved variables, ADS or provider paths.
    if ($value -notmatch '^[A-Za-z]:[\/\\]' -or $value.Contains('%') -or
        $value.Substring(2).Contains(':') -or $value -match '[\x00-\x1f"*?]') {
        throw 'ProfilesDirectory must resolve to an absolute local directory.'
    }
    $root=[IO.Path]::GetFullPath($value).TrimEnd([char[]]'\/')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Windows profiles root does not exist: $root" }
    Test-BISFNoReparsePath $root
    $root
}
function Test-BISFDirectProfilePath {
    param([string]$Path,[string]$Root)
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $pathValue=$Path.Trim()
    if (-not [IO.Path]::IsPathRooted($pathValue) -or $pathValue -match '(^\\\\|^//|[\x00-\x1f"*?])') { return $false }
    if ([IO.Path]::DirectorySeparatorChar -ne '/' -and $pathValue -notmatch '^[A-Za-z]:[\/\\]') { return $false }
    if ($pathValue.Contains(':') -and ($pathValue -notmatch '^[A-Za-z]:[\/\\]' -or $pathValue.Substring(2).Contains(':'))) { return $false }
    try {
        $full=[IO.Path]::GetFullPath($pathValue).TrimEnd([char[]]'\/')
        $parent=[IO.Path]::GetDirectoryName($full)
        $canonicalRoot=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
        return $null -ne $parent -and $parent.Equals($canonicalRoot,[StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}
function New-BISFProfileDecision {
    param([string]$SID,[string]$LocalPath,[string]$Status,[string]$Reason)
    [pscustomobject]@{SID=$SID;LocalPath=$LocalPath;Status=$Status;Reason=$Reason}
}
function Get-BISFUserProfileDisposition {
    param($Profile,[string]$Root,[string]$CurrentSid,[string[]]$ExcludedSIDs=@())
    $sid=[string]$Profile.SID
    $path=[string]$Profile.LocalPath
    if ([string]::IsNullOrWhiteSpace($sid)) { return New-BISFProfileDecision $sid $path Protected 'No SID' }
    if ($null -eq $Profile.PSObject.Properties['Special'] -or $null -eq $Profile.PSObject.Properties['Loaded'] -or
        $null -eq $Profile.Special -or $null -eq $Profile.Loaded) {
        return New-BISFProfileDecision $sid $path Blocked 'Missing profile lifecycle flags'
    }
    if ($Profile.Special) { return New-BISFProfileDecision $sid $path Protected 'Special system profile' }
    if ($sid -eq $CurrentSid) { return New-BISFProfileDecision $sid $path Protected 'Current administrator profile' }
    if ($sid -in $ExcludedSIDs) { return New-BISFProfileDecision $sid $path Protected 'Explicit SID exclusion' }
    # Only domain/local S-1-5-21 identities are auto-cleaned. Built-in accounts
    # (RID under 1000) and nonstandard identities remain for manual review.
    if ($sid -notmatch '^S-1-5-21-([0-9]+-){3}([0-9]+)$') {
        return New-BISFProfileDecision $sid $path Protected 'Not a normal domain/local user SID'
    }
    if ([long]$Matches[2] -lt 1000) {
        return New-BISFProfileDecision $sid $path Protected 'Built-in or reserved account RID'
    }
    if (-not (Test-BISFDirectProfilePath $path $Root)) {
        return New-BISFProfileDecision $sid $path Protected 'Path is not a direct child of ProfilesDirectory'
    }
    $leaf=[IO.Path]::GetFileName($path.TrimEnd([char[]]'\/'))
    if ($leaf -match '^(Default|Default User|Public|All Users|defaultuser0|WDAGUtilityAccount|Administrator(\..*)?)$') {
        return New-BISFProfileDecision $sid $path Protected 'Reserved or administrator profile directory'
    }
    if ($Profile.Loaded) { return New-BISFProfileDecision $sid $path Blocked 'Profile still loaded: log off the user' }
    if ($null -ne $Profile.PSObject.Properties['RefCount'] -and $null -ne $Profile.RefCount -and [long]$Profile.RefCount -gt 0) {
        return New-BISFProfileDecision $sid $path Blocked 'Profile reference count is nonzero'
    }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        return New-BISFProfileDecision $sid $path Protected 'Profile directory missing: manual review required'
    }
    # Reject junction/symlink paths rather than risk crossing filesystem boundaries.
    Test-BISFNoReparsePath $path
    New-BISFProfileDecision $sid $path Remove 'Inactive, registered, non-special user profile'
}
function Get-BISFUserProfilePlan {
    param([string[]]$ExcludedSIDs=@())
    $root=Get-BISFProfilesRoot
    $currentSid=Get-BISFCurrentUserSid
    $profiles=@(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)
    $entries=New-Object 'System.Collections.Generic.List[object]'
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($profile in $profiles) {
        $decision=Get-BISFUserProfileDisposition $profile $root $currentSid $ExcludedSIDs
        if (-not [string]::IsNullOrWhiteSpace($decision.SID)) {
            if (-not $seen.Add($decision.SID)) { throw "Duplicate Windows profile SID returned by provider: $($decision.SID)" }
        }
        $entries.Add($decision)
    }
    [pscustomobject]@{
        Root=$root;CurrentSid=$currentSid;ExcludedSIDs=[string[]]$ExcludedSIDs
        Entries=$entries.ToArray()
    }
}
function Invoke-BISFUserProfileCleanup {
    param($Plan,$Logger)
    foreach ($target in @($Plan.Entries | Where-Object { $_.Status -eq 'Remove' })) {
        if ($target.SID -notmatch '^S-1-5-21-([0-9]+-){3}[0-9]+$') { throw 'Refusing an invalid user profile SID.' }
        # Re-query by the unambiguous SID immediately before deletion.
        $query="SID='$($target.SID)'"
        $matches=@(Get-CimInstance -ClassName Win32_UserProfile -Filter $query -ErrorAction Stop)
        if ($matches.Count -ne 1) { throw "Profile disappeared or became ambiguous: $($target.SID)" }
        $now=Get-BISFUserProfileDisposition $matches[0] $Plan.Root $Plan.CurrentSid $Plan.ExcludedSIDs
        if ($now.Status -ne 'Remove' -or $now.LocalPath -ne $target.LocalPath) {
            throw "Profile changed since preview; not deleting SID $($target.SID): $($now.Reason)"
        }
        Remove-CimInstance -InputObject $matches[0] -Confirm:$false -ErrorAction Stop
        Write-BISFLog $Logger Info UserProfiles ("Removed profile SID={0}; path={1}" -f $target.SID,$target.LocalPath)
    }
}
