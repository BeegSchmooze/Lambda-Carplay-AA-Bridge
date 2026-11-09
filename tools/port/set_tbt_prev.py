"""Mark an earlier g70.tbt build as "previous" in a new single-firmware build: every SUM_NEW_*
of the old set that differs from the new build's goes into the matching SUM_PREV_* (space-
separated, kept with any already there), so the new package installs over the old one and
uninstall still recognises it. Run before ports/build_tbt_multi.py.
usage: set_tbt_prev.py <new release-<port>-tbt dir> <old sums.sh or common.sh> ..."""
import re, sys

new = sys.argv[1] + '/pkg/scripts/common.sh'
s = open(new).read()
VAL = re.compile(r'^(SUM_(?:NEW|PREV)_\w+)=(.*)$', re.M)
cur = {k: v.strip('"') for k, v in VAL.findall(s)}
for old in sys.argv[2:]:
    for k, v in VAL.findall(open(old).read()):
        if not k.startswith('SUM_NEW_'):
            continue
        v = v.strip('"')
        name = k[len('SUM_NEW_'):]
        pk = 'SUM_PREV_' + name
        assert pk in cur, pk + ' missing in ' + new
        if not v or v == cur.get(k):
            continue
        have = cur[pk].split()
        if v not in have:
            have.append(v)
            cur[pk] = ' '.join(have)
            print('%s += %s' % (pk, v))
for k, v in cur.items():
    if k.startswith('SUM_PREV_'):
        s, n = re.subn(r'^%s=.*$' % k, '%s="%s"' % (k, v), s, flags=re.M)
        assert n == 1, k
open(new, 'w', newline='\n').write(s)
