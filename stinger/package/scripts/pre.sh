#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

log "preinstall $PKG"
if [ -d "$BRIDGE_BACKUP" ]; then
    log "FAIL: the G70 bridge (g70.carplay.bt) is installed and already includes turn-by-turn"
    toast "G70 turn-by-turn: the G70 bridge is installed and already includes turn-by-turn. Nothing was changed."
    exit 1
fi
if ! check_unit; then
    toast "G70 turn-by-turn: this head unit's files do not match the build. Nothing was changed. See the NEMESIS logs."
    exit 1
fi
log "preinstall ok"
exit 0
