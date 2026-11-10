#!/system/bin/sh
# stinger.tbt - turn-by-turn on the cluster and HUD for wired Android Auto and CarPlay (and USB
# wireless adapters): Kia Stinger turn-by-turn v1.1 (251120 and 260507). One firmware set per supported build in firmware/<name>/
# (sums.sh + deltas); the set whose stock files this unit has is used (pick_firmware at the end).
# The turn-by-turn part of the G70 bridge (g70.carplay.bt) without its wireless parts.
#
#   HKMC_DiPO      CarPlay route guidance (stock-gated to stepofspec >= 999),
#                    drawn turns and the HUD distance (LeafiaCpTurn), stock maneuver-index fix
#   HKMC_GPM       Android Auto turn manager (stock-gated to stepofspec >= 999) and the HMG-API
#                    AaTurns port: drawn turns, HUD street and distance, next turns, lanes
#   Iap2ServerApp  advertises RouteGuidanceDisplay to the iPhone (stock: stepofspec >= 999 only)
#   HKMC_Navi_ExSL car navigation skips its turn frames while the phone guides
#                    (sys.leafia.phonetbt, stamped by DiPO / GPM); traps still pass
#   libautoreceiver_infobank  Android Auto turn-by-turn on the cluster: Leafia's
#                    projection.tbt library patch ported to this stock library
#
# Nothing modified is shipped: the four apps are rebuilt on the head unit from its own stock
# files (firmware/<name>/<app>.lpd deltas, applied by lpatch only to the exact stock .odex, then added to
# the stock APK), and each result must match the tested build's checksum. Every change is
# checked against the stock checksums first, backed up, and put back byte for byte on uninstall
# (NEMESIS Manager > Packages > Uninstall).
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

PKG=stinger.tbt
BACKUP_DIR=/data/nemesis/backup/stinger.tbt
LOG=/data/nemesis/stinger.tbt.log
APP_DIR=/system/app
BUILD_DIR=/data/nemesis/build/stinger.tbt
APPS="Iap2ServerApp HKMC_DiPO HKMC_GPM HKMC_Navi_ExSL"
# the full bridge (the same apps, plus wireless) keeps its stock backup here while installed
BRIDGE_BACKUP=/data/nemesis/backup/g70.carplay.bt
# the same package under its earlier id (v1.0 and the test builds)
OLD_TBT_BACKUP=/data/nemesis/backup/g70.tbt

# stock files the builds were made from
# our builds (stock APK + patched classes.dex)
# earlier builds of this package an install may replace (the stock backup is kept)

# Android Auto library (turn-by-turn)
AA_LIB=/system/lib/libautoreceiver_infobank.so
# earlier builds of the library this package may replace (rebuilt from the stock backup)

HOLD_PKGS="com.daudio.app.dipo com.tcc.iap2server com.google.android.projection.sink com.mnsoft.navi"
HOLD_FILE=/data/nemesis/stinger.tbt.stopped

LP_ROOT=.
. ./scripts/lpatch.sh

log() { echo "$1"; mkdir -p /data/nemesis 2>/dev/null; echo "$1" >> "$LOG" 2>/dev/null; true; }

toast() {
    am broadcast -a com.hkmc.intent.action.TOAST \
        -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
}

# toolbox `mount -o remount` is refused on these units even as root; only NEMESIS can remount
sys_rw() { /system/xbin/nemesis remount rw >/dev/null 2>&1; }
sys_ro() { /system/xbin/nemesis remount ro >/dev/null 2>&1 || true; }

file_md5() {
    local _line _sum
    _line=$(md5 "$1" 2>/dev/null) || return 1
    set -- $_line
    _sum=$1
    [ -n "$_sum" ] || return 1
    echo "$_sum"
}

sum_eq() {
    local _got
    [ -s "$1" ] || return 1
    _got=$(file_md5 "$1") || return 1
    [ "$_got" = "$2" ]
}

stock_sum() { eval echo "\$SUM_STOCK_${1}_${2}"; }
new_sum() { eval echo "\$SUM_NEW_${1}"; }

chown_system() { chown 0.0 "$1" 2>/dev/null || chown 0:0 "$1" 2>/dev/null || true; }

# copy beside the target, then rename over it (new inode; a running app keeps the old mapping)
put_file() {
    local _src="$1" _dst="$2" _tmp="${2}.g70tmp"
    rm -f "$_tmp" 2>/dev/null || true
    cp -f "$_src" "$_tmp" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    cmp "$_src" "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp" 2>/dev/null; return 1; }
    chmod 644 "$_tmp" 2>/dev/null || true
    chown_system "$_tmp"
    mv "$_tmp" "$_dst" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    chmod 644 "$_dst" 2>/dev/null || true
    chown_system "$_dst"
    [ -x /system/bin/restorecon ] && restorecon "$_dst" 2>/dev/null
    cmp "$_src" "$_dst" >/dev/null 2>&1
}

# ---- checks ----

is_stock_app() {
    sum_eq "$APP_DIR/$1.apk" "$(stock_sum $1 apk)" && sum_eq "$APP_DIR/$1.odex" "$(stock_sum $1 odex)"
}
is_our_app() { sum_eq "$APP_DIR/$1.apk" "$(new_sum $1)"; }
# an earlier build of this package (needs its stock backup to be present)
is_prev_app() {
    local _s _live
    _live=$(file_md5 "$APP_DIR/$1.apk") || return 1
    for _s in $(eval echo "\$SUM_PREV_${1}"); do
        [ "$_live" = "$_s" ] && return 0
    done
    return 1
}

check_unit() {
    local _p _n
    _p=$(getprop ro.build.product 2>/dev/null)
    if [ -z "$FW_SET" ]; then
        log "firmware '$_p': this unit's files match none of this package's firmware sets ($(fw_sets))"
        log "FAIL: no firmware set for this unit"
        return 1
    fi
    log "firmware set $FW_SET (built on $PRODUCT)"
    # the firmware name is informational: every file this package changes is checked
    # below and must be the exact stock file the build was made from
    if [ "$_p" = "$PRODUCT" ]; then
        log "firmware $_p - the build's own"
    else
        log "firmware '$_p' (this build was made on $PRODUCT): installing only if every file below matches"
    fi
    if [ -d "$BRIDGE_BACKUP" ]; then
        log "FAIL: the G70 bridge (g70.carplay.bt) is installed and already includes turn-by-turn - uninstall it first to use this package instead"
        return 1
    fi
    if [ -d "$OLD_TBT_BACKUP" ]; then
        log "FAIL: the earlier Stinger turn-by-turn (g70.tbt) is installed - uninstall it first (NEMESIS Manager, My Packages, g70.tbt), restart, then install this"
        return 1
    fi
    for _n in $APPS; do
        [ -s "$FW_DIR/$_n.lpd" ] || { log "FAIL: payload $FW_DIR/$_n.lpd missing"; return 1; }
        if is_stock_app "$_n"; then
            log "$_n: stock - ok"
        elif is_our_app "$_n"; then
            log "$_n: this package's build is already live"
        elif is_prev_app "$_n" && sum_eq "$BACKUP_DIR/$_n.apk" "$(stock_sum $_n apk)" && sum_eq "$BACKUP_DIR/$_n.odex" "$(stock_sum $_n odex)"; then
            log "$_n: earlier build of this package - will be replaced (stock backup present)"
        else
            log "live $_n.apk md5=$(file_md5 $APP_DIR/$_n.apk) odex md5=$(file_md5 $APP_DIR/$_n.odex)"
            log "FAIL: $_n is neither the stock app this build was made from nor this build"
            return 1
        fi
    done
    if sum_eq "$AA_LIB" "$SUM_STOCK_AALIB"; then
        log "libautoreceiver_infobank.so: stock - ok"
    elif sum_eq "$AA_LIB" "$SUM_NEW_AALIB"; then
        log "libautoreceiver_infobank.so: this package's build is already live"
    elif is_prev_aalib && sum_eq "$BACKUP_DIR/libautoreceiver_infobank.so" "$SUM_STOCK_AALIB"; then
        log "libautoreceiver_infobank.so: earlier build of this package - will be replaced (stock backup present)"
    else
        log "live libautoreceiver_infobank.so md5=$(file_md5 $AA_LIB)"
        log "FAIL: libautoreceiver_infobank.so is neither stock nor this build"
        return 1
    fi
    mkdir -p "$BACKUP_DIR" && echo "$FW_SET" > "$BACKUP_DIR/firmware-set" || return 1
    return 0
}

# ---- apps ----

android_up() { [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ]; }

# stop the apps while their files change, so none restarts against half-written files
apps_hold() {
    local _p
    android_up || return 0
    touch "$HOLD_FILE" 2>/dev/null || { log "WARN: cannot record stopped apps; not stopping them"; return 0; }
    for _p in $HOLD_PKGS; do
        case " $(echo $(cat "$HOLD_FILE" 2>/dev/null)) " in *" $_p "*) ;; *) echo "$_p" >> "$HOLD_FILE" ;; esac
        if pm disable "$_p" >/dev/null 2>&1; then log "stopped $_p for the file swap"; else log "WARN: could not stop $_p"; fi
    done
    return 0
}

apps_release() {
    local _p _left=""
    [ -f "$HOLD_FILE" ] || return 0
    if ! android_up; then
        log "WARN: stopped apps start again on the next run with Android up"
        return 0
    fi
    for _p in $(cat "$HOLD_FILE"); do
        if pm enable "$_p" >/dev/null 2>&1; then log "started $_p again"; else _left="$_left $_p"; log "WARN: could not start $_p again"; fi
    done
    if [ -z "$_left" ]; then rm -f "$HOLD_FILE"; else echo "$_left" > "$HOLD_FILE"; fi
    return 0
}

wipe_dalvik() {
    local _n
    for _n in $APPS; do
        rm -f /data/dalvik-cache/*${_n}* /data/dalvik-cache/arm/*${_n}* /cache/dalvik-cache/*${_n}* 2>/dev/null
    done
    true
}

write_odex() {
    if [ -z "$BOOTCLASSPATH" ]; then
        export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
    fi
    [ -x /system/bin/dexopt ] || return 1
    /system/bin/dexopt --preopt "$1" "$2" "m=y,u=n" || return 1
    [ -s "$2" ] || return 1
    chmod 644 "$2" 2>/dev/null || true
    chown_system "$2"
    [ -x /system/bin/restorecon ] && restorecon "$2" 2>/dev/null
    return 0
}

# the package manager looks for an APK that carries classes.dex in the Dalvik cache;
# put the odex there so the first boot does not re-optimise it
prefill_dalvik() {
    local _odex="$1" _cache="/data/dalvik-cache/system@app@${2##*/}@classes.dex"
    [ -s "$_odex" ] && [ -d /data/dalvik-cache ] || return 0
    rm -f "${_cache}.tmp" 2>/dev/null
    if ! cp -f "$_odex" "${_cache}.tmp" 2>/dev/null || ! cmp "$_odex" "${_cache}.tmp" >/dev/null 2>&1; then
        rm -f "${_cache}.tmp" 2>/dev/null
        return 0
    fi
    chmod 644 "${_cache}.tmp" 2>/dev/null || true
    chown 1000:1000 "${_cache}.tmp" 2>/dev/null || chown 1000.1000 "${_cache}.tmp" 2>/dev/null || true
    mv "${_cache}.tmp" "$_cache" 2>/dev/null || rm -f "${_cache}.tmp" 2>/dev/null
    return 0
}

snapshot_apps() {
    local _n _e
    mkdir -p "$BACKUP_DIR" || return 1
    for _n in $APPS; do
        for _e in apk odex; do
            if [ -s "$BACKUP_DIR/$_n.$_e" ]; then
                log "snapshot exists for $_n.$_e - keeping original"
                continue
            fi
            if ! sum_eq "$APP_DIR/$_n.$_e" "$(stock_sum $_n $_e)"; then
                log "FAIL: $APP_DIR/$_n.$_e is not stock, refusing to snapshot"
                return 1
            fi
            cp -f "$APP_DIR/$_n.$_e" "$BACKUP_DIR/$_n.$_e" || return 1
            sum_eq "$BACKUP_DIR/$_n.$_e" "$(stock_sum $_n $_e)" || { log "FAIL: snapshot of $_n.$_e mismatch"; return 1; }
            log "backed up $APP_DIR/$_n.$_e"
        done
    done
    return 0
}

# rebuild each app from the stock snapshot: lpatch delta (stock .odex -> modified
# classes.dex, refused unless the .odex is the exact original) + lpatch zipadd
# (stock APK + that classes.dex); the result must match the tested build
build_apps() {
    local _n _dex
    mkdir -p "$BUILD_DIR" || return 1
    _dex="$BUILD_DIR/classes.dex"
    for _n in $APPS; do
        if is_our_app "$_n"; then
            log "$_n: already this build - nothing to rebuild"
            continue
        fi
        if [ -s "$BUILD_DIR/$_n.apk" ] && sum_eq "$BUILD_DIR/$_n.apk" "$(new_sum $_n)"; then
            continue
        fi
        rm -f "$BUILD_DIR/$_n.apk" "$_dex" 2>/dev/null
        if ! "$(lp_bin)" delta "$FW_DIR/$_n.lpd" "$BACKUP_DIR/$_n.odex" "$_dex" >/dev/null 2>&1; then
            log "FAIL: stock $_n.odex is not the file this patch needs"
            return 1
        fi
        if ! "$(lp_bin)" zipadd "$BACKUP_DIR/$_n.apk" "$_dex" "$BUILD_DIR/$_n.apk" >/dev/null 2>&1; then
            rm -f "$_dex"
            log "FAIL: could not assemble $_n.apk"
            return 1
        fi
        rm -f "$_dex"
        if ! sum_eq "$BUILD_DIR/$_n.apk" "$(new_sum $_n)"; then
            rm -f "$BUILD_DIR/$_n.apk"
            log "FAIL: rebuilt $_n.apk does not match the tested build"
            return 1
        fi
        log "built $_n.apk from the stock files"
    done
    return 0
}

remove_build_dir() {
    case "$BUILD_DIR" in
        /data/nemesis/build/stinger.tbt) rm -rf "$BUILD_DIR" ;;
    esac
    true
}

apply_apps() {
    local _n _live _odex
    for _n in $APPS; do
        _live="$APP_DIR/$_n.apk"
        _odex="$APP_DIR/$_n.odex"
        if is_our_app "$_n"; then
            log "$_n: already this build"
            continue
        fi
        put_file "$BUILD_DIR/$_n.apk" "$_live" || { log "FAIL: could not write $_live"; return 1; }
        rm -f "$_odex" 2>/dev/null
        [ -f "$_odex" ] && { log "FAIL: could not delete $_odex"; return 1; }
        if write_odex "$_live" "$_odex"; then
            log "OK: $_n installed, odex written"
        else
            rm -f "$_odex" 2>/dev/null
            log "dexopt failed for $_n; boot will optimize"
        fi
    done
    wipe_dalvik
    for _n in $APPS; do
        prefill_dalvik "$APP_DIR/$_n.odex" "$APP_DIR/$_n.apk"
    done
    return 0
}

# restore_apps [force]: without force, only when this build is live
restore_apps() {
    local _n _e
    for _n in $APPS; do
        [ -s "$BACKUP_DIR/$_n.apk" ] || continue
        if [ "$1" != force ] && ! is_our_app "$_n" && ! is_prev_app "$_n" && ! [ -f "$APP_DIR/$_n.apk.g70tmp" ]; then
            if is_stock_app "$_n"; then
                log "$_n already stock"
            else
                log "WARN: live $_n is not this package's build - leaving it alone"
            fi
            continue
        fi
        for _e in apk odex; do
            if [ ! -s "$BACKUP_DIR/$_n.$_e" ]; then
                log "FAIL: incomplete snapshot for $_n"
                return 1
            fi
            put_file "$BACKUP_DIR/$_n.$_e" "$APP_DIR/$_n.$_e" || { log "FAIL: restore $_n.$_e"; return 1; }
        done
        log "restored stock $_n apk+odex"
    done
    wipe_dalvik
    return 0
}

# ---- libautoreceiver_infobank.so: Android Auto turn-by-turn ----

is_prev_aalib() {
    local _s _live
    _live=$(file_md5 "$AA_LIB") || return 1
    for _s in $SUM_PREV_AALIB; do
        [ "$_live" = "$_s" ] && return 0
    done
    return 1
}

snapshot_aalib() {
    mkdir -p "$BACKUP_DIR" || return 1
    if sum_eq "$BACKUP_DIR/libautoreceiver_infobank.so" "$SUM_STOCK_AALIB"; then
        log "snapshot exists for libautoreceiver_infobank.so - keeping original"
        return 0
    fi
    sum_eq "$AA_LIB" "$SUM_STOCK_AALIB" || { log "FAIL: $AA_LIB is not stock, refusing to snapshot"; return 1; }
    cp -f "$AA_LIB" "$BACKUP_DIR/libautoreceiver_infobank.so" || return 1
    sum_eq "$BACKUP_DIR/libautoreceiver_infobank.so" "$SUM_STOCK_AALIB" || { log "FAIL: snapshot of libautoreceiver_infobank.so mismatch"; return 1; }
    log "backed up $AA_LIB"
}

apply_aalib() {
    local _tmp="$BACKUP_DIR/libautoreceiver_infobank.patched" _src="$AA_LIB"
    if sum_eq "$AA_LIB" "$SUM_NEW_AALIB"; then
        log "libautoreceiver_infobank.so: already this build"
        return 0
    fi
    # the delta applies to stock only; an earlier build is rebuilt from the backup
    sum_eq "$AA_LIB" "$SUM_STOCK_AALIB" || _src="$BACKUP_DIR/libautoreceiver_infobank.so"
    rm -f "$_tmp" 2>/dev/null
    "$(lp_bin)" delta "$AA_LPD" "$_src" "$_tmp" >/dev/null 2>&1 && sum_eq "$_tmp" "$SUM_NEW_AALIB" ||
        { rm -f "$_tmp"; log "FAIL: lpatch could not rebuild the Android Auto library"; return 1; }
    if ! put_file "$_tmp" "$AA_LIB"; then
        rm -f "$_tmp"
        log "FAIL: could not write $AA_LIB"
        return 1
    fi
    rm -f "$_tmp"
    log "OK: $AA_LIB patched (Android Auto turn-by-turn)"
}

restore_aalib() {
    [ -s "$BACKUP_DIR/libautoreceiver_infobank.so" ] || return 0
    if ! sum_eq "$AA_LIB" "$SUM_NEW_AALIB" && ! is_prev_aalib && ! [ -f "$AA_LIB.g70tmp" ]; then
        if sum_eq "$AA_LIB" "$SUM_STOCK_AALIB"; then log "libautoreceiver_infobank.so already stock"
        else log "WARN: live libautoreceiver_infobank.so is not this package's build - leaving it alone"; fi
        return 0
    fi
    put_file "$BACKUP_DIR/libautoreceiver_infobank.so" "$AA_LIB" || { log "FAIL: restore $AA_LIB"; return 1; }
    log "restored stock $AA_LIB"
}

# rename our install descriptor on the USB drive so the next boot does not reinstall
retire_usb_descriptor() {
    local _d
    for _d in /storage/usb0 /storage/usb1 /storage/usb2 /mnt/media_rw/usb0 /mnt/media_rw/usb1 /mnt/media_rw/usb2; do
        [ -f "$_d/NEMESIS.data" ] || continue
        grep -q '^type=install' "$_d/NEMESIS.data" 2>/dev/null || continue
        grep -q 'stinger\.tbt\.zip' "$_d/NEMESIS.data" 2>/dev/null || continue
        if mv "$_d/NEMESIS.data" "$_d/NEMESIS.data.installed" 2>/dev/null; then
            log "renamed $_d/NEMESIS.data to NEMESIS.data.installed so the next boot does not reinstall"
            # test drive: make the diagnostic probe the drive's next NEMESIS item
            if [ -f "$_d/_g70-probe/NEMESIS.sh" ] && [ -f "$_d/_g70-probe/NEMESIS.data" ]; then
                cp "$_d/_g70-probe/NEMESIS.sh" "$_d/NEMESIS.sh" 2>/dev/null &&
                    cp "$_d/_g70-probe/NEMESIS.data" "$_d/NEMESIS.data" 2>/dev/null &&
                    log "the USB drive now runs the diagnostic probe next time"
            fi
        else
            log "WARN: could not rename $_d/NEMESIS.data - remove the USB drive before the head unit restarts"
        fi
    done
    true
}

remove_backup_dir() {
    case "$BACKUP_DIR" in
        /data/nemesis/backup/stinger.tbt) rm -rf "$BACKUP_DIR" ;;
        *) log "FAIL: refusing to remove $BACKUP_DIR"; return 1 ;;
    esac
}

# ---- firmware sets ----
# firmware/<name>/sums.sh holds one firmware's values (PRODUCT, SUM_STOCK_*, SUM_NEW_*, SUM_PREV_*)
# and its deltas sit beside it. The set whose files this unit has (each app and the Android Auto
# library stock, ours or an earlier build of ours) is used. Uninstall after a firmware update,
# when no set matches any more, falls back to the set recorded at install; the restore steps
# still leave alone any file that is not this package's.
FW_SET=""; FW_DIR=""; AA_LPD=""
fw_sets() { local _d _o=""; for _d in firmware/*/sums.sh; do _d=${_d%/sums.sh}; _o="$_o ${_d#firmware/}"; done; echo "${_o# }"; }
fw_load() { . "./firmware/$1/sums.sh"; FW_DIR=firmware/$1; AA_LPD=$FW_DIR/libautoreceiver_infobank.tbt.lpd; }
fw_matches() {
    local _n
    for _n in $APPS; do
        is_stock_app "$_n" || is_our_app "$_n" || is_prev_app "$_n" || return 1
    done
    sum_eq "$AA_LIB" "$SUM_STOCK_AALIB" || sum_eq "$AA_LIB" "$SUM_NEW_AALIB" || is_prev_aalib
}
pick_firmware() {
    local _s _rec=""
    for _s in $(fw_sets); do
        fw_load "$_s"
        if fw_matches; then FW_SET=$_s; return 0; fi
    done
    [ -r "$BACKUP_DIR/firmware-set" ] && read -r _rec < "$BACKUP_DIR/firmware-set"
    if [ -n "$_rec" ] && [ -r "firmware/$_rec/sums.sh" ]; then
        fw_load "$_rec"; FW_SET=$_rec; return 0
    fi
    return 1
}
pick_firmware || true
