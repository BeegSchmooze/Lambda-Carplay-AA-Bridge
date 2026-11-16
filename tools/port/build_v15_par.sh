#!/bin/sh
# v1.5 (adds 260903, kept as the build its owner tested), the parallel way: the three firmware checks at once, the three port packages at
# once, the multi-firmware package, then every mock case at once (ports/mock_multi_par.sh) and
# the compatibility check mock.
# usage: build_v15_par.sh  (in the leafia container)
W=/work
cd $W
for fw in 251120 250818 260507; do
    sh ports/build_port.sh g70-$fw-nocam > /tmp/v15-bp-$fw.txt 2>&1 &
done
wait
for fw in 251120 250818 260507; do
    echo "$fw checks: $(grep -c "^0 problems" /tmp/v15-bp-$fw.txt)/8 clean"
    grep -v '0 problems\|^==\|^\s*$' /tmp/v15-bp-$fw.txt | head -5
done
sh ports/build_full_port.sh g70-251120-nocam IKFL.USA.0000.V014.011.251120 > /tmp/v15-fp-251120.txt 2>&1 &
sh ports/build_full_port.sh g70-250818-nocam IKFL.USA.0000.V014.010.250818 > /tmp/v15-fp-250818.txt 2>&1 &
sh ports/build_full_port.sh g70-260507-nocam IKFL.USA.0000.V015.012.260507 > /tmp/v15-fp-260507.txt 2>&1 &
wait
for fw in 251120 250818 260507; do tail -1 /tmp/v15-fp-$fw.txt; done
sh ports/build_multi.sh > /tmp/v15-multi.txt 2>&1; tail -1 /tmp/v15-multi.txt
sh ports/mock_multi_par.sh 2>&1
python3 repo/tools/compat/mk_compat.py release-multi/pkg /tmp/v15-compat > /dev/null && cp /tmp/v15-compat/NEMESIS.sh repo/tools/compat/NEMESIS.sh
sh ports/mock_compat.sh 2>&1 | grep -E "^==|^RESULT"
