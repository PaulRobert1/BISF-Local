# Proposed servicing cancellation fix

Design only; no tested source, guest, VM, branch or PR changed. Based on pin `fac7b1def5787e0d9ab8bcbb0707880d7572edc2`. Implement separately from the acceptance pin in the issue-requested draft fix branch/PR after the native event contract below is established.

## Defect and recommendation

Replace aggregate task-state polling with **request-instance correlation and positive, non-cancelled completion evidence**. Never infer success from `LastRunTime` + `Ready` + `LastTaskResult=0`, nor merely from having observed `Running`.

Maintenance.ps1:83 (not bundled) marks a task started when LastRunTime advances; lines 85–90 accept Ready/result 0. Native Windows 11 evidence shows that exact combination after cancellation of a queued invocation. [Review and reproduction evidence](servicing-cancellation-review.txt). The acceptance failure is confirmed; the evidence does not prove zero component work occurred during every instant before cancellation.

The captured task definition (not bundled) uses COM handler `{752073A1-23F2-4396-85F0-8FDB879ED0ED}`, `IgnoreNew`, UnifiedSchedulingEngine, maintenance settings and a one-hour execution limit. Treating it as an executable whose process exit establishes success is incorrect. Microsoft documents that a COM handler's **Stop** method supplies a completion return code raised as an event. Thus even a zero action-completion event may accompany cancellation; it must not be the sole success criterion. [ITaskHandler::Stop](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nf-taskschd-itaskhandler-stop), [TaskCompleted](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nf-taskschd-itaskhandlerstatus-taskcompleted).

## Native evidence contract — prerequisite to implementation

On both target OS, collect provider metadata and full XML from `Microsoft-Windows-TaskScheduler/Operational`, actual task XML, returned execution GUID and all instance events for: genuine completion, queued cancellation, running cancellation and a very fast successful owned test task. Do not modify the built-in servicing task to make it faster or runnable. Preserve a caller-side timestamp/record boundary plus the guarded cancellation receipt. CBS/DISM traces can corroborate servicing but are not assumed machine-readable completion APIs.

Use the installed provider manifest (`wevtutil gp Microsoft-Windows-TaskScheduler /ge:true /gm:true`) to establish event versions and named fields. Candidate lifecycle events are start/action-start, action-complete, task-complete and termination (commonly 100/200/201/102/111); these numbers/field names are **not yet qualified for this COM handler on both OS**. Parse XML named fields, GUIDs, provider and event version, never localized message text or positional `.Properties[]`. Include failure/ignored-request/maintenance-stop events present in the actual traces. Retain all events for the task during qualification so a cancellation indicator is not accidentally filtered out.

Required demonstrated distinction: cancelled COM-handler invocations must produce a recognizable terminal cancellation/failure signal or must lack the complete positive success sequence. If stopped and successful invocations are indistinguishable in the proposed event contract, do not ship it as a fix. Keep servicing opt-in fail-closed with an explicit “completion cannot be verified” error until a supported distinguishing signal is found. A short extra sleep cannot repair an ambiguous contract.

## Proposed implementation

1. **Preflight before starting work:** require exact task path/name, enabled/demand-start readiness, state strictly Ready, no queued/running instances and readable expected definition. Existing code rejects only Disabled/Running at line 63 (not bundled); reject Queued and Unknown too. Check the Operational channel is enabled, readable and its expected event schema supported. If disabled, fail with a concrete administrator remediation message; do not silently enable/change channel policy inside Prepare. Validate/WhatIf may report prerequisites but must not start servicing or mutate channel settings.
2. **Arm durable observation before requesting:** capture a validated event bookmark/record boundary and channel metadata; read forward from it using EventLogReader, with errors surfaced. Use a monotonic Stopwatch for the existing configured timeout. Persist the task-definition hash and relevant settings for diagnostics. A watcher may supplement but must not replace durable catch-up reads; otherwise fast executions can be missed.
3. **Request the exact instance:** use Task Scheduler COM `Schedule.Service` → exact folder/task → `IRegisteredTask.Run` and immediately retain returned `IRunningTask.InstanceGuid`. Do not use Start-ScheduledTask followed by “newest instance” guessing. The API returns a new instance interface; InstanceGuid identifies it. Run can return without the task actually running when demand-start is disabled, so return success is not completion. [Run](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nf-taskschd-iregisteredtask-run), [InstanceGuid](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nf-taskschd-irunningtask-get_instanceguid).
4. **Handle races explicitly:** reject missing/malformed GUID, a GUID already present before the call, or an instance whose correlated start predates the captured boundary. IgnoreNew may race another caller between preflight and Run; never adopt another request's completion. Confirm native behavior of Run/InstanceGuid for completion before the first poll. If COM cannot retain its GUID across such fast completion, use a supported request API that returns the GUID atomically (investigate MS-TSCH SchRpcRun), rather than timing heuristics or a second start. This is a qualification point, not a prescribed undocumented interop implementation.
5. **Accumulate a per-instance state machine:** exact task path + normalized returned GUID + post-boundary records only. Require the qualified action-start and completion sequence for every expected action and terminal task success. Require explicit numeric zero action result, treating missing/malformed result as unverifiable. Cancellation, termination, failed start/action, conflicting terminal evidence, task-definition changes or unexpected instance reuse fail closed. Cancellation wins over a success-looking action result. `IRunningTask` state/disappearance and registered LastTaskResult are diagnostic only: the interface has no durable per-instance completion result. [IRunningTask](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nn-taskschd-irunningtask).
6. **Do not decide from a partial batch:** process all available records in record order before evaluating terminal success, using the native-qualified terminal ordering. Bound event-delivery catch-up within the configured deadline. Detect channel reset/clear, stale bookmark, unreadable/malformed records, event loss/rollover across the boundary or unsupported schema; report “completion evidence unavailable” and stop preparation. Absence of a cancellation record is not sufficient when the event stream is incomplete. No fixed quiet period is a substitute for qualified terminal semantics.
7. **Return only on verified success:** log path, GUID, action result, terminal record IDs and duration. On cancellation/failure/unverifiable completion/timeout, throw; existing Runner error handling prevents later profile cleanup/sealing. Do not auto-retry, stop unrelated runs, rewrite the Microsoft task or switch to DISM/ResetBase. Timeout can leave the requested task running; report that explicitly for operator recovery, retaining existing no-force-stop behavior.

Fast success is handled by reading persisted records from before the request, even when Running was never polled. It must pass as soon as a complete correlated success sequence is available; it must not time out because a short-lived process/state was missed.

## Existing tests and concrete additions

Maintenance.Tests.ps1:82 (not bundled) currently calls a Ready task with advanced LastRunTime a successful run. This test encodes the faulty assumption. The queued test at line 102 follows Queued → Running → Ready and does not model cancellation. Error-result and timeout tests exist, but no instance IDs, event evidence, cancellation or fast-run correlation tests do. Integration.Tests.ps1:132 (not bundled) already verifies that a thrown servicing failure prevents later profile deletion; retain and expand that boundary assertion.

Implement small internal adapters for task launch/identity, event retrieval and monotonic time, keeping the decision state machine pure. Unit tests may mock those adapters; native acceptance must still use actual Windows APIs.

| Test | Required result |
|---|---|
| Recorded Queued → cancellation → Ready/result 0 | Throw; no success log, later profiles/log sealing/shutdown not invoked |
| Running → cancellation with zero COM-handler completion code | Throw even when a success-looking action event exists |
| Fast successful instance completed before first poll | Pass from complete buffered GUID-correlated events, no Running observation required |
| Genuine longer successful instance | Pass once, exact requested GUID and action result recorded |
| Stale previous success or another task/instance succeeds | Never satisfy current request |
| IgnoreNew race / existing GUID returned / missing GUID | Fail closed, no second Run request |
| Queued, Running, Disabled or Unknown at entry | Refuse before Run |
| Nonzero, absent, malformed or overflowed result code | Fail; parse HRESULT/unsigned values without truncation |
| Partial success sequence, contradictory cancellation, multi-action partial result | Never report success |
| Delayed events arriving out of callback order | Use record ordering and durable replay; no premature success |
| Channel disabled/unreadable, cleared, rolled over, schema changed | Explicit evidence/prerequisite failure, never success fallback |
| Timeout and event API exception | Stop preparation; no retries or broad task stop |
| WhatIf/Validate | Zero launch and channel-policy mutations |

First create a regression test that reproduces current cancellation metadata; demonstrate failure on the old predicate. Then add evidence-contract/state-machine tests and implementation in the separate fix branch. Run the full Windows PowerShell 5.1 suite and source audit, not only maintenance tests.

Native release gate on both Windows 11 and Server 2025: repeat guarded queued cancellation, running cancellation where available, genuine built-in completion, and owned sub-poll-interval success with exact GUID/event capture. Prove cancellation fails the full Prepare flow before subsequent cleanup, without mistaking a fixture/task-start failure for the intended test. A successful owned canary validates the observer, not the real servicing COM handler. Keep the original acceptance source/evidence unchanged; record fix commit/hash separately in the draft PR and publish no “fixed” claim before these gates pass.
