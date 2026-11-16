#!/bin/sh
# G70 bridge for IKFL.USA.0000.V016.010.260903 (2026-11-15 port probe, ports/g70-260903, private).
# Rebases the newest G70 260507 trees (build/g70-260507-nocam-*: v1.3 + updates 24-26) from the 260507
# stock onto the 260903 stock, then the 260903 fixes found by classmatch / build_port / renames /
# fieldcheck, then the usual checks and the standalone package (release-g70-260903).
#   - Navi e/a (cluster sender) is d/a on 260903: merged there by merge_moved.py (e/a back to stock)
#   - DiPO renames: DipoService.S(DipoService)V -> R (both call B()), e/a.Q / e/m.Q -> L (e/b field)
#   - DiPO e/v (CarPlay maneuver) fields moved one letter (DK..DV -> DL..DW, same types): the names
#     LeafiaCpTurn / LeafiaCpGap look up by reflection become the 260903 ones
# usage: build_g70_260903.sh  (in the leafia container)
set -e
W=/work
cd $W
PORT=g70-260903
FW=IKFL.USA.0000.V016.010.260903
export MERGE_BASE=g70-260507 MERGE_OURS=g70-260507-nocam
python3 ports/merge.py $PORT
python3 ports/merge_moved.py $MERGE_BASE $MERGE_OURS $PORT navi14 HKMC_Navi_ExSL com/mnsoft/navi/e/a.smali com/mnsoft/navi/d/a.smali
D=build/$PORT-dipo18/com/daudio/app/dipo
sed -i 's#Lcom/daudio/app/dipo/service/DipoService;->S(Lcom/daudio/app/dipo/service/DipoService;)V#Lcom/daudio/app/dipo/service/DipoService;->R(Lcom/daudio/app/dipo/service/DipoService;)V#' $D/service/LeafiaDipoStart.smali
sed -i 's#Lcom/daudio/app/dipo/e/a;->Q:Lcom/daudio/app/dipo/e/b;#Lcom/daudio/app/dipo/e/a;->L:Lcom/daudio/app/dipo/e/b;#g' $D/e/g.smali
sed -i 's#Lcom/daudio/app/dipo/e/m;->Q:Lcom/daudio/app/dipo/e/b;#Lcom/daudio/app/dipo/e/m;->L:Lcom/daudio/app/dipo/e/b;#g' $D/e/m.smali
for f in $D/LeafiaCpTurn.smali $D/LeafiaCpGap.smali; do
    sed -i 's#"Dx|DM"#"Dx|DN"#; s#"DD|DS"#"DD|DT"#; s#"DF|DU"#"DF|DV"#; s#"DE|DT"#"DE|DU"#' $f
done
# every fix must have landed (and nothing left of the 260507 names)
grep -q 'DipoService;->R(Lcom/daudio/app/dipo/service/DipoService;)V' $D/service/LeafiaDipoStart.smali
! grep -q 'e/[am];->Q:Lcom/daudio/app/dipo/e/b;' $D/e/g.smali $D/e/m.smali
[ "$(grep -c '"Dx|DN"\|"DD|DT"\|"DF|DV"\|"DE|DU"' $D/LeafiaCpTurn.smali $D/LeafiaCpGap.smali | awk -F: '{s+=$2} END {print s}')" = 7 ]
! grep -q '"Dx|DM"\|"DD|DS"\|"DF|DU"\|"DE|DT"' $D/LeafiaCpTurn.smali $D/LeafiaCpGap.smali
[ "$(grep -c 'LeafiaTrapBar;->send' build/$PORT-navi14/com/mnsoft/navi/d/a.smali)" = 2 ]
[ "$(grep -c 'LeafiaTbtMute;->dropClusterData' build/$PORT-navi14/com/mnsoft/navi/d/a.smali)" = 1 ]
echo "== renamed / moved members"
python3 ports/renames.py $PORT | grep -v "DipoService;->S(Lcom/daudio/app/dipo/service/DipoService;)V" | tail -4
python3 ports/fieldshift.py $PORT | tail -1
sh ports/build_port.sh $PORT > /tmp/$PORT-bp.txt 2>&1
echo "checks: $(grep -c '^0 problems' /tmp/$PORT-bp.txt)/8 clean"
grep -v '0 problems\|^\s*$' /tmp/$PORT-bp.txt | head -12
[ "$(grep -c '^0 problems' /tmp/$PORT-bp.txt)" = 8 ]
sh ports/build_full_port.sh $PORT $FW > /tmp/$PORT-fp.txt 2>&1
tail -3 /tmp/$PORT-fp.txt
