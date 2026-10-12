# Source provenance and changes

This is an unofficial, reduced-scope derivative of **Base Image Script Framework
(BIS-F)** by Matthias Schlimm and contributors (EUCweb; source files also credit
Login Consultants Germany GmbH and individual contributors). It is not an upstream
release and does not imply upstream endorsement or equivalent feature coverage.

- Original public repository: https://github.com/EUCweb/BIS-F
- Reference tag: https://github.com/EUCweb/BIS-F/tree/7.1912.7
- Pinned commit: `351b43dbd165ac864f4bc190cc61c866889eb598`
- Original retrieved directly from GitHub, not the user's repository.
- Local rewrite/modification date: 2026-10-12.
- License: original GNU GPLv3 text included unchanged in LICENSE. The derivative
  source is distributed under GPLv3. No upstream binaries are included.

The original scripts were reviewed as source references, particularly:

- Framework/SubCall/Preparation/97_PrepBISF_PRE_BaseImage.ps1
- Framework/SubCall/Preparation/10_PrepBISF_SCCM.ps1
- Framework/SubCall/Personalization/10_PersBISF_SCCM.ps1
- Framework/SubCall/Preparation/52_PrepBISF_VMWareTCPIPOptimizations.ps1
- Framework/SubCall/Global/BISF.ps1 and BISF.psm1

The original policy-driven framework is replaced, rather than copied into a wrapper.
A successful run of this package therefore covers only its explicitly selected actions.

| Original capability/action | Local edition |
|---|---|
| Policy-driven global settings and GPO refresh | Replaced by strict GlobalConfig.xml/XSD; no policy access |
| Logging | New configurable Enabled and Path, default `.\logs` |
| Global RSS disable and DisableTaskOffload mutation | Removed; preserve current settings |
| DEP AlwaysOff and other boot configuration changes | Removed; preserve current settings |
| VMware network tweaks | Excluded |
| Temporary cleanup | Restricted age-based file cleanup with protected paths and link checks |
| SCCM preparation SMS certificates/SMSCFG.ini | Explicit opt-in via PowerShell/.NET, with service stop |
| SCCM personalization WMIC TrustedRootKey deletion | Explicit opt-in via Get-CimInstance/Remove-CimInstance |
| SCCM inventory/scheduler history and cache resets | Excluded |
| Machine-wide crypto key folder rename and Entra leave | Excluded |
| Startup personalization via schtasks.exe | Optional local task via ScheduledTasks cmdlets, with protected state |
| Shutdown via external utility | Optional Stop-Computer after success |
| Licensing rearm, Sysprep, vendor optimizers and agent sealing executables | Excluded under strict no-executable requirement |
| PVS disk/cache manipulation, VHD compaction and write-cache formatting | Excluded; deployment product remains responsible |
| FSLogix rule deletion/distribution and other vendor integrations | Excluded; existing configuration preserved |
| Image capture/provisioning | External supported workflow, not performed here |

Reference documentation used for the replacement approach:

- [Microsoft Configuration Manager client deployment, including reference image preparation](https://learn.microsoft.com/en-us/intune/configmgr/core/clients/deploy/deploy-clients-to-windows-computers)
- [Microsoft Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps)

The attached compatibility investigation informed the removed legacy actions. This
package has not been executed against the user's Windows images. See TEST-RESULTS.md
and the Windows acceptance checklist in README.md.
