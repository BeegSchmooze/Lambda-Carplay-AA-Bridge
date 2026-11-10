#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

log "preinstall $PKG"
if [ -d "$BRIDGE_BACKUP" ]; then
    log "FAIL: the G70 bridge (g70.carplay.bt) is installed and already includes turn-by-turn"
    toast "Stinger turn-by-turn: the G70 bridge is installed and already includes turn-by-turn. Nothing was changed."
    exit 1
fi
if [ -d "$OLD_TBT_BACKUP" ]; then
    log "FAIL: the earlier Stinger turn-by-turn (g70.tbt) is installed"
    toast "Stinger turn-by-turn: uninstall the earlier version (g70.tbt) in NEMESIS Manager first, restart, then install this. Nothing was changed."
    exit 1
fi
if ! check_unit; then
    toast "Stinger turn-by-turn: this head unit's files do not match the build. Nothing was changed. See the NEMESIS logs."
    exit 1
fi
log "preinstall ok"
exit 0
