#!/bin/sh
# Runs the generated compatibility check (repo/tools/compat/NEMESIS.sh) against the mock stock
# trees of ports/mock_multi.sh (/tmp/mstock-<name>): /system paths pointed at the tree, md5 and
# getprop stubbed. Prints each report's set line and result.
# usage: mock_compat.sh  (after mock_multi.sh, in the leafia container)
W=/work
SH=$(command -v mksh || echo /bin/sh)
X=/tmp/mockcompat; rm -rf $X; mkdir -p $X/bin
printf '#!/bin/sh\nmd5sum "$1" | cut -d" " -f1\n' > $X/bin/md5
printf '#!/bin/sh\necho "$MOCK_PRODUCT"\n' > $X/bin/getprop
chmod 755 $X/bin/*
for c in 251120:IKFL.USA.0000.V014.011.251120 250818:IKFL.USA.0000.V014.010.250818 \
         260507:IKFL.USA.0000.V015.012.260507 260903:IKFL.USA.0000.V016.010.260903 other:IKFL.USA.0000.V015.012.260507; do
    n=${c%%:*}; T=/tmp/mstock-$n
    D=$X/$n; mkdir -p $D/usb
    sed -e "s#/system/#$T/#g" -e "s#/data/nemesis/#$D/nemesis/#g" -e 's#^export PATH=.*#:#' \
        $W/repo/tools/compat/NEMESIS.sh > $D/check.sh
    (cd $D/usb && env PATH=$X/bin:$PATH MOCK_PRODUCT=${c#*:} $SH ../check.sh)
    echo "== $n"
    grep -E "^firmware set|^no firmware set|^RESULT|DIFFERENT" $D/usb/G70COMPAT-1/report.txt
done
