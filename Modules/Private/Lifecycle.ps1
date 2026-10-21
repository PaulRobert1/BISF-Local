# BIS-F Local, unofficial derivative. Modified 2026-10-12. GPL-3.0; see LICENSE.
function Enter-BISFLock {
    $mutex = New-Object Threading.Mutex($false, 'Global\BISF-Local-Apply-v1')
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Another BIS-F Local apply run is active.' }
        [pscustomobject]@{Mutex=$mutex;Acquired=$true}
    } catch { $mutex.Dispose(); throw }
}
function Exit-BISFLock {
    param($Lock)
    if ($null -ne $Lock) {
        try { if ($Lock.Acquired) { $Lock.Mutex.ReleaseMutex() } } finally { $Lock.Mutex.Dispose() }
    }
}
function Get-BISFIdentity {
    [pscustomobject]@{
        Name=[string]$env:COMPUTERNAME
        MachineGuid=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
        SmbiosUuid=[string](Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID
    }
}
function Test-BISFValidGuid {
    param([string]$Value)
    $g=[guid]::Empty
    [guid]::TryParse($Value,[ref]$g) -and $g -ne [guid]::Empty -and $g.ToString() -ne 'ffffffff-ffff-ffff-ffff-ffffffffffff'
}
function Test-BISFCloneIdentity {
    param($Master, $Current)
    if ([string]::IsNullOrWhiteSpace($Current.Name) -or [string]::IsNullOrWhiteSpace($Master.Name) -or $Current.Name -eq $Master.Name) {
        throw 'Personalization refused: same or missing master computer name.'
    }
    $changed = $false
    foreach ($key in 'MachineGuid','SmbiosUuid') {
        if ((Test-BISFValidGuid $Master.$key) -and (Test-BISFValidGuid $Current.$key) -and $Master.$key -ne $Current.$key) { $changed=$true }
    }
    if (-not $changed) { throw 'Personalization refused: clone identity is ambiguous (no changed reliable identifier).' }
}
function Test-BISFCompletion {
    param($State, $Identity)
    if ($null -eq $State.Completion -or $State.Completion.Generation -ne $State.Generation) { return $false }
    foreach ($key in 'Name','MachineGuid','SmbiosUuid') {
        if ($State.Completion.Identity.$key -ne $Identity.$key) { return $false }
    }
    $true
}
function New-BISFState {
    param($Master, [string]$ConfigHash, [bool]$CMPrepared)
    [pscustomobject]@{SchemaVersion=1;Generation=[guid]::NewGuid().ToString();Status='Preparing';Master=$Master;ConfigHash=$ConfigHash;CMPrepared=$CMPrepared;Completion=$null}
}
function Read-BISFState {
    param([string]$StatePath)
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { throw 'No prepared state found. Prepare the master before personalization.' }
    $s = Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    foreach ($key in 'SchemaVersion','Generation','Status','Master','ConfigHash','CMPrepared','Completion') {
        if ($null -eq $s.PSObject.Properties[$key]) { throw "Invalid lifecycle state: missing $key." }
    }
    if ($s.SchemaVersion -ne 1 -or -not (Test-BISFValidGuid $s.Generation) -or $s.Status -notin @('Preparing','Prepared','Failed') -or $s.ConfigHash -notmatch '^[0-9a-fA-F]{64}$' -or $s.CMPrepared -isnot [bool]) { throw 'Invalid lifecycle state values.' }
    foreach ($key in 'Name','MachineGuid','SmbiosUuid') { if ($null -eq $s.Master.PSObject.Properties[$key]) { throw 'Invalid master identity in state.' } }
    if ($null -ne $s.Completion) {
        if ($null -eq $s.Completion.PSObject.Properties['Generation'] -or $null -eq $s.Completion.PSObject.Properties['Identity']) { throw 'Invalid completion state.' }
        foreach ($key in 'Name','MachineGuid','SmbiosUuid') { if ($null -eq $s.Completion.Identity.PSObject.Properties[$key]) { throw 'Invalid completion identity.' } }
    }
    $s
}
function Test-BISFAclRules {
    param([string]$Owner, [object[]]$Rules, [bool]$Ancestor, [string]$Path, [string]$RequestedPath)
    $trusted = @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    $location=if ([string]::IsNullOrWhiteSpace($Path)) { 'Location' } else { "Location '$Path'" }
    $scope=if ($Ancestor) { 'Ancestor' } else { 'Target' }
    if ($Owner -notin $trusted) { throw "Untrusted filesystem owner: $Owner. $location; scope=$scope; requested='$RequestedPath'. Use an Administrators or SYSTEM-owned directory." }
    # Ancestors: deny deletion/replacement or ACL/owner changes; creating siblings is OK.
    $mask = 65536 -bor 64 -bor 262144 -bor 524288
    if (-not $Ancestor) { $mask = $mask -bor 2 -bor 4 -bor 16 -bor 256 }
    foreach ($r in $Rules) {
        if ($r.Allow -and -not $r.InheritOnly -and $r.Sid -notin $trusted -and (($r.Rights -band $mask) -ne 0)) {
            throw ("{0} is writable by untrusted principal {1}. Rights={2} (0x{3:X8}); blocked=0x{4:X8}; scope={5}; requested='{6}'." -f $location,$r.Sid,([Security.AccessControl.FileSystemRights]$r.Rights),$r.Rights,($r.Rights -band $mask),$scope,$RequestedPath)
        }
    }
}
function Test-BISFProtectedLocation {
    param([string]$Path)
    if ($Path -match '^\\\\' -or $Path -match '^//' -or -not [IO.Path]::IsPathRooted($Path)) { throw 'A local absolute path is required for protected runtime files.' }
    Test-BISFNoReparsePath $Path
    $current=[IO.Path]::GetFullPath($Path)
    $isTarget=$true
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath $current) {
            $acl=Get-Acl -LiteralPath $current -ErrorAction Stop
            $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
            $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | ForEach-Object {
                [pscustomobject]@{Sid=$_.IdentityReference.Value;Rights=[int]$_.FileSystemRights;Allow=($_.AccessControlType -eq 'Allow');InheritOnly=(($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0)}
            })
            Test-BISFAclRules $owner $rules (-not $isTarget) -Path $current -RequestedPath $Path
            $isTarget=$false
        }
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Set-BISFPrivateAcl {
    param([string]$Path)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer) { $acl=New-Object Security.AccessControl.DirectorySecurity }
    else { $acl=New-Object Security.AccessControl.FileSecurity }
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    foreach ($sid in 'S-1-5-18','S-1-5-32-544') {
        $identity=New-Object Security.Principal.SecurityIdentifier($sid)
        if ($item.PSIsContainer) { $rule=New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow') }
        else { $rule=New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','Allow') }
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
function Write-BISFState {
    param([string]$StatePath, $State)
    $dir=Split-Path -Parent $StatePath
    Test-BISFProtectedLocation $dir
    if (-not (Test-Path -LiteralPath $dir)) {
        [void][IO.Directory]::CreateDirectory($dir)
        Set-BISFPrivateAcl $dir
    }
    Test-BISFProtectedLocation $StatePath
    $tmp=Join-Path $dir ([guid]::NewGuid().ToString('N')+'.tmp')
    try {
        [IO.File]::WriteAllText($tmp, ($State | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        Set-BISFPrivateAcl $tmp
        if ([IO.File]::Exists($StatePath)) { [IO.File]::Replace($tmp,$StatePath,[NullString]::Value) }
        else { [IO.File]::Move($tmp,$StatePath) }
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}
function Get-BISFTaskArguments {
    param([string]$ScriptPath,[string]$ConfigPath)
    foreach ($p in $ScriptPath,$ConfigPath) { if ($p -match '["\r\n]' -or [string]::IsNullOrWhiteSpace($p)) { throw 'Invalid scheduled-task path.' } }
    '-NoProfile -NonInteractive -File "{0}" -Mode Personalize -ConfigPath "{1}"' -f $ScriptPath,$ConfigPath
}
function Get-BISFTaskMarker {
    param([string]$ScriptRoot,[string]$ConfigPath)
    'BISF-Local/v1 | {0} | {1}' -f $ScriptRoot,$ConfigPath
}
function Test-BISFTaskOwnership {
    param([string]$ScriptRoot,[string]$ConfigPath)
    $existing=@(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -eq 'BISF-Local-Personalize' })
    if ($existing.Count -gt 0) {
        $expected=Get-BISFTaskMarker $ScriptRoot $ConfigPath
        if ($existing.Count -ne 1 -or $existing[0].Description -ne $expected) { throw 'Refusing to overwrite an unrelated BISF-Local-Personalize task.' }
        $actions=@($existing[0].Actions)
        $hostPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $args=Get-BISFTaskArguments (Join-Path $ScriptRoot 'Invoke-BISF.ps1') $ConfigPath
        if ($actions.Count -ne 1 -or $actions[0].Execute -ne $hostPath -or $actions[0].Arguments -ne $args -or $existing[0].Principal.UserId -notin @('SYSTEM','S-1-5-18')) {
            throw 'Existing BISF task no longer matches this package.'
        }
    }
}
function Register-BISFStartupTask {
    param([string]$ScriptPath,[string]$ConfigPath)
    $root=Split-Path -Parent $ScriptPath
    Test-BISFProtectedLocation $ScriptPath
    Test-BISFProtectedLocation $ConfigPath
    Test-BISFTaskOwnership $root $ConfigPath
    $action=New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument (Get-BISFTaskArguments $ScriptPath $ConfigPath) -WorkingDirectory $root
    $trigger=New-ScheduledTaskTrigger -AtStartup
    $principal=New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -StartWhenAvailable
    $null=Register-ScheduledTask -TaskName 'BISF-Local-Personalize' -TaskPath '\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description (Get-BISFTaskMarker $root $ConfigPath) -Force -ErrorAction Stop
}
function Get-BISFJournalStatus {
    param([string]$ScriptRoot)
    $status=[pscustomobject]@{PreparationPending=$false;PersonalizationPending=$false}
    foreach ($entry in @(@('Prepare','PreparationPending'),@('Personalize','PersonalizationPending'))) {
        $path=Join-Path $ScriptRoot ('state/'+$entry[0]+'.pending')
        Test-BISFProtectedLocation $path
        $status.($entry[1])=Test-Path -LiteralPath $path
    }
    $status
}
function Enter-BISFJournal {
    param([string]$ScriptRoot,[ValidateSet('Prepare','Personalize')][string]$Mode)
    $dir=Join-Path $ScriptRoot 'state'
    Test-BISFProtectedLocation $dir
    if (-not (Test-Path -LiteralPath $dir)) {
        [void][IO.Directory]::CreateDirectory($dir)
        Set-BISFPrivateAcl $dir
    }
    $path=Join-Path $dir ($Mode+'.pending')
    Test-BISFProtectedLocation $path
    # A retained marker is intentionally not removed on failure. It remains
    # authoritative even if a later attempt to invalidate JSON state also fails.
    [IO.File]::WriteAllText($path,'Incomplete run; retry the same mode. Do not remove manually.',(New-Object Text.UTF8Encoding($false)))
    Set-BISFPrivateAcl $path
    $path
}
function Clear-BISFJournal {
    param([string]$Path)
    Test-BISFProtectedLocation $Path
    [IO.File]::Delete($Path)
}
