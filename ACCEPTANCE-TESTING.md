# Disposable Windows / MCS acceptance gate

Status: **INCOMPLETE. PR #2 and candidate PR #5 remain draft.** Current evidence is
tracked in [issue #3](https://github.com/PaulRobert1/BISF-Local/issues/3). Some
native runs have passed; unchecked rows below remain release gates. Hosted Pester tests mock Windows
profile removal, servicing, event clearing, scheduled workers and shutdown.
They do not establish that an image is safe to deploy. Do not use SWCTXMASTER05
for these tests. Use separate backed-up, disposable masters and test catalogs.

## Evidence and prerequisites

Run the checklist separately on Windows Server 2025 and Windows 11 with the
actual intended VDA, WEM and FSLogix/UPM versions. Record OS edition/build,
PowerShell version/bitness, package commit and file hashes, XML hash, installed
agents, VM tools, profile policy, execution/signing policy and MCS catalog type.
Version detection alone does not establish vendor support.

Keep evidence outside the captured image before enabling BISF log deletion.
Include console/task results, before/after profile inventory, event record
counts and relevant Citrix console results. Approve the selected event-channel
retention policy before testing event clearing. Keep every new cleanup option
false on existing production configurations.

The test operator must be a normal administrative account (RID >=1000), not
the built-in Administrator. Install package, configuration and logging outside
all profiles selected for deletion, in local Administrators/SYSTEM-controlled
locations. Keep masters unavailable for user logon through the normal Citrix
maintenance process. Session scans do not prevent a new Windows logon.

## Required runs on each operating system

| Case | Procedure | Required observation |
| --- | --- | --- |
| Automatic installation permissions | On a disposable package under Program Files (x86), grant Users Modify to the package and an explicit code-file ACE; launch BISF-Local.exe normally | Normal Windows UAC occurs if required; installation backs up and repairs package permissions automatically, then continues to preflight. Users retain code read/execute; state/log data stay private. A second launch is idempotent. Verify UAC cancellation starts no preparation. NOT RUN for this update |
| Permission repair boundaries | Use disposable reparse/hard-link files, unsafe parent ACLs, retained operator state and an external config/log path; separately run Validate and Prepare -WhatIf | Unsafe paths fail without broad parent or external ACL changes. Preview modes never repair ACLs. Retained sealing state is preserved. NOT RUN for this update |
| Defaults | Run Validate and Prepare -WhatIf with shipped XML | No profile/temp/recycle/event deletion, servicing, task registration, state mutation, sign-out or shutdown; diagnostic files only when logging is enabled |
| Checkbox editing | Open, save each checkbox combination, cancel, edit XML externally while dialog is open, try malformed XML and a locked destination | Only chosen flags change; cancel changes nothing; stale/invalid/locked saves preserve the original; no cleanup or shutdown; custom path and legacy XML work |
| Log scope | On fresh snapshots test all four WindowsEventLogs/BISFLogs combinations with explicit Shutdown, both with and without deferred operator cleanup | Only Application/System/Setup and matching BISF-generated files are selected; Security, vendor channels/files, other files and remote locations survive; events created during shutdown are allowed |
| Ordinary profiles | Make inactive disposable profiles, explicit SID exclusions, a built-in/reserved profile, and a loaded/disconnected session | Only eligible inactive profiles are removed through the provider; operator, reserved and excluded profiles survive; busy profiles block according to configured guards; no raw folder deletion |
| Dependencies | Put a package copy/config/logs or alternate WEM cache beneath an otherwise eligible disposable profile | That profile is protected; operator finalization rejects a target containing a runtime dependency; ordinary sibling profile remains eligible |
| Windows Update cleanup | With shipped ComponentCleanup=true, record inbox DISM command path/version/parameters, run on a disposable updated image and preserve DISM/BISF logs | Servicing runs before other cleanup; actual synchronous result is Online=true and RestartNeeded=false with no pending reboot. Only then do profile cleanup, acknowledged sign-out and shutdown proceed. No ResetBase or manual update-file deletion. NOT RUN for this update |
| Servicing compatibility and failures | On disposable test fixtures inject a missing cleanup parameter, native failure, missing/ambiguous result, reboot request and elapsed-budget overrun; also test false/omitted configuration and previews | Unsupported capability fails before image cleanup. Other failures prevent further cleanup/sign-out/shutdown. A budget overrun waits for active servicing to return before refusing continuation. False/omitted settings and previews never invoke cleanup. NOT RUN natively for this update |
| Recycle Bin/temp | Add expendable eligible and too-new temp files, unrelated files and current-user recycle items | Age/path guards hold; only selected temp roots and invoking user's system-drive recycle contents change |
| Protected SYSTEM handoff | Enable UserProfiles and RemoveOperatorProfile with Shutdown; run Prepare from a saved, quiescent console session and repeat from RDP | Exact triggerless SYSTEM/highest task validates trust/config/master/profile/readiness and atomically acknowledges the generation. Only successful acknowledged Prepare releases its lock and requests normal current-user sign-out. SYSTEM alone deletes the unloaded profile, performs selected log cleanup and shuts down. No new config flag or switch. NOT RUN for this update |
| Blocked sign-out and RDP disconnect | On separate snapshots block normal sign-out with an unsaved application; separately disconnect RDP before preparation/session revalidation | No forced application closure. Unsuitable/disconnected session fails validation; disconnect alone never counts as profile unload. A loaded/referenced profile prevents removal and shutdown through timeout. Native console and RDP paths NOT RUN for this update |
| Readiness failures | Deny SYSTEM startup/acknowledgement, alter generation/config, stop the acknowledged worker, or use different elevated credentials from the desktop owner | No automatic sign-out on failed/declined Prepare, unacknowledged or dead worker, changed state or session mismatch. Accepted-start acknowledgement failures retain task/state for diagnosis. NOT RUN for this update |
| Existing attempt during upgrade | Retain an old task/state on a disposable snapshot and attempt the update workflow | Installation refuses the retained seal; preserve logs/state, inspect the exact worker and confirm it has exited before replacing code. Extracting/rerunning is not automatic recovery. Do not delete markers to bypass the refusal. NOT RUN for this update |
| Successful finalization | Observe through hypervisor and inspect an offline copy of the powered-off disk | Target profile registration/content removed by Windows provider; selected log cleanup occurs afterwards; task and pending operator state absent; actual shutdown completed |
| Clone | Capture the powered-off test master and provision disposable MCS clones | No operator-seal task/state executes on clones; VerifyClone is read-only; complete external checks below |
| Reboot/persistence | Cold boot a test clone twice | No repeating finalization or identity reset; intended persistence and profile attachment remain correct |

## Failure injection on disposable snapshots

Test each failure separately, restoring a snapshot between attempts. Record
whether failure occurred before or after profile deletion; deletions are not
rolled back. Never capture an image from a failed or timed-out seal.

- Hold the operator profile loaded/referenced through the configured timeout.
  The master must remain on; no forced sign-out and no shutdown.
- Create a new loaded/referenced other profile during servicing and before final
  sealing. Further destructive steps and shutdown must be refused when the
  session guard is enabled. The SYSTEM finalizer always requires quiescence.
- Change configuration while Prepare reads it, during servicing and after
  staging; include enabling a log option absent from the confirmed plan.
  No changed configuration may become implicitly approved by a new state hash.
  Change master identity in a disposable
  copied VM, or introduce pending reboot before final deletion. Refuse deletion
  and shutdown; never run the finalizer on an MCS clone to repair an image.
- Supply unsafe ACLs inside the package: applying Prepare may repair those installation
  permissions before preflight; Validate and WhatIf must only report them. Supply an
  unsafe parent/external ACL, a redirected module/schema/config/state/log path, retained
  operator state, or a conflicting task. Refuse image cleanup and finalization.
- Make Task Scheduler enumeration fail. Preflight must report the error rather
  than treating an unreadable reserved task as absent and applying cleanup.
- Deny profile-provider removal, state/task removal, selected event-log clearing,
  BISF-log deletion or shutdown. Each error must remain visible, return failure
  and prevent a not-yet-requested shutdown. After partial removal, investigate
  and restore the disposable snapshot; do not blindly retry or delete markers.
- Verify Finalize -WhatIf and an explicitly declined Finalize -Confirm perform
  no state read/write, file logging, profile/log cleanup, task removal or power
  action. These are previews/declines, not acceptance of a seal.
- Observe actual SYSTEM task scheduling and self-unregistration through sign-out:
  a successful Start-ScheduledTask call alone does not prove the worker ran.
  Verify exact-generation acknowledgement, live worker identity, preparation-lock
  release before native sign-out, signing policy, task LastTaskResult and the actual
  power transition. A successful normal sign-out API return is asynchronous and
  is not proof of profile removal or shutdown.

Windows checks and profile deletion are separate provider calls, not one atomic
transaction. Administrators can change the machine between checks. Maintain
exclusive access throughout sealing; tests cannot remove that operational need.

## External clone checks (VerifyClone cannot certify these)

| Check | Required external evidence |
| --- | --- |
| Broker registration | Correct clone identity and Registered state in Studio/Director/Monitor |
| ICA/HDX | Real published desktop/application launch, logon and reconnect |
| WEM | Agent registration, settings processing, cache rebuild/sync and persistence |
| Profiles | Actual FSLogix container or UPM attachment, sign-out and second logon |
| Domain/network | Expected domain trust, DNS and backend connectivity |
| Activation | Valid Windows/application activation through the intended method |
| Regression | Baseline versus clone logon time, SMB performance and existing application behavior |

Record pass/fail and evidence links for each row on each OS. Keep PR #2 draft
until the complete sign-out -> profile removal -> selected log cleanup ->
shutdown -> capture -> clone workflow passes on both platforms and is reviewed.
Merging still requires the operator's authorization.

## Configuration-specific WEM scope (2026-10-16)

The operator confirms the master has no WEM backend configuration. Backend
registration, settings synchronization and persistence are **NOT APPLICABLE to
this configuration**; no success is inferred. Verify that the installed but
unconfigured agent is tolerated and its files/settings and detected cache paths
are preserved. If a WEM backend is configured later, qualify those external
integration checks before declaring that configuration accepted.
