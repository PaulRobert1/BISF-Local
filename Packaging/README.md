# EXE launcher build

`BISF-Local.exe` is an x64 console launcher, not an installer or a standalone replacement for the PowerShell package. It invokes the adjacent `Invoke-BISF.ps1` using the absolute system Windows PowerShell path and preserves the child exit code. No execution-policy override or network access is added.

Build on Linux with Clang, LLD and the MinGW kernel32 import library:

```sh
sh Packaging/build-launcher.sh
python3 Packaging/test-launcher.py
```

The test uses a private Wine prefix under `/tmp` and a dummy PowerShell host. It verifies help, missing-script refusal, paths with spaces, argument forwarding, default invocation and child failure propagation. It does not execute image preparation. Native Windows PowerShell 5.1 startup tests also pass for omitted and explicit config paths, using a harmless stub framework. Run `Packaging\Test-EntryPoint.ps1` to repeat them. They reproduce the original parameter-default failure before the fix. Framework cleanup acceptance remains subject to the previously documented limits.

The GPL source and build script are included. Keep the full package together; see USER-MANUAL.md for use.

Current no-argument behavior is Prepare. The native entrypoint test asserts this using a stub module; explicit `-Mode Validate` is tested separately. `GlobalConfig.xml` enables the compatible cleanup/seal workflow. Configuration Manager remains disabled. Run `python3 Packaging/test-defaults.py` to check the packaged defaults.
