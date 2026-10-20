# Explorer settings are applied per user at Explorer sign-in, including new clone users.
function Set-BISFUserRegistryValue {
 param([string]$Key,[AllowEmptyString()][string]$Name,$Value,[string]$Kind='DWord')
 $allowed=@('Software\Microsoft\Windows\CurrentVersion\Explorer','Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
 'Software\Classes\CLSID\{679f85cb-0220-4080-b29b-5540cc05aab6}',
 'Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}',
 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32')
 if($Key -notin $allowed){throw 'Unexpected Explorer registry target'}
 $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Key)
 try {$k.SetValue($Name,$Value,[Microsoft.Win32.RegistryValueKind]::$Kind);$k.Flush()} finally {$k.Dispose()}
}
function Invoke-BISFUserCustomizations {
 [CmdletBinding()]param([switch]$RemoveQuickAccess,[switch]$ClassicContextMenu)
 if($RemoveQuickAccess){
  Set-BISFUserRegistryValue 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1
  Set-BISFUserRegistryValue 'Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 0
  Set-BISFUserRegistryValue 'Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0
  foreach($id in '{679f85cb-0220-4080-b29b-5540cc05aab6}','{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'){
   Set-BISFUserRegistryValue ('Software\Classes\CLSID\'+$id) 'System.IsPinnedToNameSpaceTree' 0
  }
 }
 if($ClassicContextMenu){Set-BISFUserRegistryValue 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '' '' 'String'}
}
function Test-BISFExplorerPreflight {
 param([string]$ScriptRoot)
 if($ScriptRoot.Contains('"') -or $ScriptRoot.Contains('%')){throw 'Unsupported package path for Explorer sign-in hook'}
 Test-BISFProtectedLocation $ScriptRoot
 $script=Join-Path $ScriptRoot 'Apply-BISFUserSettings.ps1'
 if(-not(Test-Path -LiteralPath $script -PathType Leaf)){throw 'Missing Explorer user-settings script'}
 Test-BISFProtectedLocation $script
 foreach($file in Get-ChildItem (Join-Path $ScriptRoot 'Modules') -Recurse -File){Test-BISFProtectedLocation $file.FullName}
}
function Invoke-BISFExplorerCustomization {
 param($Config,[string]$ScriptRoot,$Logger)
 Test-BISFExplorerPreflight $ScriptRoot
 $remove=[bool]$Config.Explorer.RemoveQuickAccess;$classic=[bool]$Config.Explorer.ClassicContextMenu
 if(-not $remove -and -not $classic){return}
 if($remove){
  # Remove only known Quick Access/Home namespace registrations; preserve all other shell objects.
  $desktop=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop',$true)
  try {
   foreach($branch in @($desktop.GetSubKeyNames()|Where-Object {$_ -match '^NameSpace(?:_[0-9]+)?$'})){
    $ns=$desktop.OpenSubKey($branch,$true)
    try {
     foreach($id in '{679f85cb-0220-4080-b29b-5540cc05aab6}','{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'){
      $item=$ns.OpenSubKey($id)
      if($null -ne $item){
       try {$values=@(foreach($n in $item.GetValueNames()){[pscustomobject]@{Name=$n;Kind=[string]$item.GetValueKind($n);Value=$item.GetValue($n)}});$backup=$values|ConvertTo-Json -Compress -Depth 4}
       finally {$item.Dispose()}
       Write-BISFLog $Logger Info Explorer ("Removing HKLM Explorer Desktop\$branch\$id; original values=$backup")
       $ns.DeleteSubKeyTree($id,$false)
      }
     }
    } finally {$ns.Dispose()}
   }
  } finally {if($desktop){$desktop.Dispose()}}
  $k=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer')
  try {Write-BISFLog $Logger Info Explorer ('Previous HubMode='+[string]$k.GetValue('HubMode','<absent>'));$k.SetValue('HubMode',1,[Microsoft.Win32.RegistryValueKind]::DWord)}finally{$k.Dispose()}
 }
 $hostPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $scriptPath=Join-Path $ScriptRoot 'Apply-BISFUserSettings.ps1'
 if($scriptPath.Contains('"') -or $scriptPath.Contains('%')){throw 'Unsupported package path for Explorer sign-in hook'}
 $stub='"'+$hostPath+'" -NoLogo -NoProfile -NonInteractive -File "'+$scriptPath+'"'
 if($remove){$stub+=' -RemoveQuickAccess'}
 if($classic){$stub+=' -ClassicContextMenu'}
 $key=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\Microsoft\Active Setup\Installed Components\{855FB3AD-8D39-48B1-AFC5-51D75252E1BC}')
 try {
  $key.SetValue('','BISF Local Explorer settings');$key.SetValue('StubPath',$stub)
  $key.SetValue('Version','2026,10,20,1');$key.SetValue('IsInstalled',1,[Microsoft.Win32.RegistryValueKind]::DWord);$key.Flush()
 } finally {$key.Dispose()}
 Invoke-BISFUserCustomizations -RemoveQuickAccess:$remove -ClassicContextMenu:$classic
 Write-BISFLog $Logger Info Explorer "Applied current-user settings and registered Explorer sign-in settings for clone users. QuickAccessRemoved=$remove; ClassicContextMenu=$classic. Package must remain installed."
}
