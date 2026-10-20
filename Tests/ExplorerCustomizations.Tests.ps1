BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . "$root/Modules/Private/ExplorerCustomizations.ps1"
}
Describe 'Explorer user customization scope' {
 BeforeEach { Mock Set-BISFUserRegistryValue {} }
 It 'makes no changes when both options are disabled' {
  Invoke-BISFUserCustomizations -RemoveQuickAccess:$false -ClassicContextMenu:$false
  Should -Invoke Set-BISFUserRegistryValue -Times 0
 }
 It 'sets This PC and hides both Quick Access and Home without deleting user files' {
  Invoke-BISFUserCustomizations -RemoveQuickAccess
  Should -Invoke Set-BISFUserRegistryValue -Times 1 -ParameterFilter {$Name -eq 'LaunchTo' -and $Value -eq 1}
  Should -Invoke Set-BISFUserRegistryValue -Times 2 -ParameterFilter {$Name -eq 'System.IsPinnedToNameSpaceTree' -and $Value -eq 0}
  Should -Invoke Set-BISFUserRegistryValue -Times 0 -ParameterFilter {$Key -match '86ca1aa0'}
 }
 It 'sets an explicitly empty classic-menu COM registration, not a missing default value' {
  Invoke-BISFUserCustomizations -ClassicContextMenu
  Should -Invoke Set-BISFUserRegistryValue -Times 1 -ParameterFilter {$Key -eq 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -and $Name -eq '' -and $Value -ceq '' -and $Kind -eq 'String'}
 }
}
