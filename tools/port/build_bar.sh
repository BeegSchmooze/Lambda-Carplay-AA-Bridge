#!/bin/sh
# Update 25 (HUD approach bar): compiles LeafiaBar for GPM and DiPO, backs up the two patched
# classes of every tree (once, to build/u24-bar-backup/), copies LeafiaBar.smali in and runs
# hooks25_bar.py on the three G70 v1.3/u24 trees and the two Stinger trees, then the reference
# checks. After this: ports/build_u23_par.sh (G70 multi) and the Stinger tbt builds.
# usage: build_bar.sh  (in the leafia container)
set -e
W=/work
B=$W/aa-port/bar
SDK=$W/sdk/android-4.4.2/android.jar
T=/tmp/bar
rm -rf $T && mkdir -p $T/src/g $T/src/d $T/cls $T/dex
sed 's/@PKG@/com.google.android.projection.leafia/' $B/LeafiaBar.java.in > $T/src/g/LeafiaBar.java
sed 's/@PKG@/com.daudio.app.dipo/' $B/LeafiaBar.java.in > $T/src/d/LeafiaBar.java
javac -nowarn -source 7 -target 7 -encoding utf8 -cp $SDK -d $T/cls $T/src/g/LeafiaBar.java $T/src/d/LeafiaBar.java
echo "== off-car check"
java -cp $T/cls com.google.android.projection.leafia.LeafiaBar
java -cp $W/sdk/android-11/lib/d8.jar com.android.tools.r8.D8 --release --min-api 18 --lib $SDK \
    --output $T/dex $(find $T/cls -name '*.class')
java -jar $W/bin/baksmali.jar d -o $T/smali $T/dex/classes.dex
G=com/google/android/projection/leafia
D=com/daudio/app/dipo
BK=$W/build/u24-bar-backup
for t in g70-251120-nocam g70-250818-nocam g70-260507-nocam stinger-251120 stinger-260507; do
    if [ ! -d $BK/$t ]; then
        mkdir -p $BK/$t
        cp $W/build/$t-gpm15/$G/LeafiaAaTurns.smali $BK/$t/
        cp $W/build/$t-dipo18/$D/LeafiaCpTurn.smali $BK/$t/
    fi
    cp $T/smali/$G/LeafiaBar.smali $W/build/$t-gpm15/$G/
    cp $T/smali/$D/LeafiaBar.smali $W/build/$t-dipo18/$D/
    python3 $B/hooks25_bar.py gpm $W/build/$t-gpm15
    python3 $B/hooks25_bar.py dipo $W/build/$t-dipo18
    echo "== $t refs"
    python3 $W/tools-g70/check_refs.py $W/build/$t-gpm15 $W/fwsmali $W/build/$t-gpm15/$G/LeafiaBar.smali $W/build/$t-gpm15/$G/LeafiaAaTurns.smali | tail -1
    python3 $W/tools-g70/check_refs.py $W/build/$t-dipo18 $W/fwsmali $W/build/$t-dipo18/$D/LeafiaBar.smali $W/build/$t-dipo18/$D/LeafiaCpTurn.smali | tail -1
done
