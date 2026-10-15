# Acceptance evidence milestone — IN PROGRESS

This reviewed, sanitized bundle is an interim evidence snapshot, not final acceptance. Subsequent live runs are not inferred.

Current W11 installation update: FSLogix and WEM installed with exit 0; VDA first invocation returned 3, then resumed setup returned 0 at 18:10:15 UTC. Final normal reboot and baseline qualification are pending. See [VDA installation result](evidence/w11/vda-resume-output.txt). No complete W11 vendor baseline is claimed.

# Disposable Windows acceptance — draft evidence map

Snapshot assembled 2026-10-15T18:02:35.588008+00:00. Live testing continues; this draft is not a completed acceptance certificate. PR #2 must remain draft. No production VM or MCS acceptance is claimed.

**Overall: IN PROGRESS / INCOMPLETE.** Both OS have GUI, native guard, ordinary profile/temp and recycle evidence. Windows 11 primary deferred finalization has 13 passing offline fixture checks. Server primary normal sign-out and copied-disk inspection also have 13 passing offline fixture checks. Server CVAD2012/WEM/FSLogix installation and shipped-agent previews now pass their observed scope; external broker/ICA/MCS/profile-attachment acceptance remains BLOCKED. The separate2507 LTSR comparison is BLOCKED by unavailable authorized media access. Pester remains regression evidence only.

## Identity and baseline

- Pinned commit: `fac7b1def5787e0d9ab8bcbb0707880d7572edc2`. Full manifest: [source-manifest.json](source-manifest.json).
- Acceptance specification: [source/ACCEPTANCE-TESTING.md](source/ACCEPTANCE-TESTING.md).
- Windows 11 VM `vm-10020`, `BISF-W11-TEST`: Windows 11 Pro 25H2, `10.0.26200`, x64. Windows PowerShell Desktop `5.1.26100.6584` recorded in bootstrap. [evidence/w11/os.json](evidence/w11/os.json), [evidence/w11/bootstrap.txt](evidence/w11/bootstrap.txt).
- Server 2025 VM `vm-10021`, `BISF-S25-TEST`: installed Microsoft Windows Server 2025 Standard Evaluation `10.0.26100`, x64; Windows PowerShell `5.1.26100.7462`. Native baseline and all 44 guest file hashes verified against pin. [evidence/server/native-baseline/baseline.json](evidence/server/native-baseline/baseline.json); [evidence/server/native-baseline/source-hashes.json](evidence/server/native-baseline/source-hashes.json).
- VMware Tools installer returned 3010 during Windows 11 bootstrap; subsequent native guest execution and observed normal-sign-out shutdown establish later guest availability. Current power/Tools state is not inferred from that historical baseline. Bootstrap ran as built-in Administrator; negative tests were reported run as normal `BISFOperator`. Record SID/RID, policy and per-run identity with final artifacts.
- Windows 11 primary baseline is pre-agents. Server vendor baseline snapshot10029 has CVAD2012 (`2012.0.0.28051`, VDA installer `7.28.0.30`), WEM `2005.2.0.1`, FSLogix `3.26.826.17182`, all44 source hashes verified and AutoAdminLogon=0. [evidence/server/vendor-baseline-complete.json](evidence/server/vendor-baseline-complete.json); [evidence/server/vendor-baseline-check.txt](evidence/server/vendor-baseline-check.txt). Server native configuration preserves installed-agent checks; its shipped-default preview now passes. Product-version presence is not compatibility certification or external catalog/profile-policy acceptance.
- Guest source inventory matches 44 pinned files; absent from guest inventory: none; mismatches: none. [evidence/w11/source-hashes.json](evidence/w11/source-hashes.json).
- Shipped XML SHA256: `6b084021132915686649260378953c7ed5acc217f30368de66c1857e0de288df`. Local baseline-output SHA256: `bef6b74e9db4d372f01ed29c14672c30cec8c28b33f0d47cc6f4fa626165eb01`. Guest source-hashes artifact SHA256: `50ecc11d8f3aad125578995f20bacce8b5f5097829f1d65c65c880ccf5d34ebc`.

## Required acceptance rows

PASS below means only the explicitly described native observation. PARTIAL never satisfies a complete checklist row. NOT TESTED means no qualifying evidence yet. BLOCKED means required external product/environment absent. Harness setup failures are distinguished from BISF failures.

| Checklist row | Windows 11 | Server 2025 | Evidence and remaining gate |
|---|---|---|---|
| Defaults, shipped XML Validate and Prepare -WhatIf | BLOCKED — shipped VDA missing; native variants PASS | PASS — shipped-agent preview, six checks | Server shipped Validate and Prepare -WhatIf exit0; profile/task/state/config invariance checks pass after agent installation. Earlier missing-BrokerAgent output is historical pre-install evidence. [evidence/server/agents-preview-results.json](evidence/server/agents-preview-results.json); [evidence/server/agents-preview-output.txt](evidence/server/agents-preview-output.txt); [evidence/w11/baseline-output.txt](evidence/w11/baseline-output.txt) |
| Checkbox editing | PASS — nine actual GUI cases | PASS — nine actual GUI cases | [evidence/w11/gui-v2-final/results.json](evidence/w11/gui-v2-final/results.json) run7a8a644fc1d84824be72d1d7ac918fda: four flag combinations/custom path, Cancel, stale, locked, malformed and legacy. Earlier automation failures retained as harness history. Server run a2a6d83b57984dd58a95f9fd1e735937: [evidence/server/gui-results-final.json](evidence/server/gui-results-final.json). |
| Log scope, all event/BISF flag combinations, with/without deferred cleanup | PARTIAL — true/true deferred fixture scope PASS | PARTIAL — true/true deferred fixture scope PASS | Both primary deferred runs have 13 passing offline fixture checks; Server powered off at 17:49:24 UTC. Seven other combinations on each OS remain NOT TESTED. [evidence/w11/offline-inspection-final.json](evidence/w11/offline-inspection-final.json); [evidence/server/normal-signout-power.json](evidence/server/normal-signout-power.json) |
| Ordinary profiles | PASS — observed native fixture scope | PASS — nine native checks | W11 inactive SID1002 removed; Server inactive SID1005 removed through CIM, preserved operator1000/built-in500/excluded1006/dependency1007 and system profiles. Dependency fixture preserved by explicit SID exclusion, not automatic path coverage. [evidence/w11/ordinary-native.txt](evidence/w11/ordinary-native.txt); [evidence/server/ordinary-native.txt](evidence/server/ordinary-native.txt); [evidence/server/before-primary-seal/ordinary-results.json](evidence/server/before-primary-seal/ordinary-results.json) |
| Dependencies | PARTIAL — native guards | PARTIAL — native guards | Both native guard runs protect a real registered dependency profile, leave sibling eligible and reject operator dependency. Full orchestration and alternate WEM cache remain untested. [evidence/w11/run-negative-revised.txt](evidence/w11/run-negative-revised.txt); [evidence/server/run-negative.txt](evidence/server/run-negative.txt) |
| Servicing | CONFIRMED FALSE-SUCCESS — cancelled queued task accepted | NOT TESTED | Queued task had advanced LastRun/result 0; deliberate cancellation left Ready/result 0, which BISF accepted as completion with exit 0. No successful servicing acceptance. [servicing-cancellation-review.txt](servicing-cancellation-review.txt) |
| Recycle Bin/temp | PASS — observed fixture scope | PASS — observed fixture scope | Old temp removed/new and unrelated retained on both OS. Current-operator recycle W11 4→0 and Server2→0, exit0. Other-user recycle preservation not independently measured. [evidence/w11/recycle-result.json](evidence/w11/recycle-result.json); [evidence/server/recycle-result.json](evidence/server/recycle-result.json); [evidence/server/ordinary-native.txt](evidence/server/ordinary-native.txt) |
| Protected SYSTEM handoff | PASS — observed staging | PASS — observed staging | Both staged exact SYSTEM/highest triggerless Finalize action with protected state. [evidence/w11/normal-signout/seal-task.xml](evidence/w11/normal-signout/seal-task.xml); [evidence/server/normal-signout/seal-task.xml](evidence/server/normal-signout/seal-task.xml); [evidence/server/normal-signout/seal-state-acl.json](evidence/server/normal-signout/seal-state-acl.json) |
| Disconnect versus sign-out | PARTIAL — timeout and normal sign-out evidence | PARTIAL — normal sign-out offline verified | W11 disconnected loaded operator timed out2minutes/result2 without shutdown; its separate normal sign-out cleanup is offline-verified. Server normal sign-out reached powered off at 17:49:24 and offline cleanup passed; its disconnect-timeout case is not done. [evidence/w11/disconnect-timeout/inspect-final.txt](evidence/w11/disconnect-timeout/inspect-final.txt); [evidence/server/normal-signout-power.json](evidence/server/normal-signout-power.json) |
| Successful finalization | PASS — primary native fixture scope | PASS — primary native fixture scope | Both copied-disk inspections have 13 passing checks. Server sealed snapshot 10030 retained after 17:49:24 UTC poweroff; copy task 16266 completed, inspected read-only on W11 and subsequently detached with its copy retained (root confirmed). Source Server remains off/unbooted since seal. [evidence/w11/offline-inspection-final.json](evidence/w11/offline-inspection-final.json); [evidence/server/normal-signout-power.json](evidence/server/normal-signout-power.json) |
| Clone | BLOCKED | BLOCKED | No disposable Citrix/MCS catalog; capture/provision and read-only VerifyClone not proven. Installed Server agents do not satisfy this gate. |
| Reboot/persistence | BLOCKED | BLOCKED | Requires disposable MCS clones and two cold boots with profile/identity persistence checks. |

### Log-scope subcases

| WindowsEventLogs | BISFLogs | Deferred operator cleanup | Windows 11 | Server 2025 |
|---|---|---|---|---|
| false | false | no | NOT TESTED | NOT TESTED |
| false | false | yes | NOT TESTED | NOT TESTED |
| false | true | no | NOT TESTED | NOT TESTED |
| false | true | yes | NOT TESTED | NOT TESTED |
| true | false | no | NOT TESTED | NOT TESTED |
| true | false | yes | NOT TESTED | NOT TESTED |
| true | true | no | NOT TESTED | NOT TESTED |
| true | true | yes | PASS — native fixture scope, offline verified | PASS — native fixture scope, offline verified |

Every log subcase requires explicit Shutdown, fresh snapshot, approved retention policy, external evidence retention, Application/System/Setup selection only, Security/vendor/unrelated/remote survival, and allowance for newly created shutdown events.

## Failure injections — individual evidence map

| Injection / required refusal | Windows 11 | Server 2025 | Evidence / remaining requirement |
|---|---|---|---|
| Operator remains loaded/referenced through timeout | PASS — real disconnected-session timeout | NOT TESTED | [evidence/w11/disconnect-timeout/inspect-final.txt](evidence/w11/disconnect-timeout/inspect-final.txt): operator Disc and Loaded=true; actual SYSTEM finalizer error after2minutes, LastTaskResult2, no shutdown; state retained Pending. |
| New loaded/referenced other profile during servicing | NOT TESTED | NOT TESTED | Existing loaded-profile preflight refusal is not this race injection. |
| New loaded/referenced other profile before final sealing | NOT TESTED | NOT TESTED | Need refusal before further destructive steps; SYSTEM quiescence. |
| Configuration changes while Prepare reads it | NOT TESTED | NOT TESTED | No concurrent config read/change run. |
| Configuration changes during servicing | NOT TESTED | NOT TESTED | No servicing/config race run. |
| Configuration changes after staging | NOT TESTED | NOT TESTED | No actual staged hash rejection run. |
| Enable previously unconfirmed log option | NOT TESTED | NOT TESTED | Must not acquire implicit approval/new hash. |
| Master identity changes on disposable copy | NOT TESTED | NOT TESTED | Never run repair finalizer on MCS clone. |
| Pending reboot before final deletion | NOT TESTED | NOT TESTED | Preflight fixture does not qualify late finalizer gate. |
| Unsafe ACL | PARTIAL — native guard PASS | PARTIAL — native guard PASS | Actual Everyone Modify ACL refused; restored. Full Prepare no-mutation gate still untested. |
| Redirected module | NOT TESTED | NOT TESTED | Config junction does not cover redirected module import. |
| Redirected schema | NOT TESTED | NOT TESTED | Separate schema reparse injection required. |
| Redirected configuration | PARTIAL — native guard PASS | PARTIAL — native guard PASS | Actual config junction refused; target unchanged; no full Prepare test. |
| Redirected state | NOT TESTED | NOT TESTED | Separate state path redirect required. |
| Redirected log path | NOT TESTED | NOT TESTED | Separate logging redirect required. |
| Retained operator state | NOT TESTED | NOT TESTED | Need existing protected pending state refusal before mutation. |
| Conflicting scheduled task | PARTIAL — native guard PASS | PARTIAL — native guard PASS | Actual disabled triggerless unrelated reserved task refused; owned fixture removed. |
| Task Scheduler enumeration fails | NOT TESTED | NOT TESTED | Must show error, not silently assume task absent. |
| Profile-provider removal denied | NOT TESTED | NOT TESTED | Need visible failure and no subsequent shutdown; restore snapshot after partial work. |
| State removal denied | NOT TESTED | NOT TESTED | Need actual finalizer cleanup failure evidence. |
| Task removal denied | NOT TESTED | NOT TESTED | Need actual scheduler denial evidence. |
| Selected event-log clearing denied | NOT TESTED | NOT TESTED | Need actual permission/error behavior. |
| BISF-log deletion denied | NOT TESTED | NOT TESTED | Need actual selected-file refusal and no shutdown. |
| Shutdown denied | NOT TESTED | NOT TESTED | Need actual request failure exposed; no masked success. |
| Finalize -WhatIf with missing config | PARTIAL — native preview PASS | PARTIAL — native preview exit0 | Exit0 with nonexistent config; full no-side-effects snapshots should be attached. |
| Finalize explicitly declined -Confirm | PASS — observed native decline | PASS — observed native decline | Both exit 0 with nonexistent configuration, without configuration/state access error. [evidence/w11/finalize-decline-output.txt](evidence/w11/finalize-decline-output.txt); [evidence/server/finalize-decline-output.txt](evidence/server/finalize-decline-output.txt) |
| Actual SYSTEM worker scheduling and self-unregistration through sign-out | PARTIAL | PARTIAL — offline task absence verified | W11 actual SYSTEM execution and shutdown observed; offline task file and TaskCache Tree absent. Orphan TaskCache Tasks GUID entries are not excluded without a preseal GUID. [Offline inspection — 13 PASS](evidence/w11/offline-inspection-final.json). Server offline inspection also confirms task file and TaskCache Tree absence; the same orphan-GUID scope limitation applies. [Server offline result](evidence/server/offline-inspection-final.json). |
| Pending reboot at Prepare platform gate (supplementary) | PARTIAL — native guard PASS | PARTIAL — native guard PASS | Revised PendingFileRenameOperations fixture produces expected pending-reboot refusal; all seven native guard cases PASS. Original protected-CBS write failure was a fixture setup failure. Full Prepare ordering and late finalizer reboot gate remain untested. [evidence/w11/run-negative-revised.txt](evidence/w11/run-negative-revised.txt) |

Failure evidence: [evidence/w11/run-negative.txt](evidence/w11/run-negative.txt), [evidence/w11/native-preview-output.txt](evidence/w11/native-preview-output.txt), [evidence/w11/finalize-decline-output.txt](evidence/w11/finalize-decline-output.txt). Revised harness: native-negative-preflight.ps1 (omitted from bundle; see OMITTED.json) and [native-negative-preflight-notes.txt](native-negative-preflight-notes.txt). First native-negative run: six PASS, one fixture setup FAIL. Revised run: seven PASS, including pending-reboot refusal: [evidence/w11/run-negative-revised.txt](evidence/w11/run-negative-revised.txt) and [evidence/w11/preseal/native-negative-434e5431a7e946eea9bdc5264050671c.json](evidence/w11/preseal/native-negative-434e5431a7e946eea9bdc5264050671c.json). Server native negative run also has sevenPASS: [evidence/server/run-negative.txt](evidence/server/run-negative.txt); [evidence/server/before-primary-seal/native-negative-1a39892140694e65ba19f5103fcfa692.json](evidence/server/before-primary-seal/native-negative-1a39892140694e65ba19f5103fcfa692.json). These private-guard results do not establish orchestrated Prepare ordering or finalization safety. Full-Prepare/finalizer fault harnesses are prepared locally but have no qualifying execution evidence yet.

## External clone checks

| Required check | Windows 11 | Server 2025 | Missing evidence |
|---|---|---|---|
| Broker registration | BLOCKED | BLOCKED | Intended VDA and MCS clone Registered in Studio/Director/Monitor. |
| ICA/HDX | BLOCKED | BLOCKED | Actual published launch, logon and reconnect. |
| WEM | BLOCKED | BLOCKED | Agent registration, processing, cache rebuild/sync and persistence. |
| FSLogix or UPM profiles | BLOCKED | BLOCKED | Intended provider installed; real attachment, sign-out and second logon. |
| Domain/network | BLOCKED | BLOCKED | Clone domain trust, DNS and backend connectivity. |
| Activation | BLOCKED | BLOCKED | Clone Windows/application activation through intended method. |
| Regression | BLOCKED | BLOCKED | Master versus clone logon, SMB and application comparison. |

## Supporting regression tests

Windows 11 clean Pester run: 264 passed, 0 failed, 0 skipped, exit0. [evidence/w11/pester-clean-output.txt](evidence/w11/pester-clean-output.txt). Server 2025 clean Pester run: 264 passed, 0 failed, 0 skipped, 162.68 seconds, exit 0: [evidence/server/pester-clean-output.txt](evidence/server/pester-clean-output.txt). Tests include mocks of Windows/destructive behavior and do not replace any native acceptance case above. Earlier runs and GUI failures remain retained; do not overwrite failed attempts with later successes.

## Permanent host RAM fix — separate infrastructure result

ESXi `192.168.100.48`: both OpenWebUI and Frigate use PCI GPU passthrough, so full guest reservations must remain. Original 40GiB+16GiB allocations left only97MiB admission budget against Windows211MiB overhead. An original40GiB reboot later failed by91MiB because admission capacity fluctuated; retry booted without change for telemetry.

Root changed only OpenWebUI `vm-10009` RAM/reservation from40960 to34816MiB (34GiB), keeping locked reservation and16vCPU. Existing model cap30GiB, context8192 and parallel1 preserved. Measured original model cgroup peak21.59GiB justified34GiB while retaining roughly3.2GiB guest capacity above cap. Frees6GiB host capacity; test VMs run sequentially.

Post-change verification: GPU113 model healthOK, GTX1080Ti9397MiB VRAM, identical model generated32tokens in2.22s versus2.20s baseline. Cgroup peak21.33GiB, zeroOOM/high/max events, zero swap and PSI averages0. OpenWebUI and4GiBWindows test both poweredOn; Frigate/OpenWebUI heartbeatgreen. Admission unreserved6137MiB is not physical-free headroom because Windows has no reservation. Host physicalused54796MiB snapshot; Windows quickstat was stale0 afterresume. This is boot/inference coexistence validation, not sustained peak stress or simultaneous personal24GiBWindows qualification. Personal Windows remained off; no model policy changes or Fedora worker changes.

Evidence: [ram-investigation/applied-fix.json](ram-investigation/applied-fix.json), [ram-investigation/model-inference.output.txt](ram-investigation/model-inference.output.txt), [ram-investigation/post34-inference.output.txt](ram-investigation/post34-inference.output.txt), [ram-investigation/post34-capacity.output.txt](ram-investigation/post34-capacity.output.txt), [ram-investigation/post34-host.json](ram-investigation/post34-host.json), [ram-investigation/findings.txt](ram-investigation/findings.txt).

## Full pinned source SHA256 manifest

| Path | SHA256 |
|---|---|
| `.github/workflows/pester-windows-2025.yml` | `9e784b12b7c31edc97b10ba88a71af849ff52ff7542b67b465a0f8685127027c` |
| `.gitignore` | `42447b04fc539bc10a02e3171ca36a732b0ed356950421266297f641799d3626` |
| `ACCEPTANCE-TESTING.md` | `32499b455bfb281d3e4e444b30a6ae13461e57937f463fe8444003d1e3ebc0cf` |
| `CONTINUE-HERE.txt` | `0084be3666621e50ae69ecf43296084caf89763eec71404b7a8e826ba74e135c` |
| `Configure-BISF-LogCleanup.ps1` | `546287773fa9bbf1b8a7e745da23ca61c9f37c414a567d8e2900353354f49647` |
| `GlobalConfig.xml` | `6b084021132915686649260378953c7ed5acc217f30368de66c1857e0de288df` |
| `GlobalConfig.xsd` | `d9cb30a9a088979b4206d5018d8af094b0152668ab022002b74b8b154a108920` |
| `IMPLEMENTATION-NOTES.md` | `509bd40388f17511a8b9837d2c7afd48cad9056309b5d5aa935edc7924e55ba2` |
| `Invoke-BISF.ps1` | `538f7b14485f41cb08c7815b1d6189f70df60ff187edd681ca75a67a648d4fa7` |
| `LICENSE` | `42289afe97723ded3b5ba603db0ebe16b8bfb33680f675d1565527c2273392f1` |
| `Modules/BISF.Local.psm1` | `7658e5c6c0eb3fa1d56f5a62e73307832a4ca77ee45a0ac0152c525f9e09ff7d` |
| `Modules/Private/Citrix.ps1` | `ea03a1a85557117d92b1e144d612ad11447b0b79d72bf49a0772aa09ca2a4df7` |
| `Modules/Private/CloneHealth.ps1` | `7b422c038923d61fd92d88c50d5f198e9db6ac8998e7be6d6a70b5418d495dbd` |
| `Modules/Private/Configuration.ps1` | `efff26ca0ccfe7bad768745315d509588f8e3cf2ef7f8c2b319c13d200a6688e` |
| `Modules/Private/Finalization.ps1` | `d6a83afce1365bf64016f872f3cf02b84d2d6bfa06d042962d18d51e973fb631` |
| `Modules/Private/Lifecycle.ps1` | `516922a53de8d8b8b4ecb6a11e6750b3f6ddaa9213c8f1c36db00dc56a4d7dc7` |
| `Modules/Private/LogCleanup.ps1` | `9d4b7e2d0bc844c69397c71e2645cbb9dfcc22a37e755a36afe999ac787911fb` |
| `Modules/Private/Logging.ps1` | `4ecb383b9521869ef885b89da4433a4bb31f7a357eb4d8522c9a631445f94ab3` |
| `Modules/Private/Maintenance.ps1` | `69dd33181521c7913f0047a621596607af33ecc674aa0b94295ba5a3aaa76a86` |
| `Modules/Private/Operations.ps1` | `686b94e861badf65ef95549459689792ca985156b1ed699edbb7d1f2b0499eec` |
| `Modules/Private/Preflight.ps1` | `c254fd6e335e744b6e725c81eacf90f6269f90f0077e41741ed94d7f505bc758` |
| `Modules/Private/Profiles.ps1` | `224cbcd3fe33ec12f5327f397618592cc59e79b0cd444d4312758073eac83304` |
| `Modules/Private/Runner.ps1` | `17b36cb78235bec7ad3fecd56415b9714c041bc1c6c306fef6993c3e7056b220` |
| `README.md` | `8370785a915cb091a8851db7ab491c0bc02b5ec57febe8c71e1e83f5069c3c85` |
| `REVIEW-2026-10-15.md` | `fdcdaaa47a9dd96e1d2de32aefc401b30b1599e2d38aebe72cb53c1145ac6202` |
| `TEST-RESULTS.md` | `558eba313c379ce85ebbdf440fed9c48acdd668501475258e260d6239ba89e41` |
| `Tests/Citrix.Tests.ps1` | `c08860d2bf07f055be85a5f5442ff79f3f3f1633318e55ca257738cd2a9d5714` |
| `Tests/CloneHealth.Tests.ps1` | `0f7a86eda559e81c778e1a39c2706bd8b9c5ee41756f1815044637d62abffc6e` |
| `Tests/Configuration.Tests.ps1` | `d43a270a94418f78437817894ae7389ce90bb0f7861411f96995c84706170851` |
| `Tests/Finalization.Tests.ps1` | `152dde2324874c4e981fd91ae8d217402d1d185e370fb6d8c92b7cc912460b22` |
| `Tests/Integration.Tests.ps1` | `92a351984fe89595df1a3ee76f7ff1fcb36911eba130929b8b2d913f9a65fa63` |
| `Tests/Invoke-Tests.ps1` | `18c535e5faf9477d75e644b75a98ac2f86707cf5e126a2a557ef7694026f12cd` |
| `Tests/Lifecycle.Tests.ps1` | `e86663014a2812839c7ecbeef8d06abb227ab6aff6a1c39f413ab0027d489bb5` |
| `Tests/LogCleanup.Tests.ps1` | `79daf92e44e175d7af3579509d1debaacf7de7b4c0459c9f068f961c4118c391` |
| `Tests/LogCleanupEditor.Tests.ps1` | `4253185d7d5d8b70e1f6650ea07f29f1d6fa736c6090435428cee6a56a14efdc` |
| `Tests/Maintenance.Tests.ps1` | `686293699f2812a905614a46946054bef8b586ab8e495318395bd85ba0231c94` |
| `Tests/Module.Tests.ps1` | `64a408dc58678b3a5727313307d0e4ef16f331a268c82e2646733a9fbe47ebb9` |
| `Tests/Operations.Tests.ps1` | `83b9aaa079a4bb8c8328cf7219a7c3d902593c7f4656d02a3c2d79d3dbfed7c6` |
| `Tests/Preflight.Tests.ps1` | `c3c3d5d83a84434c942323cff8a2a1911138f3212a6d8bf1ab2a84948052f5b6` |
| `Tests/Profiles.Tests.ps1` | `9b7f3d0fe3ea90f2d052791d5886191a4b2eeeb6668d6ef6252346d743c70329` |
| `Tests/SourceAudit.ps1` | `5083858a0102e8c5e059df2a51de0b25aabc9c2d640c032e57ac19bf4715f488` |
| `Tests/Static.Tests.ps1` | `27af6813bd946af8e94f07c19c0e6e2acebeeacca4e95fecdf58a0cceced5778` |
| `UPSTREAM.md` | `8a9bc2169c0d3bf2933b91cb098b98d8821d8128e506b8f5cf8bec9a01cfa761` |
| `WORK-HANDOFF.md` | `f40752f3cdde79b42983bd0055a84bf8c68078456aafc157745fa8cab27e9150` |

Final gate remains incomplete until the entire sign-out → profile removal → selected log cleanup → shutdown → capture → clone workflow passes on both target platforms and is reviewed. Any failed/timeout sealing image must not be captured. Merge remains separately authorized.

## Evidence limitations and servicing defect

The primary Windows 11 true/true deferred run reached shutdown after normal sign-out. Copy task 16239 completed; the copied disk was inspected read-only as disk 1 on Server, with expected serial/unique ID and configuration hash verified. Source Windows 11 was never booted for inspection. All 13 offline checks PASS: operator profile registration/directory absent; seal task file and TaskCache Tree absent; pending state absent; BISF fixture deleted; Citrix/WEM/FSLogix/unrelated preservation fixtures retain exact known content; Application/System/Setup old records absent; Security old record retained, with EVTX reads validated. [Offline inspection — 13 PASS](evidence/w11/offline-inspection-final.json); [Output](evidence/w11/offline-inspection-final-output.txt).

Server primary seal: exact staged SYSTEM task and normal sign-out poweroff observed at 17:49:24 UTC, snapshot 10030 retained. Read-only copied-disk inspection on W11 disk 1 passed all 13 checks, run 7c4d2e2f7c1145c8a95d0d6bd5f4656e. Copy task 16266 completed and root subsequently confirmed copy detachment and evidence completion; the copy is retained. The source Server has never booted since sealing. Server Security preservation uses the newest existing marker, explicitly documented in seal-events-before.json despite legacy Oldest field names; this avoids mistaking ordinary oldest-record rotation for clearing. W11 retains its original marker selection. [Server offline result](evidence/server/offline-inspection-final.json); [Server offline output](evidence/server/offline-inspection-output.txt). [offline-copy-receipts/evidence-server-normal-signout-both-logs-20261015T174949Z-863b93df93.vmdk.json](offline-copy-receipts/evidence-server-normal-signout-both-logs-20261015T174949Z-863b93df93.vmdk.json).

Limits: preservation fixtures are not actual vendor event channels. TaskCache Tasks orphan GUID entries were not excluded without a preseal task GUID. This proves the primary native fixture scope, not the other seven combinations on each OS or external clone lifecycle.

Earlier offline setup failures are retained: the copied Windows volume had a BitLocker `-FVE-FS-` header and receiver initially lacked support. BitLocker feature installation completed with Success=true/3010 and receiver reboot. A subsequent PS5.1 nested-array harness error was corrected before the successful inspection. Neither setup error was a BISF failure. No live source repair or operator-profile recreation was used.

Servicing false-success is confirmed by the recorded cancellation and source predicate: Maintenance.ps1 lines 83–90 treats an advanced LastRunTime as evidence of start, then Ready plus LastTaskResult 0 as successful completion. The queued task satisfied those values after deliberate cancellation. This establishes erroneous acceptance of cancellation; it does not prove the action never ran for an instant or establish a Windows Task Scheduler defect. No source fix has been made. Evidence: [servicing-cancellation-review.txt](servicing-cancellation-review.txt); [evidence/w11/servicing-before.json](evidence/w11/servicing-before.json); [evidence/w11/servicing-native.txt](evidence/w11/servicing-native.txt); [evidence/w11/servicing-inspect.txt](evidence/w11/servicing-inspect.txt); [evidence/w11/stop-queued-servicing.txt](evidence/w11/stop-queued-servicing.txt).

The disconnect-timeout task XML has empty Triggers. The diagnostic count of 1 was a PowerShell null-array artifact and is not evidence of an automatic trigger. Ordinary cleanup preserved dependency profile SID1004 through explicit SID exclusion; that run does not prove automatic dependency-path protection end to end. Earlier GUI failures were harness issues; the final nine-case run is the qualifying GUI observation.

## Acquired vendor media and external gate

User authorized NAS CVAD 2012 and WEM 2005.2.0.1 media. The acquired CVAD ISO internal version is `2012.0.0.28051`, recorded in [evidence/media-search/cvad2012-product-version.txt](evidence/media-search/cvad2012-product-version.txt). The separate `cvad-product-version.txt` concerns the NAS Citrix 2006 candidate, not this ISO. FSLogix 26.08 installer version is `3.26.826.17182`, with valid Microsoft signature per root's verification. Server FSLogix installation completed at 16:59:26 UTC with exit 0, version `3.26.826.17182`; `frxccds` and `frxsvc` are Running/Automatic. [Installation evidence](evidence/server/fslogix-install-output.txt). WEM 2005.2.0.1 installed with exit 0; [WEM evidence](evidence/server/wem-install-output.txt). CVAD2012 third installer invocation completed with exit0 at17:38:13.2115744Z, followed by final reboot and vendor baseline verification. [evidence/server/vda-third-output.txt](evidence/server/vda-third-output.txt); [evidence/server/post-vda-final-boot.txt](evidence/server/post-vda-final-boot.txt). FSLogix installation alone does not prove real profile attachment or lifecycle behavior. Acquired versions/signatures do not establish target-OS compatibility.

[evidence/media-search/download-manifest.json](evidence/media-search/download-manifest.json).

| Acquired artifact | SHA256 |
|---|---|
| `FSLogix_26.08.zip` | `129e111d4acf8502b9351e1cec0c92212dce8222ae5b8223163fbbea518e857c` |
| `FSLogixAppsSetup.exe` | `0baf7fe8195571060f0361b351e58fe6cd422ae521a96bab3e66d900544e8a30` |
| `WEM-Agent-Setup.exe` | `4f5db875cb621632077c1d463bdf04d23d1422186662668b552657e655ec5149` |
| `CVAD-2012.iso` | `521f5d038a5552deb0df82f4243eb5fb72d5d3c4edde9239bce29fa481bc1953` |

User confirms no disposable Citrix catalog exists. External MCS clone, broker/ICA, WEM and profile-attachment lifecycle checks remain BLOCKED, despite completed Server standalone agent installation. This report is local and unpublished; the final acceptance gate remains incomplete.

## Additional requested comparison

The user confirmed CVAD **2507 LTSR** as a separate comparison target. Comparison is BLOCKED: user cannot provide authorized2507 media access; official CU2 download requires sign-in/entitlement. [media-options.md](media-options.md). No2507 installation or test result is claimed. No disposable Citrix/MCS catalog exists, so external acceptance remains blocked for this comparison too.


## Additional requested profile case

| Case | Windows 11 | Server 2025 | Scope |
|---|---|---|---|
| User Profiles “Account Unknown” / unresolved SID removal | NOT TESTED | NOT TESTED | native-account-unknown.ps1 (omitted from bundle; see OMITTED.json) is a local unexecuted native test harness. It creates an owned orphan profile, verifies SID resolution failure, excludes all other ordinary profiles and invokes actual Prepare. No product change or PASS is claimed. |

## Supplementary bundle artifacts

- [proposed-fix-design.md](proposed-fix-design.md)
- [evidence/w11/normal-signout-power.json](evidence/w11/normal-signout-power.json)
- [evidence/w11/normal-signout/seal-state-acl.json](evidence/w11/normal-signout/seal-state-acl.json)
- [evidence/server/before-primary-seal/seal-events-before.json](evidence/server/before-primary-seal/seal-events-before.json)

[Artifact hashes and transformations](ARTIFACTS.json); [omitted/missing references](OMITTED.json). No private credentials, media binaries, seed images, registry hives, virtual disks or opaque MSI logs are included. Original hashes and staged hashes differ where text normalization, redaction or links changed; only original hashes authenticate the raw source artifact.
