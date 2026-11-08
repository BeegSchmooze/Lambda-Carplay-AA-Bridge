#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

log "preuninstall $PKG"
apps_hold
if ! sys_rw; then
    log "FAIL: remount /system rw"
    apps_release
    exit 1
fi
_rc=0
restore_apps || _rc=1
restore_aalib || _rc=1
sync
sys_ro
apps_release
if [ $_rc != 0 ]; then
    log "keeping $BACKUP_DIR"
    exit 1
fi
remove_backup_dir || exit 1
log "back to stock - reboot the head unit to finish"
exit 0
