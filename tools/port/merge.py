import os, re, shutil, subprocess, sys
# 3-way merge of our builds onto a port's stock smali: base = 251120 stock (fresh deodex),
# ours = build/<tree>, theirs = ports/<port>/smali/<App>. Output build/<port>-<tree>.
# baksmali's own comment lines are dropped from all three first. New Leafia classes are copied.
W = '/work'
port = sys.argv[1]
COMMENT = re.compile(r'^\s*# (invokes|getter for|setter for|operator for):')
def clean(p):
    return '\n'.join(l for l in open(p, encoding='utf-8').read().replace('\r\n', '\n').split('\n') if not COMMENT.match(l))
apps = [('HKMC_DiPO', 'dipo18'), ('HKMC_GPM', 'gpm15'), ('HKMC_Navi_ExSL', 'navi14'), ('Iap2ServerApp', 'iap2')]
# optional: App:tree pairs instead (e.g. HKMC_Navi_ExSL:navi13)
if len(sys.argv) > 2:
    apps = [tuple(a.split(':')) for a in sys.argv[2:]]
tmp = '/tmp/merge3'
for app, t in apps:
    # MERGE_BASE=g70-260507 MERGE_OURS=g70-260507-nocam: rebase the newest trees (build/<ours>-<tree>)
    # from that port's stock instead of the 251120 originals
    base = W + '/ports/' + os.environ.get('MERGE_BASE', 'g70-251120') + '/smali/' + app
    ours = W + '/build/' + (os.environ['MERGE_OURS'] + '-' + t if os.environ.get('MERGE_OURS') else t)
    theirs = W + '/ports/' + port + '/smali/' + app
    out = W + '/build/' + port + '-' + t
    shutil.rmtree(out, ignore_errors=True)
    shutil.copytree(theirs, out)
    stats = {'same-theirs': 0, 'clean': 0, 'conflict': [], 'added': 0}
    for root, _, fs in os.walk(ours):
        for f in fs:
            p = os.path.join(root, f); r = os.path.relpath(p, ours)
            b = os.path.join(base, r); th = os.path.join(theirs, r); o = os.path.join(out, r)
            if not os.path.exists(b):
                os.makedirs(os.path.dirname(o), exist_ok=True)
                shutil.copy(p, o); stats['added'] += 1; continue
            co, cb = clean(p), clean(b)
            if co == cb: continue
            # a class we changed that the port no longer has (renamed or removed): by hand
            if not os.path.exists(th):
                stats['conflict'].append((r, 'missing in port')); continue
            ct = clean(th)
            if cb == ct:
                open(o, 'w').write(co + '\n'); stats['same-theirs'] += 1; continue
            shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp)
            for n, c in (('o', co), ('b', cb), ('t', ct)): open(tmp + '/' + n, 'w').write(c + '\n')
            rc = subprocess.call(['git', 'merge-file', '-L', 'ours', '-L', 'base', '-L', 'theirs', tmp + '/o', tmp + '/b', tmp + '/t'])
            shutil.copy(tmp + '/o', o)
            if rc == 0: stats['clean'] += 1
            else: stats['conflict'].append((r, rc))
    print(app, 'added', stats['added'], 'patched (their copy unchanged)', stats['same-theirs'], 'merged clean', stats['clean'], 'conflicts', stats['conflict'])
