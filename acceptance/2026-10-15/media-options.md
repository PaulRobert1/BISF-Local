# CVAD 2507 LTSR media — confirmed scope

Checked 2026-10-15; user confirmed **2507 LTSR**. No downloads, license acceptance, authentication or VM operations performed.

**Current documented cumulative update: CU2.** Citrix lists both single-session and multi-session CU2 VDA versions as `2507.0.2100.2123` in Programs and Features. Use the exact CU2 package and record actual file/product versions; a `_2507.exe` filename alone does not establish CU level. [CU2 release and component versions](https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2507-ltsr/whats-new/cumulative-update-2.html).

| Lab target | Official support evidence | Appropriate full installer family |
|---|---|---|
| Windows 11 Pro 25H2, build26200 | CTX224843 lists Windows11 25H2/build26200 as supported with2507 LTSR and future CUs; single-session VDA requirements list Windows11 | `VDAWorkstationSetup_2507.exe` from CU2 media |
| Windows Server2025, build26100 |2507 requirements list Server2025 for multi-session VDA | `VDAServerSetup_2507.exe` from CU2 media |

Sources: [Windows build compatibility CTX224843](https://support.citrix.com/external/article?articleUrl=CTX224843-windows-10-11-compatibility-with-citrix-virtual-desktops-xendesktop), [2507 system requirements](https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2507-ltsr/system-requirements.html), [official package names and installation instructions](https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2507-ltsr/install-configure/install-vdas.html). Windows11 multi-session is separately restricted to Citrix DaaS; our Pro fixture is single-session. Server VDI is not the proposed Server2025 configuration.

**Media acquisition is gated.** The [official CU2 download page](https://www.citrix.com/downloads/citrix-virtual-apps-and-desktops/product-software/citrix-virtual-apps-and-desktops-2507ltsr-cu2-all-editions.html) redirected to Citrix `auth.cloud.com` OAuth sign-in during this read-only check. Citrix's [CU2 download/eligibility article CTX695228](https://support.citrix.com/external/article/CTX695228/citrix-virtual-apps-and-desktops-7-2507.html) says cumulative-update permissions depend on valid Software Maintenance or equivalent legacy support/subscription coverage. This does not establish this user's entitlement either way. No anonymous full Windows VDA download was verified.

Authorized options are the CU2 full-product ISO or the matching full standalone single-session and multi-session VDA installers obtained through an entitled Citrix account or already-authorized media. Core installers exist but omit components and should not replace the intended full master-image fixture merely to reduce download size. Citrix states distributed binaries are signed; after acquisition verify actual Authenticode status/signer, SHA256 and version before installation. No new binary signature or checksum has yet been verified. [Official VDA download instructions](https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2507-ltsr/install-configure/install-vdas.html).

CU2's documented compatible WEM version is `2507.1.110.1`; WEM is a compatible component outside CVAD LTSR lifecycle benefits. Existing WEM2005.2 observations must not be relabeled as that combination. Installer prerequisites include .NET4.8 and Visual C++2015–2022; multi-session installs/enables RDS role services. Use an explicitly named clean2507 baseline rather than silently upgrading/relabeling CVAD2012 test evidence.

Root's NAS inventory contains no matching2507 media. User also confirmed no disposable Citrix catalog; installing VDA alone cannot unblock broker/ICA/MCS/profile-attachment acceptance. Next dependency is authorized CU2 media access, followed by exact version/hash validation and isolated baseline tests.
