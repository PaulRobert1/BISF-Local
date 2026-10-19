# BISF Local user manual

BISF Local prepares a Windows master image by running the cleanup options you select. Image capture and Citrix provisioning remain separate steps.

**Status:** release candidate; production acceptance is still incomplete.

## 1. Set up

1. Back up or snapshot the master. Finish Windows updates and required restarts.
2. Copy the **entire package** to `C:\Program Files\BISF-Local`. Keep the scripts, modules, XML and schema together. Use a local folder controlled by Administrators and SYSTEM, outside any profile being deleted.
3. Open **64-bit Windows PowerShell 5.1 as administrator**. PowerShell 7 is not supported for preparation.
4. Keep other users signed out and prevent new logons during preparation.

```powershell
Set-Location 'C:\Program Files\BISF-Local'
```

Preparation runs fully offline with local Windows APIs and installed agents. It downloads nothing. Broker connections and network profile storage need their normal network access after deployment.

## EXE launcher

The package includes `BISF-Local.exe` (Windows x64). Keep it beside `Invoke-BISF.ps1` and the rest of the package. From an elevated command prompt, run:

```text
BISF-Local.exe
BISF-Local.exe -Mode Prepare -WhatIf
BISF-Local.exe -Mode Prepare
```

No arguments runs validation. The EXE uses installed Windows PowerShell 5.1, forwards arguments and returns its exit code. It does not install the framework, automatically elevate, download dependencies, or bypass execution policy. Configure cleanup first as described below. Use `BISF-Local.exe --help` for usage.

## 2. Choose the cleanup

Edit the existing `GlobalConfig.xml`; keep its element order. Cleanup options default to `false`, and `FinalAction` defaults to `None`.

| Setting | What it does |
| --- | --- |
| `Cleanup.WindowsTemp` | Cleans old files from Windows Temp. |
| `Cleanup.CurrentUserTemp` | Cleans old files from the current user's Temp folder. |
| `Cleanup.MinimumAgeDays` | Sets the temporary-file age threshold; default 7 days. This does not limit profile deletion by age. |
| `Cleanup.UserProfiles` | Removes eligible unloaded local profiles through Windows. |
| `Cleanup.RecycleBin` | Empties the invoking user's system-drive Recycle Bin. |
| `LogCleanup.WindowsEventLogs` | Clears Application, System and Setup logs. |
| `LogCleanup.BISFLogs` | Removes BISF-generated diagnostic logs. |
| `Finalization.RemoveOperatorProfile` | Removes the operator's eligible profile after normal sign-out, then shuts down. |
| `FinalAction` | `None` leaves Windows running; `Shutdown` requests shutdown after successful preparation. |

Profiles displayed as **Account Unknown** are eligible when Windows reports a valid user SID and a safe, unloaded profile. System, loaded, excluded and protected profiles are preserved; missing or unsafe paths are refused. Review the preview before deletion.

Keep `Servicing.ComponentCleanup=false`. Perform component servicing separately: the optional scheduled-task integration currently refuses sealing because it cannot reliably prove completion.

Keep pending-reboot and other-loaded-profile checks enabled. For ordinary Citrix MCS use, leave `Personalization.Enabled` and both `ConfigurationManager` reset options `false`.

To choose log cleanup using checkboxes:

```powershell
.\Configure-BISF-LogCleanup.ps1
```

This only saves configuration. Both log-cleanup options require `FinalAction=Shutdown`. Security and dedicated Citrix/WEM/FSLogix event channels are preserved.

## 3. Preview and prepare

Run these commands one at a time. Resolve errors and review the preview before applying:

```powershell
.\Invoke-BISF.ps1 -Mode Validate
.\Invoke-BISF.ps1 -Mode Prepare -WhatIf
.\Invoke-BISF.ps1 -Mode Prepare
```

For immediate shutdown without operator-profile removal, keep the operator session unlocked until completion. A locked session can cause Windows to refuse shutdown; BISF reports failure rather than forcing it.

`Validate` and `-WhatIf` do not apply image changes; enabled diagnostic logging can write logs. Review every profile and cleanup path shown. To use another local configuration, add `-ConfigPath 'C:\ProtectedFolder\MyConfig.xml'` to each command.

## 4. Remove the operator profile if required

Use a regular local or domain administrator account with an eligible profile, not the built-in Administrator. Set:

- `Cleanup.UserProfiles=true`
- `Finalization.RemoveOperatorProfile=true`
- `FinalAction=Shutdown`
- `Citrix.VDA.StopBeforeShutdown=false`
- `Personalization.Enabled=false` and both `ConfigurationManager` reset options `false`

After successful `Prepare`, follow the instruction to **sign out**. Disconnecting RDP is insufficient. Do not change the configuration or package while the task waits.

The SYSTEM task waits for profiles to unload, removes and verifies the operator profile, performs selected final cleanup, then requests shutdown. The default sign-out timeout is 30 minutes. Do not run `Finalize` manually.

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
| `0` | The requested operation succeeded; a staged operator seal still needs sign-out and finalizer completion. |
| `1` | Configuration, preflight, identity or locking error. |
| `2` | An operation failed or a required action was declined. |

Resolve the reported cause. Preserve logs and any `state` files or scheduled tasks. Do not delete failure state, force shutdown, or manually delete leftover profile folders to make a failed seal appear successful. Cleanup cannot be undone; restore the backup after a partial failure when necessary.
