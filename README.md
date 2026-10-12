# BIS-F Local PowerShell edition

Unofficial, reduced-scope derivative based on the public EUCweb/BIS-F 7.1912.7
source. It prepares selected parts of a local master image using Windows PowerShell
cmdlets and .NET APIs. It does not capture, generalize, or provision an image and
is not a drop-in replacement for all upstream BIS-F integrations.

Target: elevated **64-bit Windows PowerShell 5.1**, Windows Server 2025 build 26100
or Windows 11 workstation build 22000 or later. The version gate is an eligibility
check, not certification of every Windows/agent combination. PowerShell 7 is for
portable development tests only; the runtime rejects it.

The package has no executable payloads, installer, GPO configuration, downloads or
external executable calls. Optional startup personalization launches only the built-in
Windows PowerShell host. Existing policy and network/security settings are preserved.

## Quick start

Copy the complete folder to a local location, such as `C:\Program Files\BISF-Local`.
Keep the module files and schema together with the entry script. Edit GlobalConfig.xml.
Open Windows PowerShell as administrator and run:

```powershell
Set-Location 'C:\Program Files\BISF-Local'
.\Invoke-BISF.ps1                       # Validate configuration and prerequisites
.\Invoke-BISF.ps1 -Mode Prepare -WhatIf # Preview the selected operations
.\Invoke-BISF.ps1 -Mode Prepare         # Apply the selected operations
```

**Defaults perform no cleanup or client resets and do not shut down the image.**
Enable the operations your image requires in XML. A successful empty run means only
that validation passed; it does not mean the image was sealed or captured.

For another config file:

```powershell
.\Invoke-BISF.ps1 -ConfigPath 'C:\ImageConfig\GlobalConfig.xml' -Mode Prepare -WhatIf
```

All relative paths in XML (and a relative `-ConfigPath`) resolve from the entry
script folder, regardless of the current working directory. Keep execution policy
and signing requirements in place; the package never bypasses them. Review/unblock
trusted downloaded source or sign it according to your organization's process.

## Logging

```xml
<Logging>
  <Enabled>true</Enabled>
  <Path>.\logs</Path>
</Logging>
```

This default writes to `logs` beside Invoke-BISF.ps1 and creates that directory when
needed. Set Enabled to false to disable file logging entirely, including error logs.
Console output and exit status remain available. There is no hidden fallback location.
Use an absolute local path or a relative path for a custom destination. UNC destinations
are available for interactive runs only; automatic SYSTEM personalization requires local
protected paths. Account permissions apply to the configured destination.

Each run gets a unique UTF-8 log with UTC timestamps, severity, operation and result.
Validate and -WhatIf may create diagnostic logs when logging is enabled, but perform
no image mutations. Configuration and preflight failures that occur before the logger
starts appear on the console. An unusable log destination prevents apply. A logging
failure during apply stops the run and suppresses shutdown.

Logs are not rotated automatically. Manage retention outside the preparation run.
The protected `state` directory is lifecycle metadata, **not logging**; disabling
logging does not disable state needed for personalization.

## Configuration reference

SchemaVersion must be `1`. All settings are required; unknown or duplicate elements,
invalid values and XML DTDs are rejected. Boolean values are XML booleans (`true`,
`false`, `1`, `0`), not PowerShell expressions. No command strings are accepted.

| Setting | Default | Behavior when enabled or changed |
|---|---|---|
| Logging.Enabled | true | File logging; false means no log file/directory writes |
| Logging.Path | `.\logs` | Script-relative or absolute log destination |
| Cleanup.WindowsTemp | false | Delete old files under `%SystemRoot%\Temp` |
| Cleanup.CurrentUserTemp | false | Delete old files under the executing user's LocalApplicationData\Temp; not every profile |
| Cleanup.MinimumAgeDays | 7 | Last-write age threshold, integer 1–3650 days |
| ConfigurationManager.PrepareIdentityReset | false | Stop CcmExec; remove SMS store certificates and `%SystemRoot%\SMSCFG.ini`; leave client stopped |
| ConfigurationManager.CloneTrustedRootKeyReset | false | Use CIM to delete TrustedRootKey instances during Personalize, then start CcmExec |
| Personalization.Enabled | false | Register the local SYSTEM startup task during Prepare |
| Preflight.BlockPendingReboot | true | Pending reboot blocks Prepare and its Validate preflight; false permits continuing |
| FinalAction | None | `Shutdown` requests shutdown after all selected Prepare operations succeed |

The cleanup traversal excludes reparse points and protects the package, configuration,
state and configured logs. It rechecks candidates before deletion. It does not delete
profiles, directories, event logs, update caches, or arbitrary user-supplied roots.
A file that changes, disappears, becomes inaccessible or becomes a link can fail the
run; retry after resolving active writers. Run with the image quiescent: path checks
are not a security sandbox against concurrent hostile filesystem changes.

SMS identity deletion is irreversible without an image backup. No other certificate
store, machine-wide crypto folder or Entra join is reset. The installed Configuration
Manager service, certificate store and configured CIM class must be available.
The certificate store may be empty, but must exist. Client version compatibility
still requires an actual deployment test.

## Personalization lifecycle

Enable the applicable ConfigurationManager options on the master. Enable
Personalization.Enabled for automatic startup execution, or leave it false and invoke
Personalize manually on the deployed clone. Prepare records an eligible generation
when either client option or automatic personalization is selected.

```powershell
# Run on a clone made from a successfully prepared master:
.\Invoke-BISF.ps1 -Mode Personalize -WhatIf
.\Invoke-BISF.ps1 -Mode Personalize
```

The package records master identity, preparation generation and a configuration hash
in `state\lifecycle.json`. Personalize requires a successful generation and unchanged
configuration. **Changing any XML content, including logging, requires running Prepare
again on the master before recapture.** This avoids silently changing reset behavior
on existing clones. Do not edit lifecycle state manually.

Personalize requires a changed computer name plus at least one changed valid MachineGuid
or SMBIOS UUID. The master is refused. Clones with copied identifiers are deliberately
blocked as ambiguous: resolve the provisioning identity behavior rather than weakening
this check. The same completed clone/generation becomes a no-op on later boots. A
failure does not mark completion; rerun after fixing the underlying issue.

For automatic startup, script/module/schema/config/state files and their parent paths
must be local, free of reparse points and protected against modification by untrusted
users. Owners must be SYSTEM, Administrators or TrustedInstaller. Use an appropriately
secured deployment folder; copying files there alone does not prove the ACLs are suitable.
The script checks permissions and refuses unsafe locations; it does not broadly rewrite
your package ACLs. It sets restricted ACLs only on its own new state files/directory.

The reserved task is `\BISF-Local-Personalize`, runs as SYSTEM at startup and uses the
built-in Windows PowerShell host. An unrelated task with that name is never overwritten.
The task remains installed; completion state makes later runs no-ops. A reboot of the
master will cause personalization to refuse the master, which is expected.

If nonpersistent storage discards state, personalization can run again at every boot.
This is not a universal once-per-machine guarantee for PVS/MCS. Verify actual persistence
and Configuration Manager identity behavior for your deployment technology.

## Results, failure handling and limits

- `0`: successful validation, preview, completion, or already-completed clone.
- `1`: configuration/preflight/identity/locking failure before apply.
- `2`: apply failure or a declined required operation.

Operations report Completed, Skipped, Preview or Failed. Confirmation is collected
before apply; one declined operation prevents the whole plan. A failure stops later
operations and prevents shutdown. Completed deletions are not rolled back. The runner
attempts to restore the previous CcmExec running state after failed preparation and
reports restoration failures. A prepared client remains stopped on success; capture
without restarting it, or personalize after deployment. Review failures before retrying.

The original RSS/offloading/DEP actions, GPO reads/writes and WMIC calls are absent.
Sysprep, license rearm tools, vendor optimizers, antivirus sealing executables, virtual
disk compaction, SDelete, DelProf2 and Entra leave tools are outside this package.
Use the supported PVS/MCS/vendor workflow for the steps those products require.
See UPSTREAM.md for the feature map and source provenance.

## Verification

Development tests require Pester 5 installed separately:

```powershell
.\Tests\Invoke-Tests.ps1
```

They exercise the real XML, logging, path traversal, state serialization and orchestration,
with mocked Windows service/CIM/task operations. Parser and source audit tests also check
for forbidden execution paths and binary payloads. A static scan is not a proof against
arbitrary malicious edits; keep the package administrator-controlled.

The delivered TEST-RESULTS.md records the actual test environment and results. Linux
PowerShell tests cannot establish Windows PowerShell 5.1 runtime behavior or certify a
Windows image. Before production, use a disposable clone and record:

1. Windows edition/build, VDA/PVS/MCS versions, VM tools/NIC driver, profile agent,
   Configuration Manager version, and any separately applied optimizer template.
2. Validate and Prepare -WhatIf outputs; enabled/disabled/custom-path logging behavior.
3. Actual Prepare changes and unchanged RSS, offloading, DEP and security settings.
4. Capture/provisioning with the intended product and first-boot personalization.
5. Subsequent cold boots and persistence of completion state/client identity.
6. Before/after logon duration, SMB throughput, profile attachment and VDA registration.
7. Scheduled task execution under SYSTEM and all applicable signing/execution policies.

License: GNU GPLv3; no warranty. See LICENSE and UPSTREAM.md.
