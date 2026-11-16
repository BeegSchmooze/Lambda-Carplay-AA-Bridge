#!/bin/sh
# Update 27a (projection hotspot kept on): JVM tests, compiles LeafiaHotspot for DiPO, backs up
# DipoService.smali of every bridge tree (once, build/u27-hotspot-backup/), copies the classes in,
# runs hooks27_hotspot.py on the three G70 trees, then the reference checks.
# After this: ports/build_stinger_260507.sh (Stinger wireless) / the G70 multi build.
# usage: build_hotspot.sh  (in the leafia container)
set -e
W=/work
H=$W/aa-port/hotspot
SDK=$W/sdk/android-4.4.2/android.jar
T=/tmp/hotspot
rm -rf $T && mkdir -p $T/cls $T/dex
echo "== off-car tests"
TAIL=8 sh $W/aa-port/cpreg/run_tests.sh > $T/tests.txt 2>&1 || { cat $T/tests.txt; exit 1; }
grep -E '^==|PASS|FAILED' $T/tests.txt
grep -q 'FAIL' $T/tests.txt && { echo "JVM tests failed"; exit 1; }
javac -nowarn -source 7 -target 7 -encoding utf8 -cp $SDK -d $T/cls $H/src/com/daudio/app/dipo/LeafiaHotspot.java $H/src/com/leafia/wifi/LeafiaApName.java $H/test/LeafiaHotspotTest.java
echo "== LeafiaHotspotTest"
java -cp $T/cls:$SDK LeafiaHotspotTest | tee $T/hs.txt | tail -1
grep -q FAIL $T/hs.txt && { echo "LeafiaHotspot test failed"; exit 1; }
java -cp $W/sdk/android-11/lib/d8.jar com.android.tools.r8.D8 --release --min-api 18 --lib $SDK \
    --output $T/dex $T/cls/com/daudio/app/dipo/LeafiaHotspot*.class
java -jar $W/bin/baksmali.jar d -o $T/smali $T/dex/classes.dex
D=com/daudio/app/dipo
BK=$W/build/u27-hotspot-backup
for t in g70-251120-nocam g70-250818-nocam g70-260507-nocam; do
    if [ ! -d $BK/$t ]; then
        mkdir -p $BK/$t
        cp $W/build/$t-dipo18/$D/service/DipoService.smali $BK/$t/
    fi
    cp $T/smali/$D/LeafiaHotspot*.smali $W/build/$t-dipo18/$D/
    python3 $H/hooks27_hotspot.py $W/build/$t-dipo18
    echo "== $t refs"
    python3 $W/tools-g70/check_refs.py $W/build/$t-dipo18 $W/fwsmali $W/build/$t-dipo18/$D/LeafiaHotspot*.smali $W/build/$t-dipo18/$D/service/DipoService.smali | tail -1
done
# update 27c: Android Auto (GPM) and CarPlay (Iap2ServerApp) send the network the hotspot broadcasts
mkdir -p $T/dex2
java -cp $W/sdk/android-11/lib/d8.jar com.android.tools.r8.D8 --release --min-api 18 --lib $SDK     --output $T/dex2 $T/cls/com/leafia/wifi/LeafiaApName.class
java -jar $W/bin/baksmali.jar d -o $T/smali2 $T/dex2/classes.dex
for t in g70-251120-nocam g70-250818-nocam g70-260507-nocam; do
    for a in gpm15:com/google/android/projection/protocol/WirelessExplorer.smali iap2:com/tcc/iap2server/Iap2Service.smali; do
        tr=${a%%:*}; f=${a#*:}; TT=$W/build/$t-$tr
        if [ ! -f $BK/$t/$tr-$(basename $f) ]; then mkdir -p $BK/$t; cp $TT/$f $BK/$t/$tr-$(basename $f); fi
        mkdir -p $TT/com/leafia/wifi
        cp $T/smali2/com/leafia/wifi/LeafiaApName.smali $TT/com/leafia/wifi/
        python3 $H/hooks27c_apname.py $TT
        echo "== $t $tr refs"
        python3 $W/tools-g70/check_refs.py $TT $W/fwsmali $TT/com/leafia/wifi/LeafiaApName.smali $TT/$f | tail -1
    done
done
