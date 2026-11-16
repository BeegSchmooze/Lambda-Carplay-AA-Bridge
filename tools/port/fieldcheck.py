import os, re, sys
# For a port: every stock field our classes use (Lcls;->name:type, cls in the app), compared by
# how the stock code uses it in 251120 vs the port: the number of reads/writes and the methods
# that touch it. Renamed fields fail check_refs; this catches a name that now means another
# field (as DipoService.C did on 260507). Prints the suspicious ones.
# usage: fieldcheck.py <port>
W = '/work'
port = sys.argv[1]
REF = re.compile(r'(L[\w/$]+;)->([\w$]+):(\S+)')
apps = [('HKMC_DiPO', 'dipo18'), ('HKMC_GPM', 'gpm15'), ('HKMC_Navi_ExSL', 'navi14'), ('Iap2ServerApp', 'iap2')]


def uses(root):
    """field -> (number of uses, set of method names using it), over a stock tree"""
    out = {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            if not f.endswith('.smali'):
                continue
            m = None
            for l in open(os.path.join(dp, f), encoding='utf-8', errors='replace'):
                if l.startswith('.method'):
                    m = l.split()[-1].split('(')[0]
                for c, n, t in REF.findall(l):
                    k = c + '->' + n + ':' + t
                    u = out.setdefault(k, [0, set()])
                    u[0] += 1
                    u[1].add(m)
    return out


bad = 0
for app, t in apps:
    base = W + '/ports/' + os.environ.get('MERGE_BASE', 'g70-251120') + '/smali/' + app
    theirs = W + '/ports/' + port + '/smali/' + app
    tree = W + '/build/' + port + '-' + t
    ub, ut = uses(base), uses(theirs)
    ours = set()
    for dp, _, fs in os.walk(tree):
        for f in fs:
            p = os.path.join(dp, f)
            r = os.path.relpath(p, tree)
            s = os.path.join(theirs, r)
            if os.path.exists(s) and open(s, encoding='utf-8', errors='replace').read() == open(p, encoding='utf-8', errors='replace').read():
                continue
            for l in open(p, encoding='utf-8', errors='replace'):
                for c, n, ty in REF.findall(l):
                    ours.add(c + '->' + n + ':' + ty)
    n = 0
    for k in sorted(ours):
        cls = k.split(';->')[0][1:] + '.smali'
        if not os.path.exists(os.path.join(theirs, cls)):
            continue                     # framework or our own class
        if k not in ub:
            continue                     # a field of ours
        n += 1
        b, th = ub[k], ut.get(k, [0, set()])
        if th[0] == 0:
            print(app, 'MISSING', k)
            bad += 1
        elif abs(b[0] - th[0]) > max(2, b[0] // 4) or len(b[1]) != len(th[1]):
            print(app, 'CHANGED USE', k, 'uses', b[0], '->', th[0], 'methods', len(b[1]), '->', len(th[1]))
            bad += 1
    print(app, n, 'stock fields checked')
print(bad, 'to look at')
