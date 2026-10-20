# BIS-F Local PowerShell edition

**Current package defaults:** running `BISF-Local.exe` or `Invoke-BISF.ps1` without a mode now runs **Prepare**. Temp, user-profile, Recycle Bin, Windows/BISF log and operator-profile cleanup are enabled, with shutdown after normal operator sign-out. Disable unwanted actions in `GlobalConfig.xml`. Configuration Manager resets, clone personalization, separate VDA stopping and unverifiable component cleanup remain off. Use `-Mode Validate` for checks only or `-Mode Prepare -WhatIf` for preview. Omitted legacy XML options still default to false in the parser.


For setup and everyday operation, see the [user manual](USER-MANUAL.md).

Unofficial, reduced-scope derivative based on the public EUCweb/BIS-F 7.1912.7
source. It prepares selected parts of a local master image using Windows PowerShell
cmdlets and .NET APIs. It does not capture, generalize, or provision an image and
is not a drop-in replacement for all upstream BIS-F integrations.

Target: elevated **64-bit Windows PowerShell 5.1**, Windows Server 2025 or newer
or Windows 11 workstation or newer. The version gate is an eligibility
check, not certification of every Windows/agent combination. PowerShell 7 is for
portable development tests only; the runtime rejects it.

The package includes an optional x64 `BISF-Local.exe` launcher for the adjacent PowerShell entry point. It has no installer, GPO configuration, downloads or
vendor executable calls. The launcher starts only the built-in Windows PowerShell host. Optional startup personalization launches only the built-in
Windows PowerShell host. Existing policy and network/security settings are preserved.

**Draft acceptance gate:** the complete sign-out, SYSTEM profile removal, selected
log cleanup, shutdown and clone workflow still requires disposable Windows Server
2025 and Windows 11 testing. See [ACCEPTANCE-TESTING.md](ACCEPTANCE-TESTING.md) for
the per-platform evidence matrix and failure cases. Do not use SWCTXMASTER05 for
destructive testing or mark PR #2 ready based on mocked CI alone.
[REVIEW-2026-10-15.md](REVIEW-2026-10-15.md) records the independent findings
and regression evidence.

## Additional master-image maintenance and shutdown finalization

These features are deliberately **off by default**, except the read-only
`BlockOtherLoadedProfiles` readiness check in the *new* default configuration.
Older XML lacking these elements remains compatible and gets non-destructive
defaults. You must deploy the **entire updated package** (XSD, modules, entry
script, XML) rather than copying a single module onto an older installation.

| Configuration setting | Default | Effect if enabled |
| --- | --- | --- |
| `Cleanup.WindowsTemp` | true | Age-based files under `%windir%\Temp` |
| `Cleanup.CurrentUserTemp` | true | Age-based files under operator profile's Temp |
| `Cleanup.UserProfiles` | true | Unloaded, non-system user profiles via Windows profile provider |
| `Cleanup.RecycleBin` | true | Empty **invoking user's** system-drive Recycle Bin through `Clear-RecycleBin` |
| `Servicing.ComponentCleanup` | false | Run Windows' built-in `\Microsoft\Windows\Servicing\StartComponentCleanup` maintenance task; fail closed when completion cannot be verified |
| `Servicing.TimeoutMinutes` | 75 | Refuse further operations if servicing does not finish inside this bound |
| `Preflight.MinimumSystemDriveFreeGB` | 0 | Fail preflight when system-drive free space is below this threshold |
| `Preflight.BlockOtherLoadedProfiles` | false if omitted, true in new XML | Refuse preparation if other non-system profiles remain loaded or referenced; repeat checks during preparation and before final sealing |
| `Finalization.RemoveOperatorProfile` | true | Two-phase SYSTEM finalizer (normal sign-out, then delete operator profile and shut down) |
| `Finalization.TimeoutMinutes` | 30 | Maximum period the SYSTEM task waits for a clean operator sign-out |

### Safe Windows Update and disk cleanup

Windows component-store maintenance is **not** the same as clearing
`SoftwareDistribution` or deleting WinSxS directories. When enabled, BISF
invokes the Microsoft-installed scheduled task
`\Microsoft\Windows\Servicing\StartComponentCleanup`. A new LastRunTime,
Ready state and result zero cannot distinguish successful completion from a
cancelled COM-handler run. BISF therefore refuses further image operations when
completion is unverifiable, as well as on failure or timeout. See the servicing
limitation below; there is currently no verified automatic success path.
This task may honor an update retention period and is not
guaranteed to reclaim all space. The script does not run DISM.exe, change
Windows Update services, perform `/ResetBase`, delete rollback packages
or remove update caches manually. It does not reset WSUS policy.

With RecycleBin enabled, `Clear-RecycleBin` applies only to the operator's
current system-drive Recycle Bin. Temporary-file cleanup is already
bounded by `MinimumAgeDays`; deleting inactive Windows profiles uses
the provider instead of recursively deleting `C:\Users`.

### Optional final-stage log hygiene

Run Configure-BISF-LogCleanup.ps1 in elevated Windows PowerShell 5.1
for two checkbox options. Saving this dialog updates GlobalConfig.xml
only and never executes image preparation.

The editor validates XML before saving, refuses to overwrite a configuration
changed while the dialog was open, and validates a same-directory temporary
file before atomic replacement. A failed replacement leaves the original intact.
Configuration/schema paths must be local, protected and free of reparse points.
It never changes FinalAction to enable shutdown implicitly. Prepare binds parsed
settings and confirmations to one config hash, rechecks it before later operations
and final sealing, and passes that same hash into operator staging. An edit during
servicing must be reviewed through a new Prepare; it cannot silently enable a log
option in the SYSTEM worker.

Enabled Administrative and Operational event channels, including vendor channels, are cleared at final sealing. Security and disabled/Analytic/Debug channels are preserved. Each result is recorded in the BISF execution log; a failure blocks shutdown. Windows can generate new events during shutdown.

`LogCleanup.WindowsEventLogs=true`, `LogCleanup.BISFLogs=false`: detailed BISF execution logs remain on the master. Log cleanup requires `FinalAction=Shutdown`. With operator-profile removal enabled, final cleanup and automatic shutdown follow normal operator sign-out.

`Explorer.RemoveQuickAccess=true` removes Quick Access/Home navigation registrations and opens Explorer at This PC. `Explorer.ClassicContextMenu=true` requests the classic context menu using the per-user shell registration. Both apply to the operator and through Active Setup at Explorer sign-in for other users. Keep the package at its protected installation path. Windows shell behavior can vary by build; setting either option false skips application and does not undo existing settings.

### Two-phase deletion of the operator's own profile

**DO NOT enable on a production master before validating it on a disposable
copy and confirming the package/state directory ACLs.** This feature is
more operationally risky than ordinary inactive-profile cleanup because
the active operator must sign out before their own profile can be deleted.

Configure:

```xml
<Cleanup>
  <WindowsTemp>true</WindowsTemp>
  <CurrentUserTemp>true</CurrentUserTemp>
  <UserProfiles>true</UserProfiles>
  <MinimumAgeDays>7</MinimumAgeDays>
  <RecycleBin>false</RecycleBin>
</Cleanup>
<Servicing>
  <ComponentCleanup>false</ComponentCleanup>
  <TimeoutMinutes>75</TimeoutMinutes>
</Servicing>
<Preflight>
  <BlockPendingReboot>true</BlockPendingReboot>
  <MinimumSystemDriveFreeGB>10</MinimumSystemDriveFreeGB>
  <BlockOtherLoadedProfiles>true</BlockOtherLoadedProfiles>
</Preflight>
<Finalization>
  <RemoveOperatorProfile>true</RemoveOperatorProfile>
  <TimeoutMinutes>30</TimeoutMinutes>
</Finalization>
<FinalAction>Shutdown</FinalAction>
```

The XML fragments above must be placed in the element order prescribed
by `GlobalConfig.xsd`. Also set `Personalization.Enabled=false`,
`ConfigurationManager.PrepareIdentityReset=false`,
`ConfigurationManager.CloneTrustedRootKeyReset=false` and
`Citrix.VDA.StopBeforeShutdown=false`.

**Process:**
1. Capture a VM checkpoint/backup while retaining a recovery route; complete
   Windows Update servicing and reboots beforehand.
2. Use a normal elevated **domain/local admin account with RID >=1000**
   whose local profile is eligible for removal; the built-in RID-500
   Administrator and system accounts are not automatically eligible.
3. Place BISF-Local under an **administrators/SYSTEM-controlled directory**
   outside the operator profile. The XML, modules, state and enabled log
   path must not be writable by untrusted users and must not reside inside
   the profile about to be deleted.
4. Run `Invoke-BISF.ps1 -Mode Validate`, then
   `Invoke-BISF.ps1 -Mode Prepare -WhatIf` to inspect all intended actions.
5. Run `Invoke-BISF.ps1 -Mode Prepare` only after explicit operator review.
   If preparation succeeds it writes a protected one-shot state file,
   registers and **starts** a SYSTEM scheduled task named
   `BISF-Local-OperatorSeal` with **no automatic trigger**, and prints
   the instruction to sign out.
6. **Sign out**, do not merely disconnect RDP. The task waits until no
   nonsystem Windows user profiles are loaded or referenced. Unknown nonsystem
   lifecycle flags are an error. It validates it is running
   as SYSTEM on the *same master*, checks the config SHA256 and target SID,
   verifies the operator profile is now unloaded, and rechecks eligibility.
7. It removes the operator profile through `Remove-CimInstance`, verifies
   that it is no longer registered, unregisters its task, removes its
   staging state, and only then asks Windows to shut down. If any step
   fails or the timeout expires, **it will not request shutdown**.

Preflight rejects retained operator state and checks the module directory,
schema and imported files before ordinary cleanup begins; registration repeats
the checks. The final provider object passed to deletion is itself checked for
the staged SID/path, reserved/special status, loaded state, references and links.
`Finalize -WhatIf` returns a preview before state reads, logging or image changes;
an explicitly declined `Finalize -Confirm` also performs no work. Normal Prepare
remains the supported operator entry point for a real seal.

Ordinary profile selection protects profiles containing the package, config,
state, configured logs or detected WEM cache. Operator finalization rejects an
operator target containing these dependencies. Duplicate direct profile paths
and mismatched provider SIDs fail closed. Session scans are repeated around
preparation operations, but do not lock out Windows logons: maintain exclusive
access through the normal Citrix maintenance process for the entire seal.

No task-triggered logoff, forced session termination, unguarded file-tree
deletion, scheduled startup after imaging, or automatic deletion on MCS
clones is performed. A timeout or failed stage may leave a protected
`state\operator-seal.json` and/or scheduled task for an administrator to
investigate. **Do not delete those files/tasks blindly.** Review the
`Finalize` log under your configured logging path and restore the test
snapshot when uncertain. A shutdown request can fail after profile
deletion; that cannot be rolled back by this tool.

This workflow is **not** validated yet on a real MCS master or Windows 11
template. Mocked Pester tests cannot certify Task Scheduler lifetime,
Win32_UserProfile unload timing, or machine image capture behavior.
Always power off and snapshot through a supported Citrix MCS workflow.

References:
- [Microsoft: Clean Up the WinSxS Folder](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder)
- [Microsoft: Clear-RecycleBin](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/clear-recyclebin?view=powershell-5.1)
- [Microsoft: Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask)
- [Microsoft: Delete a Windows user profile](https://learn.microsoft.com/en-us/troubleshoot/windows-server/user-profiles-and-logon/delete-user-profile)

### Post-capture MCS clone verification (read-only)

On a disposable, already-provisioned Windows Server 2025 or Windows 11
MCS test clone, copy the *complete* BISF-Local package and run from an
elevated 64-bit Windows PowerShell 5.1 console:

```powershell
.\Invoke-BISF.ps1 -Mode VerifyClone
```

This does not run Prepare, profile deletion, Windows servicing, scheduled
tasks or shutdown, and it creates no BIS-F log file. It reports:
- Local OS/Windows release, hostname, pending reboot, system-disk free space.
- Domain-join status, installed VDA service state and Machine Identity component.
- Local WEM host/cache state and FSLogix/Citrix Profile Management services.

**Important:** the resulting report explicitly marks actual **VDA
registration**, successful **ICA desktop/application launch**, **WEM
registration/setting synchronization**, Windows activation, and actual
FSLogix container attachment as **NotVerified**. A running BrokerAgent
alone cannot establish a registered VDA; confirm the broker state in
Citrix Studio/Director/Monitor and perform an end-to-end session logon.
Verify WEM agent registration and cache synchronization in WEM
administration. Check attached profile state and Windows activation
through your normal platform tools.

References:
- [Citrix VDA registration](https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/manage-deployment/vda-registration.html)
- [Citrix WEM agent registration](https://docs.citrix.com/en-us/workspace-environment-management/2507/user-interface-description/administration)

## Windows 11 / Windows Server platform compatibility

BISF-Local targets **Windows 11 single-session MCS templates** and
**Windows Server 2025 multi-session templates**, using elevated 64-bit
Windows PowerShell 5.1. Modern Windows 11 retains kernel version 10.0.
Build 26100 is shared by Windows 11 24H2 and Windows Server 2025;
`Win32_OperatingSystem.ProductType` separates workstation (1) and
member server (3). Domain controllers (2) remain blocked.

| Windows edition/release | Base build | BISF-Local platform outcome |
| --- | --- | --- |
| Windows 11 21H2 / 22H2 / 23H2 | 22000 / 22621 / 22631 | Recognized client (verify OS lifecycle) |
| Windows 11 24H2 / 25H2 | 26100 / 26200 | Recognized client |
| Windows 11 26H2 | 26300 | Recognized client; check Citrix VDA CU |
| Windows 11 26H1 | 28000 | Recognized specialized new-hardware release; Citrix compatibility not assumed |
| Other future Windows 11-family 10.0 workstation builds >=22000 | Other | Accepted by existing script-level build gate; **explicit compatibility warning** |
| Windows Server 2025 | 26100, ProductType 3 | Recognized server |
| Later Windows Server builds | >26100 | Eligible with compatibility-review diagnostics; required APIs and safety checks still apply |
| Future Windows kernel families (workstation/member server) | Newer than 10.0 | Eligible with compatibility-review diagnostics; no inferred vendor certification |
| Windows 10, Windows Server 2022/2019 and domain controllers | Older/any DC | Outside this specialized package's preparation scope |

**Citrix version support is separate from script eligibility.**
Per Citrix VDA 2507 LTSR system requirements, Windows 11 single-session
VDAs are supported, whereas Windows 11 multi-session is supported **only
with Citrix DaaS**. Citrix's CTX224843 compatibility matrix lists
**2507 LTSR CU2 or newer** among releases supporting Windows 11 26H2.
Windows 11 26H1 is designed for specialized new hardware (initially
Qualcomm Snapdragon X2), and Windows 11 VDA compatibility is not
established merely by recognizing that OS version.

References:
- [Microsoft Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Microsoft Windows 11 26H1](https://support.microsoft.com/en-us/servicing/os/windows/2026/02/windows-11-version-26h1)
- [Citrix VDA 2507 LTSR system requirements](https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2507-ltsr/system-requirements.html)
- [Citrix Windows 10/11 compatibility CTX224843](https://support.citrix.com/external/article/CTX224843/windows-10-11-compatibility-with-citrix.html)

Windows 11 release labels and vendor-compatibility warnings are logged
in Validate, Prepare and Personalize when the runtime inventory is available.
This does not automatically optimize a new Windows release, reset MSIX
packages, modify security configuration or bypass Citrix installer checks.
The regression suite exercises Windows 11 build detection using mocked OS
inventory on Server 2025; **a real Windows 11 MCS clone test is still
required** before production use.

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

**Defaults validate installed Citrix VDA and WEM components for an MCS master.**
They perform no cleanup or client resets and do not shut down the image.
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

SchemaVersion must be `1`. The Citrix section is optional for compatibility with older
configs (omitted means both integrations disabled); its child settings are required
when present. All other settings are required; unknown or duplicate elements,
invalid values and XML DTDs are rejected. Boolean values are XML booleans (`true`,
`false`, `1`, `0`), not PowerShell expressions. No command strings are accepted.

| Setting | Default | Behavior when enabled or changed |
|---|---|---|
| Logging.Enabled | true | File logging; false means no log file/directory writes |
| Logging.Path | `.\logs` | Script-relative or absolute log destination |
| Cleanup.WindowsTemp | true | Delete old files under `%SystemRoot%\Temp` |
| Cleanup.CurrentUserTemp | true | Delete old files under the executing user's LocalApplicationData\Temp; not every profile |
| Cleanup.UserProfiles | true | Removal of unloaded, non-system Windows user profiles from master image via `Win32_UserProfile` and `Remove-CimInstance`; no age threshold |
| Cleanup.ExcludedProfileSIDs | none | Optional `<ExcludedProfileSIDs><SID>...</SID></ExcludedProfileSIDs>`: protect domain/admin/service-account profile SIDs from cleanup |
| Cleanup.MinimumAgeDays | 7 | Last-write age threshold, integer 1–3650 days |
| ConfigurationManager.PrepareIdentityReset | false | Stop CcmExec; remove SMS store certificates and `%SystemRoot%\SMSCFG.ini`; leave client stopped |
| ConfigurationManager.CloneTrustedRootKeyReset | false | Use CIM to delete TrustedRootKey instances during Personalize, then start CcmExec |
| Personalization.Enabled | false | Register the local SYSTEM startup task during Prepare |
| Citrix.VDA.Enabled | true | Inventory installed version; check Desktop Service and MCS Machine Identity component |
| Citrix.VDA.StopBeforeShutdown | false | Stop Desktop Service immediately before shutdown; requires VDA enabled and FinalAction=Shutdown |
| Citrix.WEM.Enabled | true | Inventory installed version; check WEM services/SENS startup, accounts and cache path; preserve configuration |
| Preflight.BlockPendingReboot | true | Pending reboot blocks Prepare and its Validate preflight; false permits continuing |
| FinalAction | Shutdown | `Shutdown` requests shutdown after all selected Prepare operations succeed |

The temporary-file cleanup excludes reparse points and protects the package, configuration,
state, configured logs and the detected WEM cache when WEM checks are enabled. It rechecks
candidates before deletion. Temporary-file cleanup never deletes profile directories or arbitrary
roots. User-profile cleanup is a **separate, explicitly enabled** Windows profile-provider operation;
it removes the registered profile and its local content and associated profile metadata.
A file that changes, disappears, becomes inaccessible or becomes a link can fail the
run; retry after resolving active writers. Run with the image quiescent: path checks
are not a security sandbox against concurrent hostile filesystem changes.

SMS identity deletion is irreversible without an image backup. No other certificate
store, machine-wide crypto folder or Entra join is reset. The installed Configuration
Manager service, certificate store and configured CIM class must be available.
The certificate store may be empty, but must exist. Client version compatibility
still requires an actual deployment test.

## User profile cleanup before an MCS snapshot

Citrix Profile Management 2507 documentation for **Provisioning Services** recommends
removing non-essential, locally cached profiles before capturing the master vDisk,
while retaining the currently logged-on local administrator. Applying the same
local-cache hygiene to an MCS master is reasonable, but this is **not** a claim that
Citrix prescribes this exact script for MCS:
[Citrix Profile Management guidance](https://docs.citrix.com/en-us/profile-management/2507-ltsr/integrate/provisioning-services).

Optional profile cleanup uses Windows' own Win32_UserProfile provider rather than
raw recursive deletion of C:\Users or the upstream BIS-F's external Delprof2
executable. The provider manages the registered Windows profile and settings:
[Microsoft Win32_UserProfile](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/ee886409(v=vs.85)),
[Remove-CimInstance](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/remove-ciminstance?view=powershell-5.1).

Set the following **only on a backed-up, quiescent master** with no other user
sessions. The setting is optional in legacy XML and defaults to false:

    <Cleanup>
      <WindowsTemp>true</WindowsTemp>
      <CurrentUserTemp>true</CurrentUserTemp>
      <UserProfiles>true</UserProfiles>
      <MinimumAgeDays>7</MinimumAgeDays>
      <!-- Optional: known administrative/service profile SIDs to preserve. -->
      <ExcludedProfileSIDs>
        <SID>S-1-5-21-111-222-333-1001</SID>
      </ExcludedProfileSIDs>
    </Cleanup>

The sample SID is illustrative; replace it with a real SID or omit
ExcludedProfileSIDs entirely. Exclusions are never inferred from user display names.
The seven-day MinimumAgeDays threshold applies **only to temporary files**;
opted-in user-profile cleanup removes *all* eligible inactive profiles irrespective
of last-use date.

The safe selection rules are:
- Use only locally registered Win32_UserProfile objects returned from the OS,
  with valid domain/local user SIDs (S-1-5-21-...). No folder-tree search.
- Protect system/special identities, current administrator SID, built-in/reserved
  accounts (RID below 1000), template profile directories (Default/Public),
  explicitly excluded SIDs, nonstandard identities and profiles outside the
  configured Windows ProfilesDirectory.
- Only consider a direct child of the configured local ProfilesDirectory whose
  directory exists and has no reparse-point ancestor.
- If another non-exempt profile is **loaded**, has active references or has
  unknown lifecycle flags, **Prepare fails before image changes**. Log off that
  user, stop only its legitimate workloads through normal maintenance procedures
  and retry. The script never logs off users or forces profile deletion.
- Enumerate candidate SIDs and paths with reasons in Validate and Prepare -WhatIf.
  During Prepare, re-query each SID, re-check profile status/path and remove via
  Remove-CimInstance -InputObject. Any failure stops the workflow.
- Profile deletion is **irreversible** within the running master. Make a VM
  snapshot or backup first; there is no rollback of prior successfully deleted
  user profiles if a later operation fails.

Run first:

    .\Invoke-BISF.ps1 -Mode Validate
    .\Invoke-BISF.ps1 -Mode Prepare -WhatIf

Review the exact proposed SIDs and local paths in the resulting log. Profiles of
other domain administrators may have normal S-1-5-21 SIDs with RIDs >= 1000:
exclude their SIDs explicitly if those profiles must survive. Keep service
accounts, installation accounts and any data stored solely in local user profiles
backed up. This step does **not** delete profiles in FSLogix containers, Citrix
Profile Management's network user store, or other remote stores; it targets the
local cached Windows profile registered on the master only.

## Citrix VDA and WEM for MCS

Install and configure both agents first, select **Create a master MCS image** in the
VDA installer, and complete any requested reboot. Run from an administrative console
or RDP session on a quiescent master with no active ICA user sessions. This package
does not install agents, configure delivery controllers/WEM endpoints, change deployment
mode, or enable optimizations. Existing settings remain in effect.

Citrix versions are informational: **older and newer releases are accepted**. The
platform gate accepts Windows Server 2025 / Windows 11 and newer releases, while retaining administrator, architecture, PowerShell, domain-controller and operation-specific safety checks.
Required installed components and service configuration are still checked. Legacy
ExpectedRelease XML elements are accepted but ignored; the supplied config omits them.

The supplied configuration includes:

```xml
<Citrix>
  <VDA>
    <Enabled>true</Enabled>
    <StopBeforeShutdown>false</StopBeforeShutdown>
  </VDA>
  <WEM>
    <Enabled>true</Enabled>
  </WEM>
</Citrix>
```

VDA validation requires an enabled MCS Machine Identity component (`PvsVmAgent`, also
recognized by the Machine Identity display name), and Automatic startup for Desktop
Service (`BrokerAgent`). The MCS component need not currently be running on the master.
WEM validation recognizes modern and legacy Norskale host service names. It requires
Automatic startup for the host service and SENS, plus the user logon service when
installed. Older WEM agents without a separate logon service are accepted. Installed
WEM services must use LocalSystem. It never changes service startup settings.

Version inventory reads installed-product registrations in both registry views and
checks that the host service binary exists. If registrations do not provide a version,
the binary ProductVersion is reported; missing version resources report Unknown.
No Citrix version number blocks preparation. This does not establish vendor support
for a particular Citrix/Windows combination; test the installed agents on an MCS clone.

WEM cache discovery reads the installed non-policy Agent Host settings, using
AgentCacheAlternateLocation or `<agent installation>\Local Databases Set`. The path
must be local and free of reparse points; it is excluded from optional temp cleanup.
The read-only inventory distinguishes `DirectoryMissing` (cache folder absent),
`Incomplete` (folder exists but one or both expected .db files are absent), and
`FilesPresent` (both files exist). The two expected files are
`LocalAgentCache.db` and `LocalAgentDatabase.db`. Missing/partial cache is
logged as a **warning**, not an automatic preparation failure. Neither an
existing directory nor both database files prove connectivity, database integrity,
or that the latest WEM settings were synchronized. This script never creates or
refreshes these files. Confirm initialization and connectivity before capturing a
test MCS image, and check that the agent rebuilds/synchronizes the cache on a clone.

To investigate a missing cache on the master without modifying WEM, use the exact
path printed in your BIS-F log and inspect the agent's current settings:

```powershell
Get-CimInstance Win32_Service | Where-Object { $_.Name -match '^(WemAgentSvc|Norskale Agent Host Service)$' } |
    Select-Object Name, State, StartMode, PathName
Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Norskale\Agent Host' |
    Select-Object AgentLocation, AgentCacheAlternateLocation
Get-ChildItem -LiteralPath 'C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\Local Databases Set' -Force -ErrorAction SilentlyContinue |
    Select-Object Name, Length, LastWriteTime
```

An alternate cache registry value overrides the default installation-folder cache.
If the WEM service is stopped or the cache remains absent, investigate the agent's
connectivity and initialization before relying on the captured image.
The script preserves Basic, on-premises or cloud configuration and cannot establish
endpoint connectivity or the suitability of the selected optimization settings.

This workflow preserves WEM databases and does not restart WEM services or run
AgentCacheUtility. WEM 2507 documents automatic clone-database checks and cache
synchronization in [Citrix WEM 2507 agent guidance](https://docs.citrix.com/en-us/workspace-environment-management/2507/install-and-configure/agent-host.html).
For older agents, verify their documented image-preparation requirements separately;
version-independent execution does not add legacy vendor sealing utilities.

For automatic power-off, set FinalAction to `Shutdown`. Optionally also set
Citrix.VDA.StopBeforeShutdown to `true`. After all selected operations and file logging
succeed, the script stops only BrokerAgent without Force, waits up to 30 seconds for
Stopped, then requests shutdown. Startup type remains Automatic. If stopping or requesting
shutdown fails, it attempts to restore the previous running state; recovery failure is
reported. An already stopped VDA remains stopped. No recovery follows an accepted
shutdown request. A stopped VDA is not a durable maintenance-mode setting: use your
normal Citrix administration process to keep users away from the master.

With FinalAction=None, leave StopBeforeShutdown=false, inspect the result and shut down
the master through your normal process before taking the MCS snapshot. MCS owns machine
identity preparation; **do not run Sysprep on the MCS master**. Follow the
[Citrix 2507 master image instructions](https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2507-ltsr/install-configure/machine-catalogs-create.html).
Citrix-only use does not require the optional BIS-F Personalize task or its lifecycle
state. Those features serve the separately selected Configuration Manager workflow.

Before production, create an MCS test catalog from the powered-off snapshot. Verify
VDA registration and ICA logon, WEM deployment mode and configuration processing,
clone cache recreation/sync and persistence, and subsequent cold boots. The portable
unit tests do not certify an actual Citrix installation or provisioning workflow.

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
failure does not commit completion; rerun after fixing the underlying issue.
Protected `Prepare.pending` and `Personalize.pending` files guard incomplete runs,
including failures where the JSON state cannot be rewritten. An incomplete Prepare
blocks personalization: retry Prepare on the master and recapture. An incomplete
Personalize makes the same clone retry rather than trust a staged completion. Never
remove these markers manually to force success.

For automatic startup, script/module/schema/config/state files and their parent paths
must be local, free of reparse points and protected against modification by untrusted
users. Owners must be SYSTEM, Administrators or TrustedInstaller. Use an appropriately
secured deployment folder; copying files there alone does not prove the ACLs are suitable.
The script checks permissions and refuses unsafe locations; it does not broadly rewrite
your package ACLs. It sets restricted ACLs only on its own new state files/directory.

The reserved task is `\BISF-Local-Personalize`, runs as SYSTEM at startup and uses the
built-in Windows PowerShell host. An unrelated task with that name is never overwritten.
The task remains installed; completion state makes later runs no-ops. A reboot of the
master will cause personalization to refuse the master, which is expected. Changing
Personalization.Enabled to false stops future registration; it does not uninstall a
previous task. To stop an existing task, use `Disable-ScheduledTask -TaskName
BISF-Local-Personalize -TaskPath "\"` in an elevated PowerShell session.

If nonpersistent storage discards state, personalization can run again at every boot.
This is not a universal once-per-machine guarantee for PVS/MCS. Verify actual persistence
and Configuration Manager identity behavior for your deployment technology.

## Results, failure handling and limits

- `0`: successful validation, preview, completion, or already-completed clone.
- `1`: configuration/preflight/identity/locking failure before apply.
- `2`: apply failure or a declined required operation.

Operations report Completed, Skipped, Preview or Failed. Log entries saying "Ready
for state commit" are not a committed lifecycle success; check the exit status and
absence of the pending marker. Confirmation is collected
before apply; one declined operation prevents the whole plan. A failure stops later
operations and prevents a not-yet-requested shutdown. All fallible file logging
finishes before shutdown is requested. The final pending-marker deletion occurs
after an accepted shutdown request when one is configured: if that deletion fails,
the machine may already be shutting down, exit status is 2, and clones remain blocked.
There is no transactional filesystem-and-power API; the script does not restart
services or write further logs after shutdown is accepted. Prefer FinalAction=None
when you want to inspect final state before manually shutting down. Completed
deletions are not rolled back. The runner
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


## Offline execution and newer releases

Copy the complete package to a protected local directory before execution. Runtime
uses Windows PowerShell 5.1, local Windows APIs and the locally installed agents.
It does not download modules, query release catalogs, send telemetry or require
Internet access. Pester is a separately supplied development dependency, not a
runtime requirement. Local preparation can run with the VM network disconnected.
External broker registration, WEM synchronization and FSLogix/UPM network profile
attachment are deployment checks, not evidence produced by local preparation.

Newer Windows releases are eligible without an upper build/version ceiling;
unknown releases retain explicit compatibility-review diagnostics. Citrix/WEM
versions are informational and FSLogix is inventoried locally. Required service,
path, privilege, profile, pending-reboot and shutdown guards still apply. This
policy does not guarantee that every future agent layout or OS API will work.

**Servicing limitation:** `ComponentCleanup` remains opt-in and uses the built-in
Microsoft task. BISF now refuses to continue after a success-looking aggregate
result because cancelled runs can also report Ready/result 0. Even a genuinely
successful run currently requires manual review; no verified automatic success
path is claimed. Run servicing separately, review its result, then leave
`ComponentCleanup=false` for preparation. BISF does not switch to DISM, use
ResetBase, cancel tasks automatically or erase failure state to continue sealing.

Production release and rollback procedure: [PRODUCTION-RUNBOOK.md](PRODUCTION-RUNBOOK.md). The full acceptance gate remains open.
