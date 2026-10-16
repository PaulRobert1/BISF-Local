# Production release and operating gate

Status: NOT APPROVED FOR PRODUCTION. See issue #3 for evidence and outstanding gates.

## Servicing policy

The supported release workflow uses `Servicing.ComponentCleanup=false` during
BISF Prepare. Complete Windows servicing and required restarts separately before
preparation; record the maintenance operation, its completion evidence, and the
absence of pending reboot indicators. A prior Task Scheduler aggregate result of
zero is not proof that a newly requested cleanup completed. Do not disable BISF
reboot or session guards to bypass a maintenance failure.

The optional built-in StartComponentCleanup integration remains fail-closed.
It cannot currently establish successful completion of the requested instance,
and therefore is not an approved successful preparation path. Do not substitute
DISM, ResetBase, task cancellation, marker deletion, or automatic retries.

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

Use a normal administrative operator with RID >=1000. When deferred operator
removal is selected, verify the protected SYSTEM handoff and sign out normally;
disconnecting RDP is insufficient. Observe actual shutdown externally. Capture
only a successful powered-off master after inspecting its disk evidence.
Never force logoff or poweroff to turn a failed seal into a capture candidate.

## Failure and rollback

Preserve task results, pending state, logs, profile inventory and hypervisor
state outside the image. Profile/log removal is not transactional. After a
partial failure, investigate and restore the backed-up disposable/master image;
do not retry the finalizer or delete its state to suppress the failure. Never
run finalization on an MCS clone as a repair step.

## Release and pilot

Require reviewed evidence for both supported OS targets: option matrix, native
failure cases, offline disk inspection, real MCS provisioning, broker/HDX/WEM,
profile attachment, domain/activation, repeated boots and application regression.
Record any blocked or untested item as such. A mocked test or service inventory
cannot replace an external check.

A controlled pilot uses an isolated catalog and test accounts, a known-good
image for rollback, representative applications and recorded baseline logon/SMB
measurements. Validate repeated sign-in/reconnect and two cold boots before
requesting operator release approval. Retain the evidence and rollback image.
No merge or broad production deployment is authorized by a passing local test.
