#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
clang --target=x86_64-w64-windows-gnu --sysroot=/usr/x86_64-w64-mingw32/sys-root/mingw -fuse-ld=lld -Os -fno-builtin -fno-stack-protector -nostdlib -Wl,--entry,entry -Wl,--subsystem,console -Wl,--dynamicbase -Wl,--nxcompat -Wl,--no-insert-timestamp Packaging/Launcher.c -lkernel32 -o BISF-Local.exe
