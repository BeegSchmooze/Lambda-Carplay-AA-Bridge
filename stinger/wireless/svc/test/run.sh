#!/bin/sh
# off-car test of appleie.sh: fake ps / ndc / getprop / log / sleep around a fake hostapd.conf.
# The fake netd behaves like the real one: it remembers the hostapd it started and refuses startap
# until stopap, even when that hostapd died (test 8 left the Stinger's hotspot off exactly so).
# usage: run.sh  (in the leafia container)
D=$(cd "$(dirname "$0")" && pwd)
SVC=$D/../appleie.sh
fails=0
mk() {
    S=$(mktemp -d); mkdir -p $S/bin $S/dir
    for c in grep rm mkdir cat date wc mv chmod; do ln -s $(command -v $c) $S/bin/$c; done
    # fake leafiaie: records each command; refuses when $S/ierefuse exists (like a driver without add_ie)
    mkdir -p $S/pkg/svc
    cat > $S/pkg/svc/leafiaie <<P
#!/bin/sh
PATH=/usr/bin:/bin:\$PATH
echo "\$*" >> $S/ie.log
echo "cmd: \$2 \$3 \$4 \$5"
if [ -f $S/ierefuse ]; then echo "ret: -95"; exit 1; fi
echo "ret: 0"
P
    chmod 755 $S/pkg/svc/leafiaie; : > $S/ie.log
    printf 'interface=wlan0\nssid=Kia_Hotspot_x\nchannel=149\nwpa=2\n' > $S/conf
    printf 'ELF...ssid\0apple_device_ie\0wpa_psk\0' > $S/hostapd
    echo 100 > $S/pid; echo 100 > $S/netd; echo 0 > $S/sleeps; : > $S/ndc.log
    cat > $S/bin/ps <<P
#!/bin/sh
PATH=/usr/bin:/bin:\$PATH
echo "USER PID PPID VSIZE RSS WCHAN PC NAME"
echo "root 1 0 100 10 c0 b0 S /init"
[ -s $S/pid ] && echo "wifi \$(cat $S/pid) 144 2636 708 c012619c b6eba9b4 S /system/bin/hostapd"
[ -s $S/zombie ] && echo "wifi \$(cat $S/zombie) 144 0 0 c002ee40 00000000 Z hostapd"
true
P
    cat > $S/bin/ndc <<P
#!/bin/sh
PATH=/usr/bin:/bin:\$PATH
echo "\$*" >> $S/ndc.log
case "\$2" in
stopap) : > $S/pid; : > $S/netd; : > $S/zombie; echo "200 0 Softap service stopped" ;;
startap)
    if [ -s $S/netd ]; then echo "400 0 Softap already started"; exit 0; fi
    n=\$((\$(wc -l < $S/ndc.log) + 200)); echo \$n > $S/netd
    if [ -f $S/reject ] && grep -q '^apple_device_ie=' $S/conf; then echo \$n > $S/zombie
    elif [ -f $S/alwaysfail ]; then echo \$n > $S/zombie
    else echo \$n > $S/pid; fi
    echo "200 0 Softap service started" ;;
esac
P
    cat > $S/bin/getprop <<P
#!/bin/sh
PATH=/usr/bin:/bin:\$PATH
case "\$1" in sys.boot_completed) echo 1 ;; persist.leafia.ap.plain) cat $S/plain 2>/dev/null || echo t ;; esac
P
    printf '#!/bin/sh\ntrue\n' > $S/bin/log
    cat > $S/bin/sleep <<P
#!/bin/sh
PATH=/usr/bin:/bin:\$PATH
n=\$((\$(cat $S/sleeps) + 1)); echo \$n > $S/sleeps
[ -x $S/hook ] && $S/hook \$n
[ \$n -ge \${MAXS:-20} ] && kill -TERM \$PPID
true
P
    chmod 755 $S/bin/*
}
go() {
    LEAFIA_TEST_TOOL=${NOTOOL:-$S/pkg/svc/leafiaie} LEAFIA_TEST_PATH=$S/bin LEAFIA_TEST_CONF=$S/conf LEAFIA_TEST_HOSTAPD=$S/hostapd LEAFIA_TEST_DIR=$S/dir \
        TMPDIR=$S sh ${SVCX:-$SVC} > $S/out 2>&1
}
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; cat $S/out; cat $S/ndc.log; fails=$((fails + 1)); fi; }

mk; go
check "supported: line added once" '[ $(grep -c "^apple_device_ie=0000020021$" $S/conf) = 1 ]'
check "supported: one stop + one start" '[ "$(cat $S/ndc.log | tr "\n" ,)" = "softap stopap,softap startap," ]'
check "supported: hostapd running, no bad flag" '[ -s $S/pid ] && [ ! -f $S/dir/appleie.bad2 ]'
check "conf keeps its other lines" 'grep -q "^ssid=Kia_Hotspot_x$" $S/conf && grep -q "^wpa=2$" $S/conf'
check "log file written" 'grep -q "back up with the Apple IE" $S/dir/appleie.log'

mk; touch $S/reject; go
check "rejected: line taken out again" '! grep -q apple_device_ie $S/conf'
check "rejected: hotspot RUNNING again (netd stopped first)" '[ -s $S/pid ]'
check "rejected: bad flag, two stop+starts" '[ -f $S/dir/appleie.bad2 ] && [ $(grep -c stopap $S/ndc.log) = 2 ]'
check "rejected: logged" 'grep -q "start with apple_device_ie" $S/dir/appleie.log && grep -q "back up without" $S/dir/appleie.log'

mk; touch $S/alwaysfail; go
check "hostapd won't start at all: tries a third restart, says so" '[ $(grep -c stopap $S/ndc.log) = 3 ] && grep -q "turn the car off and on" $S/dir/appleie.log'

mk; printf 'ELF...ssid\0wpa_psk\0' > $S/hostapd; go
check "hostapd without the option: hotspot never touched" '[ ! -s $S/ndc.log ] && ! grep -q apple $S/conf && [ "$(cat $S/pid)" = 100 ]'
check "hostapd without the option: logged why" 'grep -q "no apple_device_ie option" $S/dir/appleie.log'
# test 11: the driver path
check "driver: the three G70 commands, once" '[ "$(cat $S/ie.log | tr "\n" ,)" = "wlan0 add_ie 0 00A040 0000020021,wlan0 add_ie 1 00A040 0000020021,wlan0 add_ie 2 00A040 0000020021," ]'
check "driver: tool copied to the backup dir and run from there" '[ -x $S/dir/leafiaie ] && grep -q "driver ($S/dir/leafiaie" $S/dir/appleie.log'
check "driver: logged accepted" 'grep -q "Apple IE given to the driver (hostapd 100)" $S/dir/appleie.log && grep -q "add_ie 0: exit 0, cmd: add_ie 0 00A040 0000020021 ret: 0" $S/dir/appleie.log'

mk; printf 'ELF...ssid\0wpa_psk\0' > $S/hostapd; sed -i s/interface=wlan0/interface=ap0/ $S/conf; go
check "driver: interface taken from hostapd.conf" '[ $(grep -c "^ap0 add_ie" $S/ie.log) = 3 ]'

mk; printf 'ELF...ssid\0wpa_psk\0' > $S/hostapd; printf '#!/bin/sh\n[ "$1" = 9 ] && echo 777 > %s/pid\ntrue\n' $S > $S/hook; chmod 755 $S/hook; MAXS=30 go
check "driver: hostapd restarted later: given again, hotspot untouched" '[ $(grep -c "add_ie 0" $S/ie.log) = 2 ] && grep -q "driver (hostapd 777)" $S/dir/appleie.log && [ ! -s $S/ndc.log ]'

mk; printf 'ELF...ssid\0wpa_psk\0' > $S/hostapd; echo f > $S/plain; go
check "driver: package hint not set: nothing sent" '[ ! -s $S/ie.log ]'

mk; printf 'ELF...ssid\0wpa_psk\0' > $S/hostapd; : > $S/pid; go
check "driver: hotspot off: nothing sent" '[ ! -s $S/ie.log ]'

mk; printf 'ELF...ssid\0wpa_psk\0' > $S/hostapd; touch $S/ierefuse
printf '#!/bin/sh\ncase "$1" in 6) echo 301 > %s/pid ;; 10) echo 302 > %s/pid ;; 14) echo 303 > %s/pid ;; 18) echo 304 > %s/pid ;; esac\ntrue\n' $S $S $S $S > $S/hook; chmod 755 $S/hook; MAXS=40 go
check "driver refuses 3 hostapd starts: drvbad, stops" '[ -f $S/dir/appleie.drvbad ] && [ $(grep -c "add_ie 0" $S/ie.log) = 3 ] && grep -q "refused the Apple IE 3 times" $S/dir/appleie.log && [ ! -s $S/ndc.log ]'

mk; printf 'ELF...ssid\0wpa_psk\0' > $S/hostapd; touch $S/dir/appleie.drvbad; go
check "driver: drvbad already: nothing sent" '[ ! -s $S/ie.log ] && grep -q "refused the Apple IE before" $S/dir/appleie.log'

mk; printf 'ELF...ssid\0wpa_psk\0' > $S/hostapd; mkdir $S/lone; cp $SVC $S/lone/; NOTOOL=$S/none SVCX=$S/lone/appleie.sh go
check "driver: tool missing: logged with the script path, nothing else" '[ ! -s $S/ie.log ] && [ ! -s $S/ndc.log ] && grep -q "leafiaie wasn.t found (script at" $S/dir/appleie.log'

mk; printf '#!/bin/sh\n[ "$1" = 10 ] && printf "interface=wlan0\\nssid=Kia_Hotspot_x\\n" > %s/conf && echo 555 > %s/pid && echo 555 > %s/netd\ntrue\n' $S $S $S > $S/hook; chmod 755 $S/hook; MAXS=30 go
check "AP restarted by Android later: line added again" '[ $(grep -c stopap $S/ndc.log) = 2 ] && [ $(grep -c "^apple_device_ie=" $S/conf) = 1 ] && [ -s $S/pid ]'

mk; echo apple_device_ie=0000020021 >> $S/conf; go
check "already has it (G70 style): nothing done" '[ ! -s $S/ndc.log ]'

mk; echo f > $S/plain; go
check "package hint not set: nothing done" '[ ! -s $S/ndc.log ] && ! grep -q apple $S/conf'

mk; : > $S/pid; go
check "hotspot off: nothing done" '[ ! -s $S/ndc.log ]'

mk; touch $S/dir/appleie.bad2; go
check "already gave up once: nothing done" '[ ! -s $S/ndc.log ]'

mk; touch $S/dir/appleie.bad; go
check "test 8 flag alone does not stop test 9" '[ -s $S/ndc.log ]'

echo; [ $fails = 0 ] && echo ALL PASS || echo "$fails FAILED"
