#!/bin/sh
# Stinger turn-by-turn v1.2: the trap-frame HUD approach bar (update 26 trapbar, as in the G70 v1.5 and
# Stinger wireless) added to the turn-by-turn navi13 trees, plus everything of the v1.2 test build
# (angle-less CarPlay turns, LeafiaBar hidden until ~0.3 mi). v1.0, v1.1 and the v1.2 test marked previous.
# usage: build_stinger_tbt_v12.sh  (in the leafia container)
set -e
W=/work
cd $W
N=com/mnsoft/navi
BK=$W/build/tbt12-trapbar-backup
# the v1.2 test build, once, so v1.2 can replace it
if [ ! -f prev/stinger-tbt-v12t-stinger.tbt.zip ]; then
    cp release-stinger-tbt-v12/dist/packages/stinger.tbt.zip prev/stinger-tbt-v12t-stinger.tbt.zip
    rm -rf prev/stinger-tbt-v12t && cp -r release-stinger-tbt-v12/pkg prev/stinger-tbt-v12t
fi
for port in stinger-251120 stinger-260507; do
    d=build/$port-navi13
    if [ ! -d $BK/$port ]; then
        mkdir -p $BK/$port/e $BK/$port/message
        cp $d/$N/e/a.smali $BK/$port/e/; cp $d/$N/message/a.smali $BK/$port/message/
    fi
    cp build/$port-navi14/$N/LeafiaTrapBar*.smali $d/$N/
    echo "== $port navi13"
    python3 aa-port/bar/hooks26_trapbar.py $d
    python3 tools-g70/check_refs.py $d $W/fwsmali $d/$N/LeafiaTrapBar.smali $d/$N/e/a.smali $d/$N/message/a.smali | tail -1
done
sh ports/build_tbt_port.sh stinger-251120 CKPE23.USA.0000.V014.011.251120 > /tmp/t12-st-251120.txt 2>&1
sh ports/build_tbt_port.sh stinger-260507 CKPE23.USA.0000.V015.012.260507 > /tmp/t12-st-260507.txt 2>&1
for fw in 251120 260507; do
    echo "== $fw: $(grep -c '^0 problems' /tmp/t12-st-$fw.txt) clean checks"
    grep -iE 'problem|error|FAIL' /tmp/t12-st-$fw.txt | grep -v '^0 problems' | head -5
    grep '^== HKMC_Navi' /tmp/t12-st-$fw.txt
    python3 ports/set_tbt_prev.py release-stinger-$fw-tbt prev/stinger-tbt-v10/pkg/firmware/$fw/sums.sh \
        prev/stinger-tbt-v11/firmware/$fw/sums.sh prev/stinger-tbt-v12t/firmware/$fw/sums.sh
done
grep -q LeafiaTrapBar /tmp/t12-st-251120.txt /tmp/t12-st-260507.txt || ls build/stinger-251120-tbt-navi/$N/LeafiaTrapBar.smali build/stinger-260507-tbt-navi/$N/LeafiaTrapBar.smali
rm -rf release-stinger-tbt-v12
python3 ports/build_tbt_multi.py release-stinger-tbt-v12 "Kia Stinger turn-by-turn" 251120=release-stinger-251120-tbt 260507=release-stinger-260507-tbt
md5sum release-stinger-tbt-v12/dist/packages/stinger.tbt.zip
TBT_MULTI=$W/release-stinger-tbt-v12 sh ports/mock_tbt_multi.sh
