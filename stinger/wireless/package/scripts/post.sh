#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

log "postinstall $PKG"

undo() {
    log "FAIL: $1 - putting everything back"
    sys_rw
    restore_apps force
    restore_core
    restore_aalib
    restore_props
    restore_proj
    run_audio preun
    sync
    sys_ro
    apps_release
    toast "G70 wireless CarPlay install failed and was undone; the unit is back to stock. Check the NEMESIS logs."
    exit 1
}

check_unit || undo "unit check"
apps_hold
snapshot_props || undo "prop snapshot"
snapshot_apps || undo "app snapshot"
snapshot_core || undo "libCarPlayCore snapshot"
snapshot_aalib || undo "Android Auto library snapshot"
snapshot_proj || undo "projection flags snapshot"
build_apps || undo "rebuilding the apps from the stock files"
sys_rw || undo "remount /system rw"
apply_apps || undo "app install"
remove_build_dir
apply_core || undo "libCarPlayCore patch"
apply_aalib || undo "Android Auto library patch"
apply_props || undo "props"
apply_proj || undo "projection flags"
run_audio post || undo "audio part"
sync
sys_ro
apps_release
log "all parts installed ($PKG) - rebooting"
retire_usb_descriptor
toast "G70 wireless CarPlay installed. Restarting now: remove the USB drive while it restarts."
exec /system/bin/reboot
log "FAIL: reboot returned"
exit 1
