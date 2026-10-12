# BIS-F Local, unofficial derivative. Modified 2026-10-12. GPL-3.0; see LICENSE.
function Get-BISFPlan {
    param($Config, [string]$Mode)
    $steps = New-Object 'System.Collections.Generic.List[object]'
    if ($Mode -eq 'Personalize') {
        $steps.Add([pscustomobject]@{Id='CloneGuard';Description='Verify prepared generation and clone identity'})
        if ($Config.ConfigurationManager.CloneTrustedRootKeyReset) { $steps.Add([pscustomobject]@{Id='CMCloneReset';Description='Reset Configuration Manager TrustedRootKey through CIM'}) }
        if ($Config.ConfigurationManager.PrepareIdentityReset -or $Config.ConfigurationManager.CloneTrustedRootKeyReset) { $steps.Add([pscustomobject]@{Id='CMStart';Description='Start Configuration Manager client'}) }
        $steps.Add([pscustomobject]@{Id='Complete';Description='Record successful clone personalization'})
    } else {
        foreach ($id in 'WindowsTemp','CurrentUserTemp') {
            if ($Config.Cleanup.$id) { $steps.Add([pscustomobject]@{Id=$id;Description="Remove old temporary files: $id"}) }
        }
        if ($Config.ConfigurationManager.PrepareIdentityReset) { $steps.Add([pscustomobject]@{Id='CMPrepare';Description='Stop CcmExec and remove SMS client identity'}) }
        if ($Config.Personalization.Enabled -or $Config.ConfigurationManager.PrepareIdentityReset -or $Config.ConfigurationManager.CloneTrustedRootKeyReset) {
            $steps.Add([pscustomobject]@{Id='Lifecycle';Description='Record a preparation generation and optional startup task'})
        }
        if ($Config.FinalAction -eq 'Shutdown') { $steps.Add([pscustomobject]@{Id='Shutdown';Description='Request computer shutdown'}) }
    }
    $steps.ToArray()
}
