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
- Framework/SubCall/Personalization/02_PersBISF_CTX.ps1 (legacy WEM behavior reviewed, not retained)
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
| Windows Update component cleanup | Enabled in the supplied XML; inbox Dism Repair-WindowsImage cmdlet with StartComponentCleanup, synchronous completion and reboot checks; no direct DISM.exe |
| Recycle Bin cleanup | Optional current-user system drive Clear-RecycleBin |
| Operator's active profile removal | Optional protected SYSTEM one-shot finalizer after normal user sign-out; irreversible cleanup only after profile unload |
| Storage / session readiness | Optional minimum system-drive free-space and other loaded-profile preflight gates |
| Inactive profile cleanup (Delprof2 upstream) | Optional, native Win32_UserProfile/Remove-CimInstance implementation; protects active/system/admin and explicitly excluded SIDs; no external executable |
| SCCM preparation SMS certificates/SMSCFG.ini | Explicit opt-in via PowerShell/.NET, with service stop |
| SCCM personalization WMIC TrustedRootKey deletion | Explicit opt-in via Get-CimInstance/Remove-CimInstance |
| SCCM inventory/scheduler history and cache resets | Excluded |
| Machine-wide crypto key folder rename and Entra leave | Excluded |
| Startup personalization via schtasks.exe | Optional local task via ScheduledTasks cmdlets, with protected state |
| Shutdown via external utility | Optional Stop-Computer after success |
| Licensing rearm, Sysprep, vendor optimizers and agent sealing executables | Excluded under strict no-executable requirement |
| PVS disk/cache manipulation, VHD compaction and write-cache formatting | Excluded; deployment product remains responsible |
| FSLogix rule deletion/distribution and other vendor integrations | Excluded; existing configuration preserved |
| Citrix VDA preparation | Version inventory/MCS component checks; optional Desktop Service stop immediately before shutdown |
| Legacy WEM service restarts/cache utility | Replaced with prerequisite checks and cache preservation; WEM 2507 manages clone databases itself |
| Image capture/provisioning | External supported workflow, not performed here |

Reference documentation used for the replacement approach:

- [Microsoft Configuration Manager client deployment, including reference image preparation](https://learn.microsoft.com/en-us/intune/configmgr/core/clients/deploy/deploy-clients-to-windows-computers)
- [Microsoft Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps)

Citrix extension references (reviewed 2026-10-12):

- [VDA 2507 installation and MCS component selection](https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2507-ltsr/install-configure/install-vdas.html)
- [MCS master preparation; no Sysprep](https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2507-ltsr/install-configure/machine-catalogs-create.html)
- [WEM 2507 agent services, cache location and clone startup behavior](https://docs.citrix.com/en-us/workspace-environment-management/2507/install-and-configure/agent-host.html)
- [Citrix identifies PvsVmAgent as the Machine Identity Service Agent](https://support.citrix.com/external/article/CTX141113/limited-release-hotfix-xd710misawx64001.html) (historical naming evidence, not 2507 certification)
- [Windows PowerShell 5.1 Stop-Service, including NoWait](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/stop-service?view=powershell-5.1)

The attached compatibility investigation informed the removed legacy actions. This
package has not been executed against the user's Windows images. See TEST-RESULTS.md
and the Windows acceptance checklist in README.md.
