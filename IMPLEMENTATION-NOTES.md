# Implementation decisions and review disposition

The approved design and plan were implemented as a standalone package. The local
repository remains on its implementation branch; there is no upstream remote,
merge target, publication or modification to the user's other repositories.

## Decisions made during implementation

1. A new standalone repository provides isolation because the enclosing workspace
   is not a repository. Cost if unsuitable: move this package without touching siblings.
2. Git had no author configured. Local commits explicitly use Codex
   <codex@local.invalid>; global and local user configuration were not changed.
   Cost: this is tool attribution, not the user's personal commit identity.
3. Cleanup candidates carry their approved root, protected paths, timestamp and size
   instead of plain strings, allowing deletion-time revalidation. Cost: a private
   implementation interface differs from the plan's initial signature.
4. Lifecycle state binds the entire configuration SHA256. Any XML edit, even logging,
   requires preparation again. This prevents different actions being applied to a
   captured generation. Cost: no live logging-only change on an already prepared clone.
5. Filesystem commit and shutdown cannot be atomic. A persistent pending marker blocks
   eligibility until all work succeeds. For automatic shutdown, removing the marker is
   the sole filesystem finalization after the shutdown request returns successfully.
   If it fails, the system may shut down but the clone remains ineligible. Cost: a
   storage failure can require re-preparing and recapturing an otherwise prepared image.
   All file logging finishes before the power request; no service restoration follows
   an accepted request.
6. This is an artifact delivery, so the approved local package and repository are
   retained. There is no merge or pull-request workflow to perform.

## Independent review

A separate reviewer examined the entire package and reported five findings. Fixes:

- Validate the lifecycle JSON leaf's ACL/reparse status under the apply lock before
  trusting its master identity or successful generation.
- Accept CDXML Function commands from the ScheduledTasks module during preflight.
- Enumerate plan IDs safely when the default plan is empty under module strict mode.
- Finish fallible logging before shutdown; do not restore services after acceptance.
- Delay durable success and use pending journals to remain ineligible even when both
  the original operation and a corrective JSON write fail. An unfinished clone run
  can retry without trusting a staged completion marker.

All findings have automated regression coverage. Lifecycle results are reported as
Completed only after the final commit. No minor findings were deferred.

## Boundaries considered during review

- Windows PowerShell 5.1 execution, real Windows ACLs, Configuration Manager provider
  behavior, SYSTEM tasks and shutdown require a Windows host. They remain unverified;
  assuming compatibility from Linux tests could produce a failed deployment. Syntax
  compatibility was checked separately with PSScriptAnalyzer.
- Actual CcmExec automatic startup ordering relative to the task requires image-level
  acceptance. The script orders its own operations but cannot certify service races
  from portable mocks; this can affect client identity on deployed clones.
- Cleanup is intended for a quiescent administrator-controlled master, not as a security
  sandbox against hostile concurrent path replacement. Static links and changed files
  are rejected, but hostile races require stronger OS-level containment.
- PVS/MCS provisioning and vendor sealing remain outside the package as explicitly
  approved. A successful run does not establish that an image meets those products'
  deployment requirements.
