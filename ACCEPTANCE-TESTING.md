# Disposable Windows / MCS acceptance gate

Status: **NOT RUN. PR #2 must remain draft.** Hosted Pester tests mock Windows
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
| Defaults | Run Validate and Prepare -WhatIf with shipped XML | No profile/temp/recycle/event deletion, servicing, task registration, state mutation or shutdown; diagnostic files only when logging is enabled |
| Checkbox editing | Open, save each checkbox combination, cancel, edit XML externally while dialog is open, try malformed XML and a locked destination | Only chosen flags change; cancel changes nothing; stale/invalid/locked saves preserve the original; no cleanup or shutdown; custom path and legacy XML work |
| Log scope | On fresh snapshots test all four WindowsEventLogs/BISFLogs combinations with explicit Shutdown, both with and without deferred operator cleanup | Only Application/System/Setup and matching BISF-generated files are selected; Security, vendor channels/files, other files and remote locations survive; events created during shutdown are allowed |
| Ordinary profiles | Make inactive disposable profiles, explicit SID exclusions, a built-in/reserved profile, and a loaded/disconnected session | Only eligible inactive profiles are removed through the provider; operator, reserved and excluded profiles survive; busy profiles block according to configured guards; no raw folder deletion |
| Dependencies | Put a package copy/config/logs or alternate WEM cache beneath an otherwise eligible disposable profile | That profile is protected; operator finalization rejects a target containing a runtime dependency; ordinary sibling profile remains eligible |
| Servicing | Enable ComponentCleanup on a serviced disposable master | The requested built-in task actually starts and finishes successfully; a previous recent success does not count; failure/timeout/pending reboot blocks subsequent sealing and shutdown |
| Recycle Bin/temp | Add expendable eligible and too-new temp files, unrelated files and current-user recycle items | Age/path guards hold; only selected temp roots and invoking user's system-drive recycle contents change |
| Protected SYSTEM handoff | Enable UserProfiles and RemoveOperatorProfile with Shutdown; run Prepare | Task is SYSTEM/highest, triggerless, exact package action, no execution-policy bypass; protected state exists; Prepare returns Staged without logoff, deletion of operator, or immediate shutdown |
| Disconnect vs sign-out | Disconnect RDP, inspect from hypervisor/second admin as appropriate, then restore snapshot and repeat with normal sign-out | Disconnect keeps profile loaded and causes no deletion/shutdown; normal sign-out permits provider removal only after all nonsystem profiles unload and references drain |
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
- Change configuration after staging, change master identity in a disposable
  copied VM, or introduce pending reboot before final deletion. Refuse deletion
  and shutdown; never run the finalizer on an MCS clone to repair an image.
- Supply unsafe ACLs, a redirected module/schema/config/state/log path, retained
  operator state, or a conflicting task. Refuse preparation before mutations.
- Deny profile-provider removal, state/task removal, selected event-log clearing,
  BISF-log deletion or shutdown. Each error must remain visible, return failure
  and prevent a not-yet-requested shutdown. After partial removal, investigate
  and restore the disposable snapshot; do not blindly retry or delete markers.
- Verify Finalize -WhatIf and an explicitly declined Finalize -Confirm perform
  no state read/write, file logging, profile/log cleanup, task removal or power
  action. These are previews/declines, not acceptance of a seal.
- Observe actual SYSTEM task scheduling and self-unregistration through sign-out:
  a successful Start-ScheduledTask call alone does not prove the worker ran.
  Verify signing policy, task LastTaskResult and the actual power transition.

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
