#!/bin/sh
# Turn-by-turn-only package (g70.tbt) for a port: the port's stock smali + the turn-by-turn files
# of our merged trees (ports/merge.py; same file selection as aa-port/build_tbt.sh), the car
# navigation merged from navi13 (turn mute, no camera display), the Android Auto library from
# aa-tbt/build_lib_port.py. Checks every changed class (check_refs / check_regs against the port's
# framework), then makes release-<port>-tbt/dist/packages/g70.tbt.zip.
# usage: build_tbt_port.sh <port> <firmware name>
set -e
W=/work
PORT=$1; FW=$2
P=$W/ports/$PORT
LP=$W/HMG-Leafia-Plus/tools/lpatch/lpatch-host
BCP=$(ls $P/framework/*.odex | tr '\n' ':')
cd $W

mk() {  # $1 app, $2 name, $3 merged tree, rest: files (relative to the tree root)
    _a=$1; _n=$2; _f=$W/build/$PORT-$3; shift 3
    _t=$W/build/$PORT-tbt-$_n
    rm -rf $_t; cp -r $P/smali/$_a $_t
    for _p in "$@"; do
        mkdir -p "$(dirname "$_t/$_p")"; cp "$_f/$_p" "$_t/$_p"
    done
    java -jar bin/smali.jar a --api 18 -o $_t.dex $_t
    _files=$(cd $_t && find . -name '*.smali' | while read f; do
        s=$P/smali/$_a/$f; if [ ! -f "$s" ] || ! cmp -s "$_t/$f" "$s"; then echo "$_t/${f#./}"; fi; done)
    echo "== $_a: $(echo "$_files" | grep -c smali) classes changed/added, dex $(md5sum < $_t.dex | cut -c1-8)"
    python3 tools-g70/check_refs.py $_t $P/fwsmali $_files
    _cl=$(for f in $_files; do sed -n 's/^\.class.* \(L.*;\)$/\1/p' "$f" | head -1; done | tr '\n' ',' | sed 's/,$//')
    rm -rf /tmp/regs-tbt-$_n
    java -jar bin/baksmali.jar d -r ALL,FULLMERGE -b "$BCP" -o /tmp/regs-tbt-$_n --classes "$_cl" $_t.dex
    python3 tools-g70/check_regs.py $(find /tmp/regs-tbt-$_n -name '*.smali')
}

D=com/daudio/app/dipo
mk HKMC_DiPO dipo dipo18 $D/i/e.smali $D/e/u.smali $D/LeafiaCpTurn.smali $D/LeafiaTbtMark.smali $D/LeafiaCpLane.smali $D/LeafiaBar.smali
G=com/google/android/projection
mk HKMC_GPM gpm gpm15 \
    $(cd build/$PORT-gpm15 && ls $G/leafia/*.smali | grep -v LeafiaCam) \
    $G/protocol/NavigationStatus.smali $G/sink/b/i.smali \
    $G/sink/navigation/GpmNaviTBTManager.smali $G/sink/navigation/LeafiaTbtMark.smali \
    $G/service/GalConnectionSession.smali "$G/service/GalConnectionSession\$6.smali"
mk Iap2ServerApp iap2 iap2 com/tcc/iap2server/Iap2InitInformationMsg.smali
N=com/mnsoft/navi
mk HKMC_Navi_ExSL navi navi13 $N/e/a.smali $N/message/a.smali $N/LeafiaTbtMute.smali $N/LeafiaNavLog.smali

# the Android Auto library
python3 aa-tbt/build_lib_port.py $P/lib/libautoreceiver_infobank.so \
    $(md5sum < $P/lib/libautoreceiver_infobank.so | cut -d' ' -f1) build/$PORT-libautoreceiver_infobank.so $PORT

R=$W/release-$PORT-tbt
rm -rf $R && mkdir -p $R/pkg/files $R/pkg/tools build/out
cp -r g70-tbt-pkg/. $R/pkg/
cp release-u20/pkg/tools/lpatch $R/pkg/tools/
C=$R/pkg/scripts/common.sh
sum() { md5sum < "$1" | cut -d' ' -f1; }
for m in HKMC_DiPO:dipo HKMC_GPM:gpm Iap2ServerApp:iap2 HKMC_Navi_ExSL:navi; do
    a=${m%%:*}; n=${m#*:}
    python3 HMG-Leafia-Plus/tools/mkdelta.py $P/app/$a.odex build/$PORT-tbt-$n.dex $R/pkg/files/$a.lpd
    rm -f build/out/$a-$PORT-tbt.apk
    $LP zipadd $P/app/$a.apk build/$PORT-tbt-$n.dex build/out/$a-$PORT-tbt.apk
    sed -i "s/^SUM_STOCK_${a}_apk=.*/SUM_STOCK_${a}_apk=$(sum $P/app/$a.apk)/; s/^SUM_STOCK_${a}_odex=.*/SUM_STOCK_${a}_odex=$(sum $P/app/$a.odex)/" $C
    sed -i "s/@NEW_$a@/$(sum build/out/$a-$PORT-tbt.apk)/" $C
done
python3 HMG-Leafia-Plus/tools/mkdelta.py $P/lib/libautoreceiver_infobank.so build/$PORT-libautoreceiver_infobank.so \
    $R/pkg/files/libautoreceiver_infobank.tbt.lpd
sed -i "s/^SUM_STOCK_AALIB=.*/SUM_STOCK_AALIB=$(sum $P/lib/libautoreceiver_infobank.so)/; s/^SUM_NEW_AALIB=.*/SUM_NEW_AALIB=$(sum build/$PORT-libautoreceiver_infobank.so)/" $C
OLDFW=$(sed -n 's/^PRODUCT=//p' $C)
sed -i "s/^PRODUCT=.*/PRODUCT=$FW/; s/built on IKFL.USA 251120/built on $FW (port)/" $C
grep -n "^PRODUCT\|^SUM_STOCK\|^SUM_NEW" $C
! grep -n "@NEW_" $C
mkdir -p $R/dist/packages
(cd $R/pkg && zip -qrX ../dist/packages/g70.tbt.zip .)
md5sum $R/dist/packages/g70.tbt.zip
