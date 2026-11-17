#!/system/bin/sh
# Kia Stinger: put the Apple device IE (wireless CarPlay) into the projection hotspot's beacons.
#
# The G70's NetworkManagementService passes WifiConfiguration.vendorSpecific ("0000020021") to netd,
# which writes "apple_device_ie=0000020021" into /data/misc/wifi/hostapd.conf; hostapd then puts the
# Apple IE in its beacons and probe responses. The Stinger's NMS has no such branch, so its
# hostapd.conf never gets the line (hotspot-info 2026-11-14). This NEMESIS service (root) adds it:
# each time hostapd starts without it, stop the AP through netd, append the line, start it again.
#
# Test 9 (test 8 left the hotspot off, 2026-11-15): the line is only tried when /system/bin/hostapd
# contains the option name at all (a hostapd that parses it has the string). If hostapd still doesn't
# come back up with it, the line is taken out and the AP is stopped AND started through netd (a bare
# startap is refused while netd still holds the dead hostapd), then it stops trying (appleie.bad2).
# Everything it does goes to appleie.log in the backup dir as well (hotspot-info copies it).
#
# GPL-3.0 (Genesis G70 bridge).
export PATH=${LEAFIA_TEST_PATH:+$LEAFIA_TEST_PATH:}/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
CONF=${LEAFIA_TEST_CONF:-/data/misc/wifi/hostapd.conf}
HOSTAPD=${LEAFIA_TEST_HOSTAPD:-/system/bin/hostapd}
DIR=${LEAFIA_TEST_DIR:-/data/nemesis/backup/g70.carplay.bt}
BAD=$DIR/appleie.bad2
LOG=$DIR/appleie.log
IE=0000020021

say() {
    echo "appleie: $*"
    log -t LeafiaCP "appleie: $*" 2>/dev/null
    [ -d "$DIR" ] && echo "$(date) $*" >> "$LOG" 2>/dev/null
    true
}

hpid() {
    ps 2>/dev/null | while read -r _u _p _r; do
        case "$_r" in *" /system/bin/hostapd"*) echo "$_p"; break ;; esac
    done
}

has_line() { grep -q '^apple_device_ie=' "$CONF" 2>/dev/null; }

# rewrite in place (keeps owner system:wifi and mode 0660 so hostapd, uid wifi, can still read it)
drop_line() {
    grep -v '^apple_device_ie=' "$CONF" > ${TMPDIR:-/data/local/tmp}/leafia-hostapd.$$ && cat ${TMPDIR:-/data/local/tmp}/leafia-hostapd.$$ > "$CONF"
    rm -f ${TMPDIR:-/data/local/tmp}/leafia-hostapd.$$
}

up_after() {
    _i=0
    while [ $_i -lt "$1" ]; do
        sleep 1
        _i=$((_i + 1))
    done
    [ -n "$(hpid)" ]
}

# netd refuses startap while it still holds a hostapd pid (even a dead one): stop first
restart_ap() {
    say "stopap: $(ndc softap stopap 2>&1)"
    say "startap: $(ndc softap startap 2>&1)"
}

# Test 11 (the Stinger's hostapd has no apple_device_ie option, test 9 log 2026-11-15): do what the G70's
# hostapd does itself (hostapd_add_carplay_ie, hotspot-info 3 of a G70, 2026-11-16): hand the IE to the
# Wi-Fi driver as private commands "add_ie <0 beacon|1 probe response|2 assoc response> 00A040 <IE>",
# through leafiaie (svc/leafiaie, a 2 KB static ARM tool), once each time hostapd starts. The hotspot
# itself is never stopped or restarted here. A driver that refuses the beacon command three hostapd
# starts in a row gets appleie.drvbad and no more tries.
DRVBAD=$DIR/appleie.drvbad
find_tool() {
    for _c in ${LEAFIA_TEST_TOOL:+"$LEAFIA_TEST_TOOL"} "${0%/*}/leafiaie" /data/nemesis/*/svc/leafiaie \
        /data/nemesis/*/*/svc/leafiaie /data/nemesis/*/*/*/svc/leafiaie /data/nemesis/*/*/*/*/svc/leafiaie; do
        [ -f "$_c" ] || continue
        mkdir -p "$DIR" && cat "$_c" > "$DIR/leafiaie.new" && chmod 755 "$DIR/leafiaie.new" \
            && mv "$DIR/leafiaie.new" "$DIR/leafiaie" && echo "$DIR/leafiaie" && return 0
        echo "$_c"
        return 0
    done
    return 1
}

# no head/tr on this Android: plain shell only
iface() {
    _i=
    while read -r _l; do
        case "$_l" in interface=?*) _i=${_l#interface=}; break ;; esac
    done < "$CONF" 2>/dev/null
    echo "${_i:-wlan0}"
}

driver_path() {
    if [ -f "$DRVBAD" ]; then
        say "the Wi-Fi driver refused the Apple IE before (appleie.drvbad): not trying"
        return
    fi
    TOOL=$(find_tool)
    if [ -z "$TOOL" ]; then
        say "hostapd has no apple_device_ie option and leafiaie wasn't found (script at $0): leaving the hotspot alone"
        return
    fi
    say "hostapd has no apple_device_ie option: giving the Apple IE to the Wi-Fi driver ($TOOL, script at $0)"
    _done=
    _refused=0
    while true; do
        sleep 2
        [ "$(getprop persist.leafia.ap.plain)" = t ] || continue
        _pid=$(hpid)
        [ -n "$_pid" ] || { _done=; continue; }
        [ "$_pid" = "$_done" ] && continue
        # let hostapd finish setting up the beacon first (the G70's hostapd adds it after that too)
        sleep 2
        _ok=0
        for _t in 0 1 2; do
            _r=$("$TOOL" "$(iface)" add_ie $_t 00A040 $IE 2>&1)
            _rc=$?
            say "hostapd $_pid add_ie $_t: exit $_rc, $(echo $_r)"
            [ $_t = 0 ] && [ $_rc = 0 ] && _ok=1
        done
        _done=$_pid
        if [ $_ok = 1 ]; then
            _refused=0
            say "Apple IE given to the driver (hostapd $_pid)"
        else
            _refused=$((_refused + 1))
            if [ $_refused -ge 3 ]; then
                say "the driver refused the Apple IE $_refused times: not trying again"
                mkdir -p "$DIR" && echo "$(date)" > "$DRVBAD"
                return
            fi
        fi
    done
}

trap 'exit 0' 1 2 15
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
_sz=$(wc -c < "$LOG" 2>/dev/null)
[ -n "$_sz" ] && [ "$_sz" -gt 65536 ] 2>/dev/null && mv "$LOG" "$LOG.1"
# yes/no only: grep -c prints 0 AND fails, so "grep -c || echo 0" gives two lines
knows() { grep -q apple_device_ie "$1" 2>/dev/null && echo yes || echo no; }
KNOWS=$(knows "$HOSTAPD")
say "started: hostapd knows apple_device_ie: $KNOWS; netd: $(knows /system/bin/netd); test 8 flag: $([ -f "$DIR/appleie.bad" ] && echo yes || echo no)"
if [ "$KNOWS" != yes ]; then
    driver_path
    while true; do sleep 3600; done
fi

done_pid=
while true; do
    sleep 2
    if [ -f "$BAD" ]; then
        sleep 60
        continue
    fi
    [ "$(getprop persist.leafia.ap.plain)" = t ] || continue
    pid=$(hpid)
    [ -n "$pid" ] || { done_pid=; continue; }
    [ "$pid" = "$done_pid" ] && continue
    if has_line; then
        say "hotspot up with the Apple IE (hostapd $pid)"
        done_pid=$pid
        continue
    fi
    sleep 1
    say "hostapd $pid has no Apple IE: adding apple_device_ie=$IE and restarting the hotspot"
    echo "apple_device_ie=$IE" >> "$CONF"
    restart_ap
    if up_after 4; then
        done_pid=$(hpid)
        say "hotspot back up with the Apple IE (hostapd $done_pid)"
    else
        say "hostapd didn't start with apple_device_ie: removing it, restarting the hotspot as before, not trying again"
        mkdir -p "$DIR" && echo "$(date)" > "$BAD"
        drop_line
        restart_ap
        if ! up_after 4; then
            say "hotspot still down: one more restart"
            restart_ap
            up_after 4 && say "hotspot back up without the Apple IE" || say "hotspot still down: turn the car off and on"
        else
            say "hotspot back up without the Apple IE"
        fi
        done_pid=$(hpid)
    fi
done
