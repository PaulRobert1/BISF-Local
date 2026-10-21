#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
resource=$(mktemp "${TMPDIR:-/tmp}/bisf-launcher-resource.XXXXXX.o")
trap 'rm -f "$resource"' EXIT HUP INT TERM
"${WINDRES:-x86_64-w64-mingw32-windres}" -I Packaging -i Packaging/Launcher.rc -o "$resource" -O coff
if [ -n "${CC:-}" ]; then
    # CC may select a MinGW GCC cross-compiler; its target/sysroot are built in.
    "$CC" -Os -fno-builtin -fno-stack-protector -nostdlib -Wl,--entry,entry -Wl,--subsystem,console -Wl,--dynamicbase -Wl,--nxcompat -Wl,--no-insert-timestamp Packaging/Launcher.c "$resource" -lkernel32 -o BISF-Local.exe
else
    clang --target=x86_64-w64-windows-gnu --sysroot=/usr/x86_64-w64-mingw32/sys-root/mingw -fuse-ld=lld -Os -fno-builtin -fno-stack-protector -nostdlib -Wl,--entry,entry -Wl,--subsystem,console -Wl,--dynamicbase -Wl,--nxcompat -Wl,--no-insert-timestamp Packaging/Launcher.c "$resource" -lkernel32 -o BISF-Local.exe
fi
