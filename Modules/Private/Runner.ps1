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
function Confirm-BISFOperation {
    param($Caller, [string]$Target, [string]$Action)
    $Caller.ShouldProcess($Target,$Action)
}
function Invoke-BISFLocal {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [Parameter(Mandatory=$true)][string]$ScriptRoot,
        [ValidateSet('Validate','Prepare','Personalize')][string]$Mode='Validate'
    )
    $results=New-Object 'System.Collections.Generic.List[object]'
    $logger=$null; $lock=$null; $state=$null; $previousCM=$null
    $exitCode=0; $errorMessage=$null; $applying=$false; $stateTouched=$false
    $completionTouched=$false
    $currentStep='Preflight'
    try {
        $ScriptRoot=[IO.Path]::GetFullPath($ScriptRoot)
        $ConfigPath=Resolve-BISFPath $ConfigPath $ScriptRoot
        $config=Read-BISFConfig $ConfigPath $ScriptRoot
        $hash=(Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256 -ErrorAction Stop).Hash
        $inventory=Get-BISFInventory
        $plan=@(Get-BISFPlan $config $Mode)
        Test-BISFPreflight $config $Mode $plan $ScriptRoot $ConfigPath $inventory
        $statePath=Join-Path $ScriptRoot 'state/lifecycle.json'
        if ($Mode -ne 'Validate' -and -not $WhatIfPreference) { $lock=Enter-BISFLock }
        if ($Mode -eq 'Personalize') {
            $state=Read-BISFState $statePath
            if ($state.Status -ne 'Prepared') { throw 'Preparation did not complete successfully; refusing personalization.' }
            if ($state.ConfigHash -ne $hash) { throw 'Configuration changed since preparation. Prepare the master again with the intended configuration.' }
            Test-BISFCloneIdentity $state.Master $inventory.Identity
        }
        $logger=New-BISFLogger $config $Mode
        Write-BISFLog $logger Info Inventory ("OS={0}; Build={1}; Computer={2}; CcmExec={3}; Mode={4}" -f $inventory.Caption,$inventory.Build,$inventory.Identity.Name,$inventory.CMInstalled,$Mode)
        if ($Mode -eq 'Personalize' -and (Test-BISFCompletion $state $inventory.Identity)) {
            $results.Add([pscustomobject]@{Id='Personalize';Status='Skipped';Message='This clone already completed this preparation generation.'})
            Write-BISFLog $logger Info Personalize 'Skipped: already completed this generation.'
        } elseif ($Mode -eq 'Validate') {
            foreach ($step in $plan) {
                $results.Add([pscustomobject]@{Id=$step.Id;Status='Preview';Message=$step.Description})
                Write-BISFLog $logger Info $step.Id ('Validated plan: '+$step.Description)
            }
            Write-BISFLog $logger Info Validate 'Validation completed. No image operations applied.'
        } else {
            # Ask for all selected actions before beginning; a declined step cannot leave
            # a partially applied plan. WhatIf logs previews but never writes state.
            $declined=$false
            foreach ($step in $plan) {
                if ($step.Id -eq 'CloneGuard') { continue }
                if (-not (Confirm-BISFOperation $PSCmdlet $inventory.Identity.Name $step.Description)) {
                    if (-not $WhatIfPreference) { $declined=$true }
                }
            }
            if ($WhatIfPreference) {
                foreach ($step in $plan) {
                    $results.Add([pscustomobject]@{Id=$step.Id;Status='Preview';Message=$step.Description})
                    Write-BISFLog $logger Info $step.Id ('Preview: '+$step.Description)
                }
            } elseif ($declined) {
                $exitCode=2
                $results.Add([pscustomobject]@{Id='Apply';Status='Skipped';Message='An operation was declined; no changes applied.'})
                Write-BISFLog $logger Warning Apply 'Skipped: one or more operations were declined.'
            } else {
                $applying=$true
                if ((Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $hash) { throw 'Configuration changed during preflight.' }
                $needsState=($Mode -eq 'Prepare' -and (@($plan.Id) -contains 'Lifecycle'))
                if ($needsState) {
                    $state=New-BISFState $inventory.Identity $hash $config.ConfigurationManager.PrepareIdentityReset
                    $stateTouched=$true
                    Write-BISFState $statePath $state
                } elseif ($Mode -eq 'Prepare' -and (Test-Path -LiteralPath $statePath)) {
                    # An old successful generation must never survive a new preparation.
                    $state=Read-BISFState $statePath
                    $state.Status='Failed'; $state.Completion=$null; $stateTouched=$true
                    Write-BISFState $statePath $state
                }
                $protected=@($ScriptRoot,$ConfigPath,(Join-Path $ScriptRoot 'state'),$config.Logging.Path)
                foreach ($step in $plan) {
                    $currentStep=$step.Id
                    Write-BISFLog $logger Info $step.Id ('Starting: '+$step.Description)
                    switch ($step.Id) {
                        'WindowsTemp' {
                            $roots=Get-BISFTempRoots
                            $files=@(Get-BISFCleanupCandidates $roots.WindowsTemp $config.Cleanup.MinimumAgeDays $protected)
                            Remove-BISFTempFiles $files
                        }
                        'CurrentUserTemp' {
                            $roots=Get-BISFTempRoots
                            $files=@(Get-BISFCleanupCandidates $roots.CurrentUserTemp $config.Cleanup.MinimumAgeDays $protected)
                            Remove-BISFTempFiles $files
                        }
                        'CMPrepare' { $previousCM=Invoke-BISFCMPrepare }
                        'Lifecycle' {
                            if ($config.Personalization.Enabled) { Register-BISFStartupTask (Join-Path $ScriptRoot 'Invoke-BISF.ps1') $ConfigPath }
                            $state.Status='Prepared'
                            Write-BISFState $statePath $state
                        }
                        'CloneGuard' { Test-BISFCloneIdentity $state.Master $inventory.Identity }
                        'CMCloneReset' { Invoke-BISFCMCloneReset }
                        'CMStart' { Start-Service -Name CcmExec -ErrorAction Stop; Wait-BISFService 'Running' }
                        'Complete' {
                            $completionTouched=$true
                            $state.Completion=[pscustomobject]@{Generation=$state.Generation;Identity=$inventory.Identity}
                            Write-BISFState $statePath $state
                        }
                        'Shutdown' { Stop-Computer -Confirm:$false -ErrorAction Stop }
                    }
                    $results.Add([pscustomobject]@{Id=$step.Id;Status='Completed';Message=$step.Description})
                    Write-BISFLog $logger Info $step.Id 'Completed.'
                }
                if ($plan.Count -eq 0) { Write-BISFLog $logger Info Prepare 'No image operations enabled. Nothing was sealed or captured.' }
            }
        }
    } catch {
        $errorMessage=$_.Exception.Message
        if ($applying) { $exitCode=2 } else { $exitCode=1 }
        $results.Add([pscustomobject]@{Id=$currentStep;Status='Failed';Message=$errorMessage})
        if ($Mode -eq 'Prepare' -and $stateTouched) {
            try { $state.Status='Failed'; $state.Completion=$null; Write-BISFState $statePath $state }
            catch { Write-Warning "Could not invalidate preparation state: $($_.Exception.Message)" }
        }
        if ($Mode -eq 'Personalize' -and $completionTouched) {
            try { $state.Completion=$null; Write-BISFState $statePath $state }
            catch { Write-Warning "Could not clear clone completion state: $($_.Exception.Message)" }
        }
        if ($null -ne $previousCM) {
            try { Restore-BISFCMService $previousCM }
            catch { Write-Warning "Could not restore CcmExec: $($_.Exception.Message)" }
        }
        try { Write-BISFLog $logger Error $currentStep $errorMessage }
        catch { Write-Warning "Log write failed. Original error: $errorMessage" }
    } finally {
        Close-BISFLogger $logger
        Exit-BISFLock $lock
    }
    Write-Host ("BIS-F Local: Mode={0}, ExitCode={1}, Completed={2}, Failed={3}" -f $Mode,$exitCode,@($results | Where-Object Status -eq 'Completed').Count,@($results | Where-Object Status -eq 'Failed').Count)
    [pscustomobject]@{ExitCode=$exitCode;Mode=$Mode;Results=$results.ToArray();Error=$errorMessage}
}
