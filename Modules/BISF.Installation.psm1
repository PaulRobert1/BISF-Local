# BISF-Local installation trust bootstrap. No package code is imported here.
Set-StrictMode -Version Latest
$script:InstallationTrusted=@('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
function Assert-BISFInstallationHost {
    if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1' -or -not [Environment]::Is64BitProcess) {
        throw 'Installation initialization requires elevated 64-bit Windows PowerShell 5.1.'
    }
    $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Installation initialization requires elevation.' }
}
function Test-BISFInstallationWithin {
    param([string]$Path,[string]$Parent)
    $p=[IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $r=[IO.Path]::GetFullPath($Parent).TrimEnd([char[]]'\/')
    $p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}
function Get-BISFInstallationAcl {
    param([string]$Path)
    $a=Get-Acl -LiteralPath $Path -ErrorAction Stop
    [pscustomobject]@{
        Owner=$a.GetOwner([Security.Principal.SecurityIdentifier]).Value
        Protected=$a.AreAccessRulesProtected
        NullDacl=($null -eq ([Security.AccessControl.RawSecurityDescriptor]::new($a.GetSecurityDescriptorBinaryForm(),0)).DiscretionaryAcl)
        Sddl=$a.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access)
        Rules=@($a.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | ForEach-Object {
            [pscustomobject]@{Sid=$_.IdentityReference.Value;Rights=[int]$_.FileSystemRights;Allow=($_.AccessControlType -eq 'Allow');InheritOnly=(($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0)}
        })
    }
}
function Test-BISFInstallationAclSafe {
    param($Acl,[switch]$Ancestor,[switch]$Private,[switch]$Code)
    if ($null -ne $Acl.PSObject.Properties['NullDacl'] -and $Acl.NullDacl) { return $false }
    if ($Acl.Owner -notin $script:InstallationTrusted) { return $false }
    if ($Private -and $null -ne $Acl.PSObject.Properties['Protected'] -and -not $Acl.Protected) { return $false }
    $mask=65536 -bor 64 -bor 262144 -bor 524288 -bor 1073741824 -bor 268435456
    if (-not $Ancestor) { $mask=$mask -bor 2 -bor 4 -bor 16 -bor 256 }
    $userRead=0
    foreach ($r in $Acl.Rules) {
        if ($Code -and -not $r.InheritOnly) {
            if (-not $r.Allow -and ($r.Rights -band 131241) -ne 0) { return $false }
            if ($r.Allow -and $r.Sid -eq 'S-1-5-32-545') { $userRead=$userRead -bor $r.Rights }
        }
        if (-not $r.Allow -or $r.Sid -in $script:InstallationTrusted) { continue }
        # Private data also rejects inheritable read grants to other accounts.
        if ($Private -and $r.Rights -ne 0) { return $false }
        if (-not $r.InheritOnly -and ($r.Rights -band $mask) -ne 0) { return $false }
    }
    if ($Code -and ($userRead -band 131241) -ne 131241) { return $false }
    $true
}
function Get-BISFInstallationLinkCount {
    param([string]$Path)
    if (-not ('BISFInstallation.NativeFiles' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace BISFInstallation {
 public static class NativeFiles {
  [StructLayout(LayoutKind.Sequential)] struct Info {
   public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
   public uint VolumeSerial, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
  }
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Info info);
  public static uint LinkCount(string path) {
   using(var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
    Info info; if(!GetFileInformationByHandle(stream.SafeFileHandle,out info)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    return info.Links;
   }
  }
 }
}
'@ -ErrorAction Stop
    }
    [BISFInstallation.NativeFiles]::LinkCount($Path)
}
function Assert-BISFInstallationObject {
    param([string]$Path)
    $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Installation contains a reparse point: $Path" }
    if (-not $i.PSIsContainer -and (Get-BISFInstallationLinkCount $Path) -ne 1) { throw "Installation contains a hard link or an unverifiable file: $Path" }
    $i
}
function New-BISFInstallationAcl {
    param([bool]$Directory,[bool]$Private)
    if ($Directory) { $a=New-Object Security.AccessControl.DirectorySecurity } else { $a=New-Object Security.AccessControl.FileSecurity }
    $a.SetAccessRuleProtection($true,$false)
    $a.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    foreach ($sid in @('S-1-5-18','S-1-5-32-544','S-1-5-32-545')) {
        if ($Private -and $sid -eq 'S-1-5-32-545') { continue }
        $rights=if ($sid -eq 'S-1-5-32-545') { 'ReadAndExecute' } else { 'FullControl' }
        $id=New-Object Security.Principal.SecurityIdentifier($sid)
        if ($Directory) { $rule=New-Object Security.AccessControl.FileSystemAccessRule($id,$rights,'ContainerInherit,ObjectInherit','None','Allow') }
        else { $rule=New-Object Security.AccessControl.FileSystemAccessRule($id,$rights,'Allow') }
        $null=$a.AddAccessRule($rule)
    }
    $a
}
function Set-BISFInstallationAcl {
    param([string]$Path,[bool]$Directory,[bool]$Private)
    $null=Assert-BISFInstallationObject $Path
    Set-Acl -LiteralPath $Path -AclObject (New-BISFInstallationAcl $Directory $Private) -ErrorAction Stop
}
function Assert-BISFInstallationAncestors {
    param([string]$ScriptRoot)
    $p=[IO.Path]::GetDirectoryName($ScriptRoot)
    while (-not [string]::IsNullOrEmpty($p)) {
        $null=Assert-BISFInstallationObject $p
        if (-not (Test-BISFInstallationAclSafe (Get-BISFInstallationAcl $p) -Ancestor)) {
            throw "Unsafe installation ancestor: $p. Its permissions were not changed. Use a protected installation location."
        }
        $next=[IO.Path]::GetDirectoryName($p)
        if ($next -eq $p) { break }; $p=$next
    }
}
function Get-BISFInstallationPrivateRoots {
    param([string]$ScriptRoot,[string]$ConfigPath)
    $roots=@((Join-Path $ScriptRoot 'state'),(Join-Path $ScriptRoot 'logs'))
    $settings=New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit; $settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($ConfigPath,$settings)
    try { $doc=New-Object Xml.XmlDocument; $doc.XmlResolver=$null; $doc.Load($reader) } finally { $reader.Dispose() }
    $node=$doc.SelectSingleNode('/BISF/Logging/Path')
    if ($null -ne $node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) {
        $log=$node.InnerText.Trim()
        if (-not [IO.Path]::IsPathRooted($log)) { $log=Join-Path $ScriptRoot $log }
        $log=[IO.Path]::GetFullPath($log)
        if (Test-BISFInstallationWithin $log $ScriptRoot) {
            foreach ($code in @($ScriptRoot,(Join-Path $ScriptRoot 'Modules'),$ConfigPath,(Join-Path $ScriptRoot 'Invoke-BISF.ps1'),(Join-Path $ScriptRoot 'Apply-BISFUserSettings.ps1'),(Join-Path $ScriptRoot 'GlobalConfig.xsd'))) {
                if ((Test-BISFInstallationWithin $code $log) -or (Test-BISFInstallationWithin $log (Join-Path $ScriptRoot 'Modules'))) {
                    throw 'Configured log directory overlaps installation code or its configuration.'
                }
            }
            $roots += $log
        }
    }
    $roots
}
function New-BISFInstallationPrivateDirectory {
    param([string]$Path)
    $dir=New-Object IO.DirectoryInfo($Path)
    $dir.Create((New-BISFInstallationAcl $true $true))
}
function New-BISFInstallationBackup {
    param([string]$ScriptRoot,[object[]]$Snapshots)
    # Create with a private descriptor before persisting original ACL data.
    $path=Join-Path $ScriptRoot ('acl-backup-'+[guid]::NewGuid().ToString('N'))
    New-BISFInstallationPrivateDirectory $path
    $null=Assert-BISFInstallationObject $path
    if (-not (Test-BISFInstallationAclSafe (Get-BISFInstallationAcl $path) -Private)) { throw 'Could not create a protected ACL backup.' }
    $file=Join-Path $path 'original-acls.json'
    [IO.File]::WriteAllText($file,($Snapshots | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
    Set-BISFInstallationAcl $file $false $true
    if (-not (Test-BISFInstallationAclSafe (Get-BISFInstallationAcl $file) -Private)) { throw 'ACL backup is not protected.' }
    $file
}
function Initialize-BISFInstallation {
    [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$ScriptRoot,[Parameter(Mandatory=$true)][string]$ConfigPath)
    Assert-BISFInstallationHost
    if ($ScriptRoot -match '^[\\/]{2}' -or -not [IO.Path]::IsPathRooted($ScriptRoot) -or $ScriptRoot -notmatch '^[A-Za-z]:[\\/]') { throw 'Installation requires a local absolute drive path.' }
    $root=[IO.Path]::GetFullPath($ScriptRoot).TrimEnd([char[]]'\/')
    $drive=[IO.Path]::GetPathRoot($root).TrimEnd([char[]]'\/')
    if ($root -eq $drive) { throw 'A dedicated installation directory is required.' }
    foreach ($container in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramData)) {
        if (-not [string]::IsNullOrWhiteSpace($container) -and $root.Equals($container.TrimEnd([char[]]'\/'),[StringComparison]::OrdinalIgnoreCase)) { throw 'A dedicated installation directory is required.' }
    }
    foreach ($protected in @($env:SystemRoot,$env:USERPROFILE,(Join-Path ($drive+'\') 'Users'))) {
        if (-not [string]::IsNullOrWhiteSpace($protected) -and (Test-BISFInstallationWithin $root $protected)) { throw 'Installation must be outside Windows and user profile directories.' }
    }
    $null=Assert-BISFInstallationObject $root
    Assert-BISFInstallationAncestors $root
    foreach ($marker in @('Invoke-BISF.ps1','GlobalConfig.xsd','Apply-BISFUserSettings.ps1','Modules/BISF.Local.psm1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $marker) -PathType Leaf)) { throw "Incomplete BISF installation; missing $marker." }
    }
    if (-not [IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath=Join-Path $root $ConfigPath }
    $ConfigPath=[IO.Path]::GetFullPath($ConfigPath)
    Protect-BISFInstallationTree $root $ConfigPath
}
function Protect-BISFInstallationTree {
    param([string]$root,[string]$ConfigPath)
    if (Test-Path -LiteralPath (Join-Path $root 'state/operator-seal.json')) {
        throw 'Existing operator-seal state detected. Resolve the earlier sealing attempt before installation initialization.'
    }
    # Validate each directory before descending; never follow a discovered junction.
    $items=New-Object 'Collections.Generic.List[object]'
    $queue=New-Object 'Collections.Generic.Queue[string]'; $queue.Enqueue($root)
    while ($queue.Count -gt 0) {
        $path=$queue.Dequeue(); $i=Assert-BISFInstallationObject $path; $items.Add($i)
        if ($i.PSIsContainer) {
            foreach ($child in Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop) {
                $child=Assert-BISFInstallationObject $child.FullName
                if ($child.PSIsContainer) { $queue.Enqueue($child.FullName) } else { $items.Add($child) }
            }
        }
    }
    $privateRoots=@(Get-BISFInstallationPrivateRoots $root $ConfigPath)
    $snapshots=@(); $changes=@()
    foreach ($i in $items) {
        # Prior backups remain private on all subsequent launches.
        $private=($i.FullName -match '[\\/]acl-backup-[a-f0-9]{32}([\\/]|$)')
        foreach ($dataRoot in $privateRoots) { if (Test-BISFInstallationWithin $i.FullName $dataRoot) { $private=$true; break } }
        $acl=Get-BISFInstallationAcl $i.FullName
        $snapshots += [pscustomobject]@{Path=$i.FullName;Sddl=$acl.Sddl}
        if (-not (Test-BISFInstallationAclSafe $acl -Private:$private -Code:(-not $private))) { $changes += [pscustomobject]@{Path=$i.FullName;Directory=[bool]$i.PSIsContainer;Private=[bool]$private} }
    }
    $missingRoots=@($privateRoots | Select-Object -Unique | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($changes.Count -eq 0 -and $missingRoots.Count -eq 0) { return }
    $backup=New-BISFInstallationBackup $root $snapshots
    # All paths, hard links and ancestor ACLs passed before any descriptor change.
    foreach ($change in @($changes | Sort-Object @{Expression='Private';Descending=$true},@{Expression={ $_.Path.Length };Ascending=$true})) { Set-BISFInstallationAcl $change.Path $change.Directory $change.Private }
    foreach ($dataRoot in $missingRoots) {
        New-BISFInstallationPrivateDirectory $dataRoot
        $null=Assert-BISFInstallationObject $dataRoot
        if (-not (Test-BISFInstallationAclSafe (Get-BISFInstallationAcl $dataRoot) -Private)) { throw "New runtime directory is not protected: $dataRoot" }
    }
    Assert-BISFInstallationAncestors $root
    foreach ($i in $items) {
        $null=Assert-BISFInstallationObject $i.FullName
        $private=($i.FullName -match '[\\/]acl-backup-[a-f0-9]{32}([\\/]|$)')
        foreach ($dataRoot in $privateRoots) { if (Test-BISFInstallationWithin $i.FullName $dataRoot) { $private=$true; break } }
        if (-not (Test-BISFInstallationAclSafe (Get-BISFInstallationAcl $i.FullName) -Private:$private -Code:(-not $private))) { throw "Installation permissions remain unsafe: $($i.FullName). Original ACL backup: $backup" }
    }
    Write-Verbose "Initialized protected installation permissions. Original ACL backup: $backup"
}
Export-ModuleMember -Function Initialize-BISFInstallation
