#!/bin/sh
# Builds svc/leafiaie (static ARM, no libc) for the Stinger appleie service and checks it under qemu.
# Run in the leafia container.
set -e
N=/work/ports/stinger-260507-svc/native
O=/work/ports/stinger-260507-svc/leafiaie
clang --target=armv7a-linux-androideabi -march=armv7-a -marm -mfloat-abi=softfp -Os -ffreestanding -fno-builtin \
    -fno-stack-protector -nostdlib -static -fuse-ld=lld -e _start -Wl,--gc-sections -o $O $N/leafiaie.c
llvm-strip $O
ls -l $O
llvm-readelf -h $O | grep -E "Type|Machine"
# dry run: the exact G70 commands
for t in 0 1 2; do
    got=$(qemu-arm-static $O -n wlan0 add_ie $t 00A040 0000020021)
    [ "$got" = "cmd: add_ie $t 00A040 0000020021" ] || { echo "FAIL dry $t: $got"; exit 1; }
done
# real ioctl with no such interface: refused (exit 1), no crash
set +e
qemu-arm-static $O leafiax0 add_ie 0 00A040 0000020021; rc=$?
set -e
[ $rc = 1 ] || { echo "FAIL: missing interface gave exit $rc"; exit 1; }
set +e
qemu-arm-static $O wlan0 >/dev/null; rc=$?
set -e
[ $rc = 2 ] || { echo "FAIL: missing command gave exit $rc"; exit 1; }
echo "LEAFIAIE OK"
