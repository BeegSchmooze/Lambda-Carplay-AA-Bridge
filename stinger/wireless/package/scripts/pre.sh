#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

log "preinstall $PKG"
if ! check_unit; then
    toast "G70 wireless CarPlay: this head unit's files do not match the build. Nothing was changed. See the NEMESIS logs."
    exit 1
fi
if ! run_audio pre; then
    toast "G70 wireless CarPlay: the audio part does not fit. Nothing was changed. See the NEMESIS logs."
    exit 1
fi
log "preinstall ok"
exit 0
