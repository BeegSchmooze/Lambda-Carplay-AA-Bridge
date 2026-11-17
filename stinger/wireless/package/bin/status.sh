#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

echo "id=$PKG"
echo "product=$(getprop ro.build.product 2>/dev/null)"
for _n in $APPS; do
    if is_our_app "$_n"; then echo "$_n=bridge"; elif is_stock_app "$_n"; then echo "$_n=stock"; else echo "$_n=other"; fi
done
echo "libCarPlayCore=$(core_state)"
for _prop in $PROPS persist.leafia.g70.cpbridge persist.leafia.g70.cpcomp; do
    echo "${_prop}=$(getprop "$_prop" 2>/dev/null)"
done
[ -d "$BACKUP_DIR" ] && echo "backup=$BACKUP_DIR" || echo "backup=none"
exit 0
