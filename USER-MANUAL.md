# BISF Local user manual

BISF Local prepares a Windows master image by running the cleanup options you select. Image capture and Citrix provisioning remain separate steps.

**Status:** release candidate; production acceptance is still incomplete.

## 1. Set up

1. Back up or snapshot the master. Finish Windows updates and required restarts.
2. Copy the **entire package** to `C:\Program Files (x86)\BISF-Local` or `C:\Program Files\BISF-Local`. Keep the EXE, scripts, modules, XML and schema together. When updating, preserve your custom configuration and existing `state` and `logs` contents. If an earlier operator-seal task or state remains, use the failure guidance below before replacing any program files.
3. Run **BISF-Local.exe** and accept the standard Windows administrator prompt if shown. Normal Prepare initializes permissions inside its own installation before loading the preparation runtime. No separate permission-repair command is needed. Direct script use still requires elevated **64-bit Windows PowerShell 5.1**; PowerShell 7 is not supported for preparation.
4. Keep other users signed out and prevent new logons during preparation.

```powershell
Set-Location 'C:\Program Files\BISF-Local'
```

Preparation runs fully offline with local Windows APIs and installed agents. It downloads nothing. Broker connections and network profile storage need their normal network access after deployment.

## EXE launcher

The package includes `BISF-Local.exe` (Windows x64). Keep it beside `Invoke-BISF.ps1` and the rest of the package. For ordinary preparation, run:

```text
BISF-Local.exe
```

Optional check and preview modes remain available:

```text
BISF-Local.exe -Mode Validate
BISF-Local.exe -Mode Prepare -WhatIf
BISF-Local.exe
BISF-Local.exe -Mode Prepare
```

**No arguments runs Prepare and applies the enabled cleanup.** Windows requests administrator approval when elevation is needed. Before the preparation runtime is loaded, the package checks and repairs its own permissions, preserving ordinary-user read access to code and keeping state and logs private. Original permissions are backed up when a repair is needed. Windows parent folders and external configuration/log locations are not rewritten. A remaining trust or environment error stops preparation and identifies its cause.

With operator-profile removal enabled, successful preparation waits for a healthy SYSTEM finalizer to acknowledge readiness, then requests your normal Windows sign-out automatically. The SYSTEM task waits for the profile to unload, removes and verifies it, finishes selected log cleanup and shuts down. No new configuration flag or switch is needed; your existing selected options are honored. Use `BISF-Local.exe -Mode Validate` for checks only. Validate and WhatIf do not repair permissions. The EXE uses installed Windows PowerShell 5.1, forwards arguments and returns its exit code. It downloads no dependencies and preserves execution policy. Configure cleanup first as described below. Use `BISF-Local.exe --help` for usage.

## 2. Choose the cleanup

Edit the existing `GlobalConfig.xml`; keep its element order. Windows Update component cleanup, temp, user-profile, Recycle Bin, event-log and operator-profile cleanup default to `true`; `FinalAction` defaults to `Shutdown`. BISF execution logs are retained (`LogCleanup.BISFLogs=false`). Both Explorer options below default to `true`. Set unwanted options to `false` before running. Configuration Manager resets, clone personalization and the separate VDA-stop option remain disabled. These cannot all be combined with operator-profile finalization.

| Setting | What it does |
| --- | --- |
| `Cleanup.WindowsTemp` | Cleans old files from Windows Temp. |
| `Cleanup.CurrentUserTemp` | Cleans old files from the current user's Temp folder. |
| `Cleanup.MinimumAgeDays` | Sets the temporary-file age threshold; default 7 days. This does not limit profile deletion by age. |
| `Cleanup.UserProfiles` | Removes eligible unloaded local profiles through Windows. |
| `Cleanup.RecycleBin` | Empties the invoking user's system-drive Recycle Bin. |
| `Servicing.ComponentCleanup` | Enabled by default. Removes superseded Windows update components through the inbox DISM PowerShell cmdlet before other cleanup and automatic sign-out. |
| `Servicing.TimeoutMinutes` | Completion-time budget, default 75 minutes. Active servicing is allowed to finish; an over-budget return blocks further preparation. |
| `LogCleanup.WindowsEventLogs` | Clears enabled Administrative/Operational channels, including vendor channels; preserves Security and disabled/Analytic/Debug channels. |
| `LogCleanup.BISFLogs` | Leave false to retain detailed execution logs on the master. |
| `Finalization.RemoveOperatorProfile` | After successful Prepare and SYSTEM readiness, requests normal sign-out automatically, removes the unloaded operator profile and shuts down. |
| `Explorer.RemoveQuickAccess` | Removes Quick Access/Home from Explorer; opens This PC. |
| `Explorer.ClassicContextMenu` | Requests the classic right-click menu at Explorer sign-in. |
| `FinalAction` | `None` leaves Windows running; `Shutdown` requests shutdown after successful preparation. |

Profiles displayed as **Account Unknown** are eligible when Windows reports a valid user SID and a safe, unloaded profile. System, loaded, excluded and protected profiles are preserved; missing or unsafe paths are refused. Review the preview before deletion.

Windows Update cleanup now uses `Dism\Repair-WindowsImage -Online -StartComponentCleanup -NoRestart -LimitAccess` and waits for the actual call to return. Preflight checks the installed inbox DISM cmdlet and its required parameters. If that Windows build lacks `-StartComponentCleanup`, preparation stops before image cleanup with an actionable compatibility error. The operation removes superseded update components; it does not install updates or use ResetBase. See [Microsoft's cmdlet documentation](https://learn.microsoft.com/en-us/powershell/module/dism/repair-windowsimage?view=windowsserver2025-ps).

Complete update installation and required reboots before preparation. Cleanup errors, unknown results, a restart requirement or exceeding the completion-time budget block sign-out and shutdown. The budget is checked when the synchronous operation returns; BISF never interrupts an active servicing operation. If you keep an older customized XML, set its existing `Servicing.ComponentCleanup` value to `true` to enable this new package default; missing legacy settings remain disabled.

Keep pending-reboot and other-loaded-profile checks enabled. Leave `Personalization.Enabled`, both `ConfigurationManager` reset options, and `Citrix.VDA.StopBeforeShutdown` false while operator-profile finalization is enabled.

To choose log cleanup using checkboxes:

```powershell
.\Configure-BISF-LogCleanup.ps1
```

This only saves configuration. Both log-cleanup options require `FinalAction=Shutdown`. Security is preserved. Permission-protected channels are retained with a warning; other clearing failures block shutdown. Explorer settings apply to new and existing users at Explorer sign-in; keep the installed package in place. Disabling an Explorer option skips it; it does not reverse settings already applied. Shell behavior can vary between Windows builds.

## 3. Preview and prepare

Run these commands one at a time. Resolve errors and review the preview before applying:

```powershell
.\Invoke-BISF.ps1 -Mode Validate
.\Invoke-BISF.ps1 -Mode Prepare -WhatIf
.\Invoke-BISF.ps1 -Mode Prepare
```

For immediate shutdown without operator-profile removal, keep the operator session unlocked until completion. A locked session can cause Windows to refuse shutdown; BISF reports failure rather than forcing it.

`Validate` and `-WhatIf` do not apply image changes or request sign-out; enabled diagnostic logging can write logs. A failed or declined preparation also does not request sign-out. Review every profile and cleanup path shown. To use another local configuration, add `-ConfigPath 'C:\ProtectedFolder\MyConfig.xml'` to each command.

## 4. Remove the operator profile if required

Use a regular local or domain administrator account with an eligible profile, not the built-in Administrator. Set:

- `Cleanup.UserProfiles=true`
- `Finalization.RemoveOperatorProfile=true`
- `FinalAction=Shutdown`
- `Citrix.VDA.StopBeforeShutdown=false`
- `Personalization.Enabled=false` and both `ConfigurationManager` reset options `false`

Save your work and close other applications before applying `Prepare`. Sign in directly as the preparation administrator: using different administrator credentials inside another user's desktop is refused. The same checks apply to console and RDP sessions.

After successful `Prepare`, BISF waits up to 30 seconds for the protected SYSTEM worker to acknowledge readiness. After releasing the preparation lock, it rechecks the worker and your current session and requests **normal Windows sign-out automatically**. You do not need a separate sign-out command. Do not change the configuration or package while the task waits.

The request does not force applications closed. Unsaved work can block or cancel sign-out, and disconnecting RDP alone leaves the profile loaded. The SYSTEM task waits for all required profiles and references to unload, removes and verifies the operator profile, performs selected final cleanup, then requests shutdown. The default unload timeout is 30 minutes. A readiness failure or blocked unload causes no forced sign-out or shutdown. Do not run `Finalize` manually.

Native console and RDP acceptance of this automatic handoff has not been run in the current development environment. Follow `ACCEPTANCE-TESTING.md` on disposable Windows images before production use.

## 5. Capture and check a clone

Capture the successfully prepared, powered-off master through your normal imaging workflow. For Citrix MCS, let MCS handle machine identity; do not run Sysprep as a BISF step.

On a test clone, run:

```powershell
.\Invoke-BISF.ps1 -Mode VerifyClone
```

This provides read-only local inventory. Also verify broker registration, an actual HDX logon, profile attachment and persistence, activation and repeated boots. Check WEM registration and synchronization only when a WEM backend is configured. Newer Windows and agent versions being accepted by BISF does not establish vendor compatibility.

## 6. If something fails

Logs are under `.\logs` by default, unless changed or selected for cleanup.

| Exit code | Meaning |
| --- | --- |
| `0` | The requested operation succeeded; with operator sealing, sign-out was requested and SYSTEM completion must still be observed. An accepted request does not prove profile removal or shutdown. |
| `1` | Configuration, preflight, identity or locking error. |
| `2` | An operation failed or a required action was declined. |

Resolve the reported cause. Preserve logs and any `state` files or scheduled tasks. Do not delete failure state, force shutdown, or manually delete leftover profile folders to make a failed seal appear successful. Cleanup cannot be undone; restore the backup after a partial failure when necessary.

If a previous operator-seal attempt is pending, an accepted SYSTEM worker may still be running even after a readiness timeout. Do not extract an update over the installation or assume rerunning recovers it. Preserve `state`, logs and task results. An administrator must inspect the exact owned task and worker, use the failure/rollback procedure and confirm any stopped worker has exited before replacing program files. Do not delete pending state to bypass the refusal; restore the saved image when recovery is uncertain.
