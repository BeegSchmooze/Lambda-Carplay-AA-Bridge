#!/bin/sh
# Mock installs of the multi-firmware Stinger turn-by-turn package (ports/build_tbt_multi.py):
# each firmware's stock files (fresh install, the set it picked, byte-identical uninstall), other
# conditions, refused on G70 files and with the bridge installed, and upgrades from the
# single-firmware test builds already on cars.
# usage: mock_tbt_multi.sh  (run in the leafia container)
W=/work
SH=$(command -v mksh || echo /bin/sh)
R=${TBT_MULTI:-$W/release-stinger-tbt}/dist   # TBT_MULTI: the multi package's release dir
(cd $R && printf '[nemesis]\nversion=1.0\ntype=install\npath=packages/g70.tbt.zip\n' > NEMESIS.data \
    && rm -f Stinger-tbt.zip && zip -qrX Stinger-tbt.zip NEMESIS.data packages)
Z=$R/Stinger-tbt.zip
F251=CKPE23.USA.0000.V014.011.251120
F260=CKPE23.USA.0000.V015.012.260507

t() {  # $1 label, $2 stock dir, $3 firmware, $4 expected set (or "refused"), rest: env
    _l=$1; _s=$2; _f=$3; _e=$4; shift 4
    echo "== $_l"
    env MOCK_PKG=g70.tbt MOCK_SH=$SH "$@" sh $W/tools-g70/mock-test.sh $Z $_f ckpe23_us $_s > /tmp/mocktbtm.out 2>&1
    grep -E "INSTALL|UNINSTALL|REFUSED" /tmp/mocktbtm.out | head -2
    _x=$(sed -n 's/^sandbox (logs[^)]*): //p' /tmp/mocktbtm.out)
    _set=$(sed -n 's/^firmware set \([^ ]*\) .*/\1/p' $_x/pre.log 2>/dev/null | head -1)
    case "$_e" in
        refused) grep -q "FAIL" $_x/pre.log || echo "FAIL: not refused" ;;
        *) [ "$_set" = "$_e" ] && echo "picked set $_set" || echo "FAIL: picked set '$_set', expected $_e" ;;
    esac
    grep -h "^FAIL" $_x/pre.log $_x/post.log 2>/dev/null | head -2
}
t "251120: fresh install" $W/ports/stinger-251120 $F251 251120
t "260507: fresh install" $W/ports/stinger-260507 $F260 260507
t "260507: install descriptor on the drive" $W/ports/stinger-260507 $F260 260507 MOCK_USB_DESCRIPTOR=1
t "260507: NEMESIS 1.15" $W/ports/stinger-260507 $F260 260507 MOCK_NEMESIS=1.15
t "251120: Android down" $W/ports/stinger-251120 $F251 251120 MOCK_ANDROID_DOWN=1
t "the firmware name of the other build (files decide)" $W/ports/stinger-251120 $F260 251120
t "the 251120 G70's files (must be refused)" $W/g70-stock IKFL.USA.0000.V014.011.251120 refused
t "full bridge installed (must be refused)" $W/ports/stinger-260507 $F260 refused MOCK_BRIDGE_INSTALLED=1

u() {  # $1 label, $2 old package zip, $3 stock dir, $4 firmware
    echo "== upgrade: $1"
    env MOCK_PKG=g70.tbt MOCK_SH=$SH sh $W/tools-g70/mock-upgrade.sh $2 $Z $4 ckpe23_us $3 2>&1 | grep -E "INSTALL|UNINSTALL|REFUSED|FAIL" | head -4
}
u "251120 test build" $W/prev/stinger-251120-tbt-test1-g70.tbt.zip $W/ports/stinger-251120 $F251
u "260507 test build (on the car)" $W/prev/stinger-260507-tbt-test1-g70.tbt.zip $W/ports/stinger-260507 $F260
u "v1.0 on 251120" $W/prev/stinger-tbt-v10-g70.tbt.zip $W/ports/stinger-251120 $F251
u "v1.0 on 260507" $W/prev/stinger-tbt-v10-g70.tbt.zip $W/ports/stinger-260507 $F260
