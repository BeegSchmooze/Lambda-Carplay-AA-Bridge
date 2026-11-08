#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

echo "id=$PKG"
echo "product=$(getprop ro.build.product 2>/dev/null)"
for _n in $APPS; do
    if is_our_app "$_n"; then echo "$_n=turn-by-turn"; elif is_stock_app "$_n"; then echo "$_n=stock"; else echo "$_n=other"; fi
done
if sum_eq "$AA_LIB" "$SUM_NEW_AALIB"; then echo "libautoreceiver_infobank=turn-by-turn"; elif sum_eq "$AA_LIB" "$SUM_STOCK_AALIB"; then echo "libautoreceiver_infobank=stock"; else echo "libautoreceiver_infobank=other"; fi
[ -d "$BACKUP_DIR" ] && echo "backup=$BACKUP_DIR" || echo "backup=none"
exit 0
