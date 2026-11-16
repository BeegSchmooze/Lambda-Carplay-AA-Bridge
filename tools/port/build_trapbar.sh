#!/bin/sh
# Update 26 (HUD approach bar from the trap frame): compiles LeafiaTrapBar for HKMC_Navi_ExSL, runs
# its off-car check, backs up the two patched Navi classes of every tree (once, to
# build/u26-trapbar-backup/), copies LeafiaTrapBar.smali in and runs hooks26_trapbar.py, then the
# reference checks. Run aa-port/bar/build_bar.sh too (LeafiaBar publishes sys.leafia.phonebar).
# usage: build_trapbar.sh  (in the leafia container)
set -e
W=/work
B=$W/aa-port/bar
SDK=$W/sdk/android-4.4.2/android.jar
T=/tmp/trapbar
rm -rf $T && mkdir -p $T/src $T/cls $T/stubcls $T/dex
javac -nowarn -source 7 -target 7 -encoding utf8 -cp $SDK -d $T/stubcls $W/aa-port/stubs/com/hkmc/cluster/NavigationCluster.java
javac -nowarn -source 7 -target 7 -encoding utf8 -cp $SDK:$T/stubcls -d $T/cls $B/LeafiaTrapBar.java
echo "== off-car check"
java -cp $T/cls:$T/stubcls:$SDK com.mnsoft.navi.LeafiaTrapBar
java -cp $W/sdk/android-11/lib/d8.jar com.android.tools.r8.D8 --release --min-api 18 --lib $SDK \
    --classpath $T/stubcls --output $T/dex $(find $T/cls -name '*.class')
java -jar $W/bin/baksmali.jar d -o $T/smali $T/dex/classes.dex
N=com/mnsoft/navi
BK=$W/build/u26-trapbar-backup
for t in g70-251120-nocam g70-250818-nocam g70-260507-nocam stinger-251120 stinger-260507; do
    d=$W/build/$t-navi14
    [ -d $d ] || { echo "== $t: no navi14 tree, skipped"; continue; }
    if [ ! -d $BK/$t ]; then
        mkdir -p $BK/$t/e $BK/$t/message
        cp $d/$N/e/a.smali $BK/$t/e/
        cp $d/$N/message/a.smali $BK/$t/message/
    fi
    cp $T/smali/$N/LeafiaTrapBar*.smali $d/$N/
    echo "== $t"
    python3 $B/hooks26_trapbar.py $d
    python3 $W/tools-g70/check_refs.py $d $W/fwsmali $d/$N/LeafiaTrapBar.smali $d/$N/e/a.smali $d/$N/message/a.smali | tail -1
done
