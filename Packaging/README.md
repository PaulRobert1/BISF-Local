# EXE launcher build

`BISF-Local.exe` is an x64 console launcher, not an installer or a standalone replacement for the PowerShell package. Its embedded process manifest requests administrator privileges through the normal Windows UAC prompt. It invokes the adjacent `Invoke-BISF.ps1` using the absolute system Windows PowerShell path and preserves the child exit code. No execution-policy override or network access is added. The manifest applies to every EXE invocation, including help and validation; UAC consent or administrator credentials are still required when Windows requests them.

Build on Linux with Clang, LLD, MinGW windres and the MinGW kernel32 import library:

```sh
sh Packaging/build-launcher.sh
python3 Packaging/test-launcher-manifest.py
python3 Packaging/test-launcher.py
```

Alternatively, use a MinGW GCC cross-compiler with `CC=x86_64-w64-mingw32-gcc sh Packaging/build-launcher.sh`. Set `WINDRES` if its executable has a different name. `Launcher.rc` embeds `Launcher.manifest` as resource type 24, process manifest ID 1. The resource test inspects the built executable's PE resource tree and confirms the requested administrator level and source manifest match; it runs without Windows or Wine.

The separate Wine test uses a private prefix under `/tmp` and a dummy PowerShell host. It verifies help, missing-script refusal, paths with spaces, argument forwarding, default invocation and child failure propagation. It does not execute image preparation or validate native Windows UAC behavior. Run `Packaging\Test-EntryPoint.ps1` from an elevated Windows PowerShell 5.1 console for the native startup checks using harmless stub framework and installation modules. These check omitted and explicit config paths and child exit propagation. The elevated console is necessary because redirected child output cannot be combined with a new UAC elevation request. The desktop UAC prompt must be checked separately by opening the EXE normally on Windows. Framework cleanup acceptance remains subject to the previously documented limits.

The GPL source and build script are included. Keep the full package together; see USER-MANUAL.md for use.

Current no-argument behavior is Prepare. The native entrypoint test asserts this using a stub module; explicit `-Mode Validate` is tested separately. `GlobalConfig.xml` enables the compatible cleanup/seal workflow. Configuration Manager remains disabled. Run `python3 Packaging/test-defaults.py` to check the packaged defaults.
