# BISF-Local — Work mode continuation handoff

Updated: 2026-10-15. This is a source-based development handoff, not permission to run destructive actions on any Windows master.

## User objective
Build a Windows PowerShell 5.1 Citrix MCS golden-image preparation framework for Windows Server 2025, Windows 11, and appropriately reviewed newer client releases. Preserve strict safety, reliable preview modes, and production Citrix/Windows compatibility. Master operator profile cleanup is a *separate* SYSTEM phase after normal sign-out. Latest request added GUI checkboxes for optional final-stage log hygiene.

## GitHub state (VERIFY FRESH BEFORE ANY CHANGE)
- Private repository: https://github.com/PaulRobert1/BISF-Local
- Main implementation: `implementation` (do not replace or force-push).
- PR #1: https://github.com/PaulRobert1/BISF-Local/pull/1 — `fix/wem-cache-diagnostics-20261015` into `implementation`. WEM diagnostics, safe ordinary profile cleanup, Windows 11 release awareness; passing test suite. Open/unmerged.
- PR #2: https://github.com/PaulRobert1/BISF-Local/pull/2 — `feature/seal-finalization-maintenance-20261015` into PR #1 branch. **Draft**, open/unmerged. This is the branch to continue for master maintenance, operator finalization, log-cleanup checkboxes and clone health.
- Latest confirmed completed full test: 232 passed, 0 failed, Windows Server 2025 with Windows PowerShell 5.1, GitHub Actions https://github.com/PaulRobert1/BISF-Local/actions/runs/38732870070 at commit `81eef67be621a0d21ea267392b09c55d7dc07aac`. Recheck current head CI, because documentation changes can advance the SHA.

## Existing evidence on the actual master — do not assume updated package is deployed
- `SWCTXMASTER05`: Windows Server 2025 Standard build 26100, elevated 64-bit Windows PowerShell 5.1.
- Original local package: `C:\Install\BISF-Local_Test001`, its `Profiles.ps1` was missing in the read-only inventory: NOT the current PR branch.
- VDA: Citrix 2507 LTSR CU2, `BrokerAgent` running, `PvsVmAgent` running. WEM 2507 agents running, but WEM is not fully configured; `Local Databases Set` cache absent.
- Pending reboot condition `PendingFileRenameOperations` observed; `BlockPendingReboot=true` deliberately blocks actual Prepare until resolved through normal maintenance.
- Read-only profile inventory: 7 registered profiles, 2 inactive eligibility candidates, 5 protected (including active administrator), 0 blocked; operator must review candidates.
- Current user's original XML had WindowsTemp and CurrentUserTemp true, 7 days; actual admin-profile deletion wasn't supported in Test001. Do not overwrite that original folder.

## Features already coded in the PR #2 draft (verify sources, not only this description)
- Modes: `Validate`, `Prepare`, `Personalize`, protected SYSTEM-only `Finalize`, and read-only `VerifyClone`.
- Core: strict XML/XSD and script-local paths; configurable logging; Citrix VDA/MCS and WEM read-only checks; version inventory; no Sysprep.
- Inactive local Windows profile deletion by Win32_UserProfile / Remove-CimInstance with SID, reference count, path, reparse and loaded-session guards; no raw C:\Users deletion. Opt-in `Cleanup.UserProfiles`.
- System temp/current-user temp age-based cleanup; optional Recycle Bin; optional Microsoft Windows Servicing `StartComponentCleanup` scheduled task; preflight drive space, other loaded profiles, pending reboot.
- Deferred operator profile cleanup: protected, triggerless SYSTEM scheduled task; requires normal administrator sign-out, candidate SID with RID >=1000, master identity/config hash and path guard, checks before shutdown; no forced logoff. Opt-in `Finalization.RemoveOperatorProfile`.
- Read-only `VerifyClone` reports local OS, VDA, MCS, WEM, domain join, free disk and profile-manager services; deliberately DOES NOT certify broker registration, ICA logon, activation or FSLogix attach.
- Latest user request: `<LogCleanup><WindowsEventLogs>false</WindowsEventLogs><BISFLogs>false</BISFLogs></LogCleanup>` optional under GlobalConfig.xml, strict schema order after Servicing and before ConfigurationManager.
- Added `Configure-BISF-LogCleanup.ps1` Windows Forms checkbox UI. Saving only modifies XML, never runs Prepare or clears logs. Enabled options require explicit `FinalAction=Shutdown`.
- End-of-seal Windows channels are **Application, System, Setup only**; Windows Security audit log, Citrix/WEM/FSLogix/vendor logs and remote logs remain protected. BISF log deletion matches only logger-produced files, not arbitrary paths. Normal shutdown performs final log cleanup; operator SYSTEM finalizer does so after profile removal, before shutdown. Read-only Validate and WhatIf do not delete.
- No guarantee of zero event records: Windows can log again during shutdown. This feature must be reviewed against the customer's security retention policy.

## Guardrails, implementation policy
- Never run arbitrary external binaries, GPO modification, download helpers, WMI Win32_Product, Sysprep, forced logoff, broad recursive profile deletion, Windows Update database deletion, DisableTaskOffload/RSS/DEP toggles, or vendor WEM cleanup tools.
- Do not clear Windows Security logs or invent extra event channels. No default destructive log cleaning. Do not clean Citrix WEM cache before configuration.
- Do not merge PRs or modify the production master without explicit approval. Use PR #2 draft for experimentation. Keep PR #1 unchanged.
- Review exact existing code, not just this handoff, and test from the current head; no assumption that mocks certify real Windows behavior.

## Work tasks and acceptance criteria
1. Fetch repo, PR #1 and PR #2, compare against their base, confirm head SHA/CI, read README, TEST-RESULTS, XSD, GlobalConfig, Runner, Preflight, Profiles, Finalization, Maintenance, LogCleanup, CloneHealth, and full Pester tests.
2. Audit the new LogCleanup module and `Configure-BISF-LogCleanup.ps1` for Windows PowerShell 5.1 syntax, XML validation, secure file handling, expected channel availability, correct end-of-run placement, dry-run immutability, failure/no-shutdown behavior, and compliance-friendly defaults. Check GUI interactively on a disposable Windows VM; CI currently syntax-checks the GUI only.
3. Independently review the SYSTEM finalizer's task ownership, ACL/path boundaries, race conditions, retry handling, profile unload after RDP logout, staging-file protections and power transition. Add regression tests for edge cases.
4. Validate actual Windows Server 2025 and Windows 11 MCS templates in disposable/snapshotted VMs. Do NOT test profile deletion on the production SWCTXMASTER05. On test clone verify VDA registration in Citrix Studio/Monitor, ICA launch, WEM synchronization and FSLogix/UPM attachment.
5. Keep opt-in defaults false, run `.\Tests\Invoke-Tests.ps1` with Pester 5 on Windows PowerShell 5.1 and inspect GitHub Actions. Update README and TEST-RESULTS with the latest observed evidence, not guessed pass counts.
6. Once all mocked and live acceptance checks are documented, submit PR for independent review; only merge after operator authorization.

## How the user continues in ChatGPT Work
Open a new Work-mode chat, connect the existing GitHub app/connector if needed, and provide this GitHub file URL or paste this document. Ask Work to perform the above audit/test-and-improve workflow. A new Work chat cannot be started by this existing conversation automatically.
