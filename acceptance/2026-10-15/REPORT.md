# BISF issue #3 — candidate evidence, 16 October 2026

Candidate: [`573cdf6`](https://github.com/PaulRobert1/BISF-Local/commit/573cdf6cf41d4fa053256af5bd5a630b9e172f2f), draft [PR #5](https://github.com/PaulRobert1/BISF-Local/pull/5). [44-file candidate manifest](candidate-20261016/source-manifest.json).

**Both OS completed local offline validation for the tested scenario. Overall deployment acceptance remains incomplete:** no disposable MCS catalog exists and broader native gate coverage remains outstanding. Server was completed/reported before Windows 11 inspection resumed, as requested. No PR was merged.

| Candidate check | Server 2025 / build 26100 | Windows 11 / build 26200 |
| --- | --- | --- |
| Installed agents | CVAD 2507 LTSR CU2, WEM 2507, FSLogix 3.26.826.17182 | Same versions |
| Offline tests | [278 passed, 0 failed/skipped](candidate-20261016/server/candidate-full-tests.json) | [278 passed, 0 failed/skipped](candidate-20261016/w11/candidate-full-tests.json) |
| Native offline Validate / Prepare preview | [Both exit 0; profiles unchanged](candidate-20261016/server/offline-preview.json) | [Both exit 0; profiles unchanged](candidate-20261016/w11/offline-preview.json) |
| Offline Prepare, normal console signout, SYSTEM finalization and shutdown | [PASS; retained sealed snapshot 10050](candidate-20261016/server/offline-seal/receipt.json) | [PASS; retained powered-off snapshot 10049](candidate-20261016/w11/offline-seal/postboot-receipt.json) |
| Postboot cleanup/preservation | [13/13 PASS](candidate-20261016/server/offline-seal/postseal-results.json), NIC remained disconnected through inspection | [13/13 PASS](candidate-20261016/w11/offline-seal/postseal-results.json), NIC remained disconnected through inspection |

Both OS checks prove operator profile registration/directory removal, absent seal task/state, selected BISF and Application/System/Setup log cleanup, and preservation of Security, vendor files and unrelated files. These are postboot checks with a retained sealed snapshot, not a new copied-disk or MCS certificate. Each NIC was restored only after inspection; both disposable VMs were then shut down normally.

Runtime needs no Internet download, release catalog, telemetry or module feed. Stage the package and required installed agents locally. Newer Windows releases are eligible with compatibility-review diagnostics; Citrix/WEM versions remain informational. This is not vendor certification of every future version.

Optional ComponentCleanup retains the Microsoft scheduled task and fails closed on unverifiable completion. Ready/result 0 is insufficient because cancellation can produce the same aggregate result. **No automatic verified-success path is claimed.** Review servicing separately and leave ComponentCleanup disabled for preparation; no DISM substitution, ResetBase or automatic cancellation was added.

Failure evidence is retained: the first Server attempt used a disconnected RDP session; the operator stayed loaded and BISF correctly refused shutdown ([review](candidate-20261016/server/offline-failure-review.json), [log](candidate-20261016/server/offline-finalizer.log), snapshot 10046). A separate baseline run used a verified console session and passed. Windows 11's original 90-second harness wait expired while native profile removal continued; that same Prepare later returned 0 without rerunning it. Postboot inspection was paused as requested, then completed after Server. [Windows 11 observation history](candidate-20261016/w11/offline-seal/observation-history.json) records the observation timeout, priority pause and the scope of each receipt. No Prepare or finalizer was rerun to recover the harness.

The [earlier baseline report](BASELINE-REPORT.md) concerns commit fac7b1d and includes Account Unknown profile, GUI, ordinary cleanup, timeout, copied-disk and Server log-matrix evidence. Its historical skip/media statements are superseded by this update; baseline PASS results are not relabeled as 2507 candidate results. The complete native failure-injection and both-OS flag matrix gates have not been rerun/completed for this candidate. External broker/HDX/WEM backend/profile attachment, MCS capture/clones and activation remain unverified. Keep the acceptance gate and PRs open/draft.

The [earlier personal-VM observation](candidate-20261016/protected-vm.json) at 06:45 UTC recorded powered off, no snapshots and the original configuration version. [Final inventory at 07:39 UTC](candidate-20261016/final-state.json) instead records it powered on, still without snapshots, with configuration version 07:26:29. This test run issued no mutations to that VM and leaves its current state untouched; the earlier “remains off/unchanged” wording is superseded. Both disposable test VMs are off. SWCTXMASTER05 was excluded. Signature verification was omitted at the user's request; hashes identify tested bytes only. No credentials, media, hives or raw MSI logs are included.
