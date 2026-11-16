import os, re, sys, difflib
# For a port: every reference our code makes (added classes + lines we added to stock classes)
# into a stock class that changed between the 251120 stock and the port's stock. A reference is
# OK when the target still exists in the port with the same body; otherwise the method/field in
# the port whose body matches the 251120 target best is suggested (obfuscated names shift).
W = '/work'
port = sys.argv[1]
APPS = [('HKMC_DiPO', 'dipo18'), ('HKMC_GPM', 'gpm15'), ('HKMC_Navi_ExSL', 'navi14'), ('Iap2ServerApp', 'iap2')]
COMMENT = re.compile(r'^\s*(# (invokes|getter for|setter for|operator for):|\.line )')
REF = re.compile(r'(L[\w/$]+;)->([\w$<>]+)(\([^)]*\)[\w/$;\[]+|:[\w/$;\[]+)')


def lines(p):
    return [l for l in open(p, encoding='utf-8').read().replace('\r\n', '\n').split('\n') if not COMMENT.match(l)]


def members(p):
    """name+sig -> body text for methods; name:type -> '' for fields"""
    m, cur, body = {}, None, []
    for l in lines(p):
        s = l.strip()
        if s.startswith('.field '):
            d = s.split(' = ')[0].split()[-1]
            m[d] = 'FIELD ' + s
        elif s.startswith('.method '):
            cur = s.split()[-1]; body = []
        elif s.startswith('.end method') and cur:
            m[cur] = '\n'.join(body); cur = None
        elif cur is not None:
            body.append(s)
    return m


def cls_path(root, c):
    return os.path.join(root, c[1:-1] + '.smali')


for app, t in APPS:
    # MERGE_BASE / MERGE_OURS as in merge.py (rebasing the newest trees from another port's stock)
    base = W + '/ports/' + os.environ.get('MERGE_BASE', 'g70-251120') + '/smali/' + app
    theirs = W + '/ports/' + port + '/smali/' + app
    ours = W + '/build/' + (os.environ['MERGE_OURS'] + '-' + t if os.environ.get('MERGE_OURS') else t)
    refs = {}
    for r, _, fs in os.walk(ours):
        for f in fs:
            p = os.path.join(r, f); rel = os.path.relpath(p, ours)
            b = os.path.join(base, rel)
            if os.path.exists(b):
                bl = set(lines(b))
                src = [l for l in lines(p) if l not in bl]   # lines we added
            else:
                src = lines(p)
            for l in src:
                for c, n, s in REF.findall(l):
                    refs.setdefault((c, n + s), set()).add(rel)
    bad = 0
    for (c, ms), where in sorted(refs.items()):
        bp, tp = cls_path(base, c), cls_path(theirs, c)
        if not os.path.exists(bp):
            continue  # framework or our own class
        if not os.path.exists(tp):
            print(app, 'MISSING CLASS', c, 'used by', sorted(where)); bad += 1; continue
        if lines(bp) == lines(tp):
            continue
        bm, tm = members(bp), members(tp)
        if ms not in bm:
            continue
        if ms in tm and tm[ms] == bm[ms]:
            continue
        sig = ms[ms.index('('):] if '(' in ms else ms[ms.index(':'):]
        cands = [(difflib.SequenceMatcher(None, bm[ms], tm[k]).ratio(), k) for k in tm
                 if (k[k.index('('):] if '(' in k else k[k.index(':'):]) == sig]
        cands.sort(reverse=True)
        same = ms in tm
        print('%s %s %s->%s  (%s in port; best: %s) used by %s' % (
            app, 'CHANGED' if same else 'RENAMED?', c, ms, 'present' if same else 'absent',
            ', '.join('%s %.2f' % (k, r) for r, k in cands[:3]), sorted(where)[:3]))
        bad += 1
    print(app, len(refs), 'references checked,', bad, 'to look at')
