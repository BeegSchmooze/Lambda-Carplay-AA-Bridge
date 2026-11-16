#!/bin/sh
# Update 26 (CarPlay turns stock DiPO drops): JVM tests, compiles LeafiaCpGap for DiPO, backs up
# e/u.smali of every tree (once, to build/u25-gap-backup/), copies LeafiaCpGap.smali in and runs
# hooks26_dipo.py on the three G70 trees and the two Stinger trees, then the reference checks.
# After this: ports/build_u23_par.sh (G70 multi) and the Stinger tbt builds.
# usage: build_gap.sh  (in the leafia container)
set -e
W=/work
G=$W/aa-port/gap
SDK=$W/sdk/android-4.4.2/android.jar
T=/tmp/gap
rm -rf $T && mkdir -p $T/cls $T/dex
echo "== off-car tests"
TAIL=12 sh $W/aa-port/cpreg/run_tests.sh | grep -E '^==|FAIL|PASS|passed|failed' || true
TAIL=12 sh $W/aa-port/cpreg/run_tests.sh | grep -q 'FAIL' && { echo "JVM tests failed"; exit 1; }
# compile against the bridge sources (LeafiaCpTurn etc.) and the stubs; ship only LeafiaCpGap
SRCS="$(find $W/aa-port/cpreg/src $W/aa-port/cpreg/stubs -name "*.java") $W/aa-port/stubs/com/hkmc/cluster/NavigationCluster.java"
javac -nowarn -source 7 -target 7 -encoding utf8 -cp $SDK -d $T/cls $SRCS
java -cp $W/sdk/android-11/lib/d8.jar com.android.tools.r8.D8 --release --min-api 18 --lib $SDK \
    --output $T/dex $T/cls/com/daudio/app/dipo/LeafiaCpGap.class
java -jar $W/bin/baksmali.jar d -o $T/smali $T/dex/classes.dex
D=com/daudio/app/dipo
BK=$W/build/u25-gap-backup
for t in g70-251120-nocam g70-250818-nocam g70-260507-nocam stinger-251120 stinger-260507; do
    if [ ! -d $BK/$t ]; then
        mkdir -p $BK/$t
        cp $W/build/$t-dipo18/$D/e/u.smali $BK/$t/
    fi
    cp $T/smali/$D/LeafiaCpGap.smali $W/build/$t-dipo18/$D/
    python3 $G/hooks26_dipo.py $W/build/$t-dipo18
    echo "== $t refs"
    python3 $W/tools-g70/check_refs.py $W/build/$t-dipo18 $W/fwsmali $W/build/$t-dipo18/$D/LeafiaCpGap.smali $W/build/$t-dipo18/$D/e/u.smali | tail -1
done
