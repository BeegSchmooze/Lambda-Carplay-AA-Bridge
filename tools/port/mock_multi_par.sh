#!/bin/sh
# ports/mock_multi.sh with every case in parallel (each case has its own sandbox and output
# file); prints the results in the original order.
# usage: mock_multi_par.sh  (run in the leafia container)
W=/work
SH=$(command -v mksh || echo /bin/sh)
R=$W/release-multi
(cd $R/dist && printf '[nemesis]\nversion=1.0\ntype=install\npath=packages/g70.carplay.bt.zip\n' > NEMESIS.data \
    && rm -f G70.zip && zip -qrX G70.zip NEMESIS.data packages)
Z=$R/dist/G70.zip
FX=$W/ports/g70-250818/onebin/featurexml.cfg
stock() {
    _s=/tmp/mstock-$1; rm -rf $_s; mkdir -p $_s/onebin/ikfl_us
    cp -r $2/app $2/lib $2/framework $_s/
    cp -r $3/etc $3/build.prop $_s/
    cp $FX $_s/onebin/ikfl_us/featurexml.cfg
    [ -f $_s/lib/libstagefright_soft_aacdec.so ] || cp $W/g70-stock/lib/libstagefright_soft_aacdec.so $_s/lib/
    rm -f $_s/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml \
          $_s/etc/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml
}
stock 251120 $W/g70-stock $W/ports/g70-250818
stock 250818 $W/ports/g70-250818 $W/ports/g70-250818
stock 260507 $W/ports/g70-260507 $W/ports/g70-260507
stock other $W/ports/g70-260507 $W/ports/g70-260507
cp $W/ports/g70-250818/app/HKMC_GPM.apk $W/ports/g70-250818/app/HKMC_GPM.odex /tmp/mstock-other/app/
O=/tmp/mockpar; rm -rf $O; mkdir -p $O

t() {  # $1 n, $2 label, $3 stock name, $4 firmware, $5 expected set (or "refused"), rest: env
    _n=$1; _l=$2; _s=/tmp/mstock-$3; _f=$4; _e=$5; shift 5
    {
        echo "== $_l"
        env MOCK_SH=$SH "$@" sh $W/tools-g70/mock-test.sh $Z $_f ikfl_us $_s > $O/$_n.raw 2>&1
        grep -E "INSTALL|UNINSTALL|REFUSED" $O/$_n.raw | head -2
        _x=$(sed -n 's/^sandbox (logs[^)]*): //p' $O/$_n.raw)
        _set=$(sed -n 's/^firmware set \([^ ]*\) .*/\1/p' $_x/pre.log 2>/dev/null | head -1)
        if [ "$_e" = refused ]; then
            grep -q "no firmware set for this unit" $_x/pre.log || echo "FAIL: not refused for a missing set"
        else
            [ "$_set" = "$_e" ] || echo "FAIL: picked set '$_set', expected $_e"
            grep -q "commented the wireless" $_x/post.log || echo "FAIL: featurexml.cfg left as it was"
        fi
        grep -h "^FAIL" $_x/pre.log $_x/post.log 2>/dev/null | head -3
    } > $O/$_n.txt 2>&1
}
u() {  # $1 n, $2 label, $3 old package zip, $4 stock name, $5 firmware
    {
        echo "== upgrade: $2"
        env MOCK_SH=$SH sh $W/tools-g70/mock-upgrade.sh $3 $Z $5 ikfl_us /tmp/mstock-$4 2>&1 | grep -E "INSTALL|UPGRADE|UNINSTALL|FAIL" | head -4
    } > $O/$1.txt 2>&1
}
t 01 "251120: fresh install" 251120 IKFL.USA.0000.V014.011.251120 251120 &
t 02 "250818: fresh install" 250818 IKFL.USA.0000.V014.010.250818 250818 &
t 03 "260507: fresh install" 260507 IKFL.USA.0000.V015.012.260507 260507 &
t 04 "260507: Android down" 260507 IKFL.USA.0000.V015.012.260507 260507 MOCK_ANDROID_DOWN=1 &
t 05 "260507: NEMESIS 1.15" 260507 IKFL.USA.0000.V015.012.260507 260507 MOCK_NEMESIS=1.15 &
t 06 "IKPE name on 250818 files" 250818 IKPE.USA.0000.V014.010.250818 250818 &
t 07 "unknown mix of files (must be refused)" other IKFL.USA.0000.V015.012.260507 refused &
u 08 "v1.1 on 251120" $W/release-u22/dist/packages/g70.carplay.bt.zip 251120 IKFL.USA.0000.V014.011.251120 &
u 09 "250818 bridge v2 (cameras)" $W/release-g70-250818/dist/packages/g70.carplay.bt.zip 250818 IKFL.USA.0000.V014.010.250818 &
u 10 "260507 bridge (cameras)" $W/release-g70-260507/dist/packages/g70.carplay.bt.zip 260507 IKFL.USA.0000.V015.012.260507 &
u 11 "v1.2 on 251120" $W/prev/v12-g70.carplay.bt.zip 251120 IKFL.USA.0000.V014.011.251120 &
u 12 "v1.2 on 250818" $W/prev/v12-g70.carplay.bt.zip 250818 IKFL.USA.0000.V014.010.250818 &
u 13 "v1.2 on 260507" $W/prev/v12-g70.carplay.bt.zip 260507 IKFL.USA.0000.V015.012.260507 &
u 14 "260507 update 23 test build" $W/prev/u23test1-g70.carplay.bt.zip 260507 IKFL.USA.0000.V015.012.260507 &
u 15 "v1.3 on 251120" $W/prev/v13-g70.carplay.bt.zip 251120 IKFL.USA.0000.V014.011.251120 &
u 16 "v1.3 on 250818" $W/prev/v13-g70.carplay.bt.zip 250818 IKFL.USA.0000.V014.010.250818 &
u 17 "v1.3 on 260507" $W/prev/v13-g70.carplay.bt.zip 260507 IKFL.USA.0000.V015.012.260507 &
u 18 "update 24 on 251120" $W/prev/u24-g70.carplay.bt.zip 251120 IKFL.USA.0000.V014.011.251120 &
u 19 "update 24 on 250818" $W/prev/u24-g70.carplay.bt.zip 250818 IKFL.USA.0000.V014.010.250818 &
u 20 "update 24 on 260507" $W/prev/u24-g70.carplay.bt.zip 260507 IKFL.USA.0000.V015.012.260507 &
wait
cat $O/[0-9]*.txt
