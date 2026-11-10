#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

log "postinstall $PKG"

undo() {
    log "FAIL: $1 - putting everything back"
    sys_rw
    restore_apps force
    restore_aalib
    sync
    sys_ro
    apps_release
    toast "Stinger turn-by-turn install failed and was undone; the unit is back to stock. Check the NEMESIS logs."
    exit 1
}

check_unit || undo "unit check"
apps_hold
snapshot_apps || undo "app snapshot"
snapshot_aalib || undo "Android Auto library snapshot"
build_apps || undo "rebuilding the apps from the stock files"
sys_rw || undo "remount /system rw"
apply_apps || undo "app install"
remove_build_dir
apply_aalib || undo "Android Auto library patch"
sync
sys_ro
apps_release
log "all parts installed ($PKG) - rebooting"
retire_usb_descriptor
toast "Stinger turn-by-turn installed. Restarting now: remove the USB drive while it restarts."
exec /system/bin/reboot
log "FAIL: reboot returned"
exit 1
