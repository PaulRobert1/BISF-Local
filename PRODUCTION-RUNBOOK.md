# Production release and operating gate

Status: NOT APPROVED FOR PRODUCTION. See issue #3 for evidence and outstanding gates.

## Servicing policy

The current candidate enables `Servicing.ComponentCleanup=true` in its supplied
configuration. Windows Update cleanup runs first in Prepare using the inbox
`Dism\Repair-WindowsImage -Online -StartComponentCleanup -NoRestart -LimitAccess`
cmdlet. Preflight checks the installed module and required parameters before
image cleanup. A normal synchronous return with explicit online context and
`RestartNeeded=false`, followed by clear pending-reboot checks, is required to
continue toward automatic sign-out and shutdown. The former scheduled-task
summary-state completion path has been removed.

Complete update installation and required restarts before preparation. This
operation removes superseded components; it does not install updates, use
ResetBase, reset Windows Update services or delete update databases. Preserve
the default DISM log under `%WINDIR%\Logs\Dism\dism.log` as servicing evidence.
`Servicing.TimeoutMinutes` is an elapsed completion budget, default 75 minutes.
The synchronous call is allowed to finish before an over-budget result blocks
the next step; BISF never cancels active servicing to meet that budget. Errors,
unknown completion results and required restarts also prevent finalization.
Qualify the native cmdlet and result contract on the exact disposable Windows
build before production use. Do not disable reboot/session checks or delete
pending state to bypass a maintenance failure.

## Before sealing

1. Qualify the exact Windows build, installed agent versions, package commit and
   configuration against ACCEPTANCE-TESTING.md. Newer versions being eligible
   does not certify vendor support or backend compatibility.
2. Back up the master and record the recovery snapshot. Keep package, XML, logs
   and pending state in local protected paths outside every deletion target.
3. Confirm the site's execution policy permits the package. Keep new cleanup
   flags false until their effects and event retention are explicitly approved.
4. Maintain exclusive administrative access and block user logons through the
   site's maintenance controls. Session checks cannot prevent concurrent logons.
5. Run Validate and Prepare -WhatIf, review the selected profiles and paths, and
   save the package/config hashes and results outside the image.

## Seal and capture

Use a normal administrative operator with RID >=1000, signed directly into the
console or RDP desktop under that account. Save work and close other applications.
With `RemoveOperatorProfile=true`, successful Prepare waits for the exact protected
SYSTEM worker to acknowledge readiness. After releasing its lock and rechecking
the worker/session, BISF requests the current operator's normal Windows sign-out
automatically; no new config flag or launch switch is required. The worker alone
waits for profile unload, removes/verifies the profile, finishes selected log cleanup
and shuts down. Unsaved applications can block sign-out; disconnecting RDP is
insufficient. A failed/declined run or preview never requests sign-out. Observe actual
shutdown externally. Capture only a successful powered-off master after inspecting
its disk evidence.
Never force logoff or poweroff to turn a failed seal into a capture candidate.

## Failure and rollback

Preserve task results, pending state, logs, profile inventory and hypervisor
state outside the image. Profile/log removal is not transactional. After a
partial failure, investigate and restore the backed-up disposable/master image;
do not retry the finalizer or delete its state to suppress the failure. Windows
can remove profile registration while leaving locked files behind; BISF requires
both registration and the original profile directory to be absent. A leftover
directory blocks further cleanup and shutdown; never remove it as a fallback
to make the failed seal appear successful. Never
run finalization on an MCS clone as a repair step.

For a retained earlier operator-seal attempt, do not overwrite its package or
assume extracting/rerunning the update recovers it. A successfully started worker
can outlive an acknowledgement timeout. Inspect its exact task/action, retained
state, Finalize log and worker process. If recovery requires stopping that attempt,
confirm the owned worker has exited before replacing program files. Retain the
evidence and use the saved image when uncertain; do not erase task/state merely
to make preflight accept another run.

## Release and pilot

Require reviewed evidence for both supported OS targets: option matrix, native
failure cases, offline disk inspection, real MCS provisioning, broker/HDX/WEM,
profile attachment, domain/activation, repeated boots and application regression.
Record any blocked or untested item as such. A mocked test or service inventory
cannot replace an external check. Native console and RDP testing of automatic
sign-out, worker lifetime, profile unload and actual shutdown has not been run
in this update's development environment.

A controlled pilot uses an isolated catalog and test accounts, a known-good
image for rollback, representative applications and recorded baseline logon/SMB
measurements. Validate repeated sign-in/reconnect and two cold boots before
requesting operator release approval. Retain the evidence and rollback image.
No merge or broad production deployment is authorized by a passing local test.
