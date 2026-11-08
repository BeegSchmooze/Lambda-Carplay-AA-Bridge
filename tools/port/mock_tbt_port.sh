#!/bin/sh
# Mock installs of a port's g70.tbt on that port's stock files: fresh install + uninstall, other
# conditions, wrong stock (the 251120 G70) refused, full bridge installed refused.
W=/work
PORT=$1; FW=$2
RG=${3:-ikfl_us}   # region folder (ro.mobis.targetdir name); the Stinger's is ckpe23_us
R=$W/release-$PORT-tbt/dist
cd $R
printf '[nemesis]\nversion=1.0\ntype=install\npath=packages/g70.tbt.zip\n' > NEMESIS.data
rm -f G70-tbt.zip && zip -qrX G70-tbt.zip NEMESIS.data packages
SH=$(command -v mksh || echo /bin/sh)
S=$W/ports/$PORT
t() { echo "== $1"; shift; env MOCK_PKG=g70.tbt MOCK_SH=$SH "$@" sh $W/tools-g70/mock-test.sh $R/G70-tbt.zip $FW $RG $S 2>&1 | grep -vE "^sandbox|^shell"; }
t "fresh install"
t "install descriptor on the drive" MOCK_USB_DESCRIPTOR=1
t "NEMESIS 1.15" MOCK_NEMESIS=1.15
t "Android down" MOCK_ANDROID_DOWN=1
echo "== the 251120 G70's files (must be refused)"
env MOCK_PKG=g70.tbt MOCK_SH=$SH sh $W/tools-g70/mock-test.sh $R/G70-tbt.zip IKFL.USA.0000.V014.011.251120 g70_us $W/g70-stock 2>&1 | grep -E "REFUSED|FAIL|INSTALL" | head -4
echo "== full bridge installed (must be refused)"
env MOCK_PKG=g70.tbt MOCK_SH=$SH MOCK_BRIDGE_INSTALLED=1 sh $W/tools-g70/mock-test.sh $R/G70-tbt.zip $FW $RG $S 2>&1 | grep -E "REFUSED|FAIL|INSTALL" | head -4
