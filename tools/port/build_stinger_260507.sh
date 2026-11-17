#!/bin/sh
# Kia Stinger wireless CarPlay/AA bridge for CKPE23.USA.0000.V015.012.260507 (2023 Stinger with
# the Broadcom BCM4359 Wi-Fi card: same chip and Wi-Fi firmware as the G70, Wi-Fi probe
# 2026-11-10). Its DiPO, GPM and Iap2ServerApp code is identical to the G70's 260507 code and its
# Navi differs in 1 class we don't patch (b/i), so the trees are the current G70 260507 trees
# (build/g70-260507-nocam-*) with that class from the Stinger. Then the usual checks and the full
# standalone package (release-stinger-260507).
# usage: build_stinger_260507.sh  (in the leafia container)
set -e
W=/work
cd $W
PORT=stinger-260507
G=g70-260507-nocam
P=$W/ports/$PORT
for a in HKMC_DiPO HKMC_GPM Iap2ServerApp; do
    n=$(diff -r ports/$G/smali/$a $P/smali/$a | grep -c '^[<>]' || true)
    [ "$n" = 0 ] || { echo "$a differs from the G70 260507 ($n lines): needs a real merge"; exit 1; }
done
for t in dipo18 gpm15 iap2 navi14; do
    rm -rf build/$PORT-$t
    cp -r build/$G-$t build/$PORT-$t
done
DIFF=$(diff -rq ports/$G/smali/HKMC_Navi_ExSL $P/smali/HKMC_Navi_ExSL | sed -n 's#^Files .*/HKMC_Navi_ExSL/\(.*\) and .* differ$#\1#p')
ONLY=$(diff -rq ports/$G/smali/HKMC_Navi_ExSL $P/smali/HKMC_Navi_ExSL | grep -c '^Only in' || true)
[ "$ONLY" = 0 ] || { echo "Navi has classes only on one side: needs a real merge"; exit 1; }
echo "Navi classes from the Stinger: $(echo $DIFF)"
for f in $DIFF; do
    cmp -s ports/$G/smali/HKMC_Navi_ExSL/$f build/$PORT-navi14/$f || { echo "we patch $f: needs a real merge"; exit 1; }
    cp $P/smali/HKMC_Navi_ExSL/$f build/$PORT-navi14/$f
done
# the port's trees must differ from its stock exactly where the G70 260507 trees differ from theirs
for m in HKMC_DiPO:dipo18 HKMC_GPM:gpm15 HKMC_Navi_ExSL:navi14 Iap2ServerApp:iap2; do
    a=${m%%:*}; t=${m#*:}
    x=$(diff -r ports/$G/smali/$a build/$G-$t | md5sum | cut -c1-8)
    y=$(diff -r $P/smali/$a build/$PORT-$t | sed "s#$P/smali#ports/$G/smali#g; s#build/$PORT-#build/$G-#g" | md5sum | cut -c1-8)
    echo "$a: our changes $([ "$x" = "$y" ] && echo same as the G70 260507 || echo DIFFERENT $x $y)"
done
sh ports/build_port.sh $PORT > /tmp/stinger260507-bp.txt 2>&1
echo "checks: $(grep -c '^0 problems' /tmp/stinger260507-bp.txt)/8 clean"
grep -v '0 problems\|^\s*$' /tmp/stinger260507-bp.txt | head -12
sh ports/build_full_port.sh $PORT CKPE23.USA.0000.V015.012.260507 > /tmp/stinger260507-fp.txt 2>&1
tail -3 /tmp/stinger260507-fp.txt
# earlier test builds an install may replace (their SUM_NEW_* -> this build's SUM_PREV_*), rezip
R=$W/release-$PORT
python3 - $R/pkg/scripts/common.sh $W/prev/stinger260507-wl-t1/scripts/common.sh $W/prev/stinger260507-wl-t2/scripts/common.sh $W/prev/stinger260507-wl-t3/scripts/common.sh $W/prev/stinger260507-wl-t4/scripts/common.sh $W/prev/stinger260507-wl-t5/scripts/common.sh $W/prev/stinger260507-wl-t6b/scripts/common.sh $W/prev/stinger260507-wl-t7/scripts/common.sh $W/prev/stinger260507-wl-t8/scripts/common.sh $W/prev/stinger260507-wl-t9/scripts/common.sh $W/prev/stinger260507-wl-t10/scripts/common.sh <<'PY'
import re, sys
p, prevs = sys.argv[1], sys.argv[2:]
s = open(p).read()
new = {k: v.strip('"') for k, v in re.findall(r'^SUM_NEW_(\w+)=(.*)$', s, re.M)}
for f in prevs:
    for k, v in re.findall(r'^SUM_NEW_(\w+)=(.*)$', open(f).read(), re.M):
        v = v.strip('"')
        if not v or v == new.get(k): continue
        cur = re.search(r'^SUM_PREV_%s=(.*)$' % k, s, re.M).group(1).strip('"').split()
        if v not in cur: cur.append(v)
        s = re.sub(r'^SUM_PREV_%s=.*$' % k, 'SUM_PREV_%s="%s"' % (k, ' '.join(cur)), s, flags=re.M)
open(p, 'w').write(s)
PY
# test 7: GPM/iap2server can't read hostapd.conf (EACCES), so the package tells LeafiaApName that this
# unit's hotspot broadcasts the plain SSID (persist.leafia.ap.plain=t; restored on uninstall like the others)
sed -i 's/^PROPS="persist.sys.iap2.wifi persist.iap2.iden.wireless"$/PROPS="persist.sys.iap2.wifi persist.iap2.iden.wireless persist.leafia.ap.plain"/' $R/pkg/scripts/common.sh
grep -q '^PROPS=.*persist.leafia.ap.plain' $R/pkg/scripts/common.sh || { echo 'PROPS hint not added'; exit 1; }
# test 8: the Apple device IE. A root NEMESIS service (svc/appleie.sh) adds apple_device_ie to hostapd.conf
# and restarts the AP whenever it comes up without it (the G70's netd writes that line; the Stinger's NMS never
# asks it to). Service entries need the 1.1 header (as in the third-party service packages).
mkdir -p $R/pkg/svc
cp $W/ports/$PORT-svc/appleie.sh $R/pkg/svc/appleie.sh
chmod 755 $R/pkg/svc/appleie.sh
# test 11: the driver-command tool appleie.sh uses when hostapd has no apple_device_ie option
sh $W/ports/$PORT-svc/native/build.sh
cp $W/ports/$PORT-svc/leafiaie $R/pkg/svc/leafiaie
chmod 755 $R/pkg/svc/leafiaie
sh $W/ports/$PORT-svc/test/run.sh | tail -1 | grep -q "ALL PASS" || { echo "appleie tests failed"; exit 1; }
python3 $W/ports/$PORT-svc/nemesis_data.py $R/pkg/NEMESIS.data
cat $R/pkg/NEMESIS.data
grep '^SUM_PREV_' $R/pkg/scripts/common.sh | cut -c1-60
(cd $R/pkg && rm -f ../dist/packages/g70.carplay.bt.zip && zip -qrX ../dist/packages/g70.carplay.bt.zip .)
md5sum $R/dist/packages/g70.carplay.bt.zip
