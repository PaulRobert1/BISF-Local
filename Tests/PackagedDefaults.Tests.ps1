BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 foreach($name in 'Configuration','Runner','Citrix','Finalization','LogCleanup'){. "$root/Modules/Private/$name.ps1"}
}
Describe 'Requested packaged preparation defaults' {
 It 'builds the complete compatible cleanup plan from the shipped XML' {
  $c=Read-BISFConfig (Join-Path $root 'GlobalConfig.xml') $root
  {Test-BISFOperatorSealSettings $c;Test-BISFCitrixSettings $c;Test-BISFLogCleanupSettings $c}|Should -Not -Throw
  $ids=@(Get-BISFPlan $c Prepare|ForEach-Object Id)
  ($ids -join ',')|Should -Be 'WindowsTemp,CurrentUserTemp,RecycleBin,UserProfiles,ExplorerSettings,LogCleanup,OperatorFinalize'
  $c.LogCleanup.WindowsEventLogs|Should -BeTrue
  $c.LogCleanup.BISFLogs|Should -BeFalse
  $c.FinalAction|Should -Be 'Shutdown'
 }
 It 'keeps Configuration Manager and incompatible or unverifiable operations disabled' {
  $c=Read-BISFConfig (Join-Path $root 'GlobalConfig.xml') $root
  $c.ConfigurationManager.PrepareIdentityReset|Should -BeFalse
  $c.ConfigurationManager.CloneTrustedRootKeyReset|Should -BeFalse
  $c.Personalization.Enabled|Should -BeFalse
  $c.Citrix.VDA.StopBeforeShutdown|Should -BeFalse
  $c.Servicing.ComponentCleanup|Should -BeFalse
  $c.Preflight.BlockPendingReboot|Should -BeTrue
  $c.Preflight.BlockOtherLoadedProfiles|Should -BeTrue
 }
 It 'allows cleanup and shutdown to be disabled through XML' {
  [xml]$xml=Get-Content (Join-Path $root 'GlobalConfig.xml') -Raw
  foreach($n in 'WindowsTemp','CurrentUserTemp','RecycleBin','UserProfiles'){$xml.BISF.Cleanup.$n='false'}
  $xml.BISF.LogCleanup.WindowsEventLogs='false';$xml.BISF.LogCleanup.BISFLogs='false'
  $xml.BISF.Explorer.RemoveQuickAccess='false';$xml.BISF.Explorer.ClassicContextMenu='false'
  $xml.BISF.Finalization.RemoveOperatorProfile='false';$xml.BISF.FinalAction='None'
  $p=Join-Path $TestDrive 'disabled.xml';$xml.Save($p);$c=Read-BISFConfig $p $root
  @(Get-BISFPlan $c Prepare).Count|Should -Be 0
 }
}
