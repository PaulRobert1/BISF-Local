# Verification record

2026-10-12, Linux x86_64 development host.

- PowerShell 7.6.6, Pester 5.7.1: 130 tests passed, 0 failed.
- Actual suite entry point: `Tests/Invoke-Tests.ps1`.
- Runtime files parsed by PowerShell; default XML exercised against its XSD.
- Source audit checks for forbidden external execution, legacy mutations and binaries.
- Windows service, CIM, task and ACL effects are mocked in portable tests.
- Real XML/file logging, cleanup selection/deletion, and JSON state round trips exercised
  against disposable local test directories. No Windows master image was modified.

Not executed: Windows PowerShell 5.1, Server 2025/Windows 11 image lifecycle,
real Citrix VDA/WEM 2507 installations, Configuration Manager, Windows ACL enforcement,
actual SYSTEM startup task,
PVS/MCS provisioning or real shutdown. These require the Windows acceptance checklist
in README.md. This is development verification, not production certification.

Independent source review completed. All five actionable findings were addressed:
state-file trust checks before reads, ScheduledTasks Function discovery, default
empty-plan strict-mode behavior, post-shutdown logging order, and durable success
under combined failures. Regression tests were observed failing before fixes and
passing afterward. The reviewer did not re-review the fix pass; automated regression
verification was performed by the implementer.

PSScriptAnalyzer 1.24.0 PSUseCompatibleSyntax targeting Windows PowerShell 5.1:
no findings in the entry script or runtime modules. This checks syntax, not actual
Windows API behavior. Direct CLI execution on Linux returned exit code 1 with an
unsupported-host diagnostic and no image changes.

No minor review findings were deferred. Runtime tools and development dependencies
are outside the shipped archive. See IMPLEMENTATION-NOTES.md for decisions and limits.


Citrix extension verification: 37 additional tests cover XML/backward compatibility,
release checks, missing MCS component, WEM prerequisites, default/alternate cache
selection, local-path rejection, WEM cache exclusion from cleanup, WhatIf/Validate,
VDA stop/shutdown ordering, partial stop failure, recovery and the accepted-shutdown
boundary. A module-scope test exercises enabled VDA discovery under production strict
mode. Windows inventory, registry discovery and service-controller calls remain mocked.

The Citrix reviewer identified an unbounded Stop-Service wait; fixed using NoWait and
explicit bounded waits, with focused failing-then-passing regressions. The reviewer
rechecked the fix and reported no definite remaining issue. Their minor suggestion to
assert the current controller recovery path rather than the obsolete Start-Service call
was also applied. No review findings were deferred.

Version-independent update: all 130 tests pass. Tests cover older and newer version
strings, unknown resources, legacy Norskale host service discovery, absence of the
optional logon service, existing Windows eligibility checks and existing failure
recovery. No Citrix version comparison remains. Windows runtime and actual agent/OS
compatibility remain unverified.

## WEM cache diagnostics regression additions (2026-10-15)

The `fix/wem-cache-diagnostics-20261015` branch adds four read-only
WEM cache state tests and one integration test verifying that a missing cache
logs a warning in Validate mode without stopping services or requesting shutdown.
It also adds a GitHub Actions workflow using the `windows-2025` runner and
Windows PowerShell 5.1 with Pester 5.7.1.

The 2026-10-12 revision passed 130 portable Pester tests. The first updated
WEM-only branch passed **135/135 Pester tests** on Windows Server 2025 / Windows
PowerShell 5.1: https://github.com/PaulRobert1/BISF-Local/actions/runs/38701590882.
These Windows-hosted tests still mock Citrix agents and do not certify an MCS clone.

## Profile cleanup regression additions (2026-10-15)

An opt-in Cleanup.UserProfiles operation uses native Win32_UserProfile inventory
and Remove-CimInstance (wrapped for Pester) with protective SID/path guards.
Tests cover disabled-by-default legacy XML, explicit exclusions, operator and
built-in administrator protection, path boundaries, special/system identities,
loaded-profile and RefCount blockers, Validate/WhatIf immutability, and
per-SID pre-deletion revalidation against lifecycle/path changes.

**158/158 Pester tests passed, 0 failed, 0 skipped** on Windows Server 2025
with Windows PowerShell 5.1, GitHub Actions:
https://github.com/PaulRobert1/BISF-Local/actions/runs/38705010124.

Profile deletion in this CI run was simulated by mocks. No real profile was
deleted, no real Citrix agent was installed, and no MCS provisioning was tested.
Actual MCS master image integration and clone acceptance remain required.

## Windows 11 release-awareness tests (2026-10-15)

Platform inventory now recognizes Windows 11 21H2, 22H2, 23H2, 24H2,
25H2, 26H2, and the special 26H1 release, while checking the workstation
ProductType separately from Windows Server 2025 (shared 26100 build).
Unknown future client builds generate an explicit compatibility warning;
unknown future server builds remain blocked. Regression cases include
26H2's VDA CU compatibility guidance and negative OS candidates.

Windows 11 is covered by portable mocked-OS unit tests on the Windows
Server 2025 GitHub runner. **No actual Windows 11 virtual machine or
Citrix single-session VDA was tested** by these checks. Verify MCS
provisioning, user-profile behavior, and Citrix support on an isolated
Windows 11 template before production rollout.
