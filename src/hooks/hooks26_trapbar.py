"""Update 26: the HUD approach bar from the trap frame. In an HKMC_Navi_ExSL tree, every
NavigationCluster.updateTBTTrapInfoNew(NaviTbtTrapInfo) call (e/a x2, message/a x1) goes through
LeafiaTrapBar.send(cluster, info) instead. LeafiaTrapBar.smali must already be in the tree
(aa-port/bar/build_trapbar.sh copies it). Idempotent: a patched tree is left alone.
usage: hooks26_trapbar.py <navi tree>"""
import os, re, sys

tree = sys.argv[1]
M = 'Lcom/mnsoft/navi/LeafiaTrapBar;->send(Lcom/hkmc/cluster/NavigationCluster;Lcom/hkmc/cluster/NavigationCluster$NaviTbtTrapInfo;)V'
call = re.compile(r'^(\s*)invoke-virtual \{(v\d+), (v\d+)\}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTTrapInfoNew\(Lcom/hkmc/cluster/NavigationCluster\$NaviTbtTrapInfo;\)V$', re.M)
assert os.path.exists(os.path.join(tree, 'com/mnsoft/navi/LeafiaTrapBar.smali')), 'LeafiaTrapBar.smali missing'
want = {'com/mnsoft/navi/e/a.smali': 2, 'com/mnsoft/navi/message/a.smali': 1}
done = 0
for rel, n in want.items():
    p = os.path.join(tree, rel)
    s = open(p, newline='').read()
    have = s.count(M)
    if have == n:
        print('%s: already patched' % rel); done += 1; continue
    assert have == 0, '%s: partly patched' % rel
    found = call.findall(s)
    assert len(found) == n, '%s: %d trap calls, expected %d' % (rel, len(found), n)
    s = call.sub(lambda m: '%sinvoke-static {%s, %s}, %s' % (m.group(1), m.group(2), m.group(3), M), s)
    open(p, 'w', newline='').write(s)
    print('%s: %d trap call(s) -> LeafiaTrapBar.send' % (rel, n))
# no other class may still call it directly (the 17-int updateTBTTrapInfo is left alone)
left = []
for d, _, fs in os.walk(tree):
    for f in fs:
        if f.endswith('.smali') and f != 'LeafiaTrapBar.smali':
            if 'NavigationCluster;->updateTBTTrapInfoNew' in open(os.path.join(d, f), newline='').read():
                left.append(os.path.join(d, f))
assert not left, 'direct calls left: %s' % left
