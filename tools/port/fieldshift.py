"""Field renames check_refs can't see: a field our code names (added lines + our new classes) that
still exists in the port with the same type, but whose position among that class's fields of the
same type moved (obfuscated names shifted: 260507 e/u Al/Am -> 260903 Am/An). Also reflection:
field names in const-strings of our new classes that exist in the base but not in the port.
usage: MERGE_BASE=<base port> MERGE_OURS=<ours prefix> fieldshift.py <port>"""
import os, re, sys

W = '/work'
port = sys.argv[1]
basep = os.environ.get('MERGE_BASE', 'g70-251120')
oursp = os.environ.get('MERGE_OURS', '')
APPS = [('HKMC_DiPO', 'dipo18'), ('HKMC_GPM', 'gpm15'), ('HKMC_Navi_ExSL', 'navi14'), ('Iap2ServerApp', 'iap2')]
FREF = re.compile(r'(L[\w/$]+;)->([\w$]+):([\w/$;\[]+)')
FDEF = re.compile(r'^\.field [\w\s-]*?([\w$]+):([\w/$;\[]+)')
STR = re.compile(r'const-string(?:/jumbo)? \w+, "([\w|$]+)"')


def fields(p):
    out = []
    for l in open(p, encoding='utf-8', errors='replace'):
        m = FDEF.match(l)
        if m:
            out.append(m.groups())
    return out


def lines(p):
    return open(p, encoding='utf-8', errors='replace').read().split('\n')


bad = 0
for app, t in APPS:
    base = '%s/ports/%s/smali/%s' % (W, basep, app)
    theirs = '%s/ports/%s/smali/%s' % (W, port, app)
    ours = '%s/build/%s' % (W, (oursp + '-' + t) if oursp else t)
    refs, strs = {}, {}
    for r, _, fs in os.walk(ours):
        for f in fs:
            p = os.path.join(r, f)
            rel = os.path.relpath(p, ours)
            b = os.path.join(base, rel)
            src = lines(p)
            if os.path.exists(b):
                bl = set(lines(b))
                src = [l for l in src if l not in bl]
            else:
                for l in src:
                    for s in STR.findall(l):
                        strs.setdefault(s, set()).add(rel)
            for l in src:
                for c, n, ty in FREF.findall(l):
                    refs.setdefault((c, n, ty), set()).add(rel)
    n = 0
    for (c, name, ty), where in sorted(refs.items()):
        bp = os.path.join(base, c[1:-1] + '.smali')
        tp = os.path.join(theirs, c[1:-1] + '.smali')
        if not os.path.exists(bp) or not os.path.exists(tp):
            continue
        n += 1
        bs = [x for x, y in fields(bp) if y == ty]
        ts = [x for x, y in fields(tp) if y == ty]
        if name not in bs:
            continue
        i = bs.index(name)
        want = ts[i] if len(ts) == len(bs) else '?'
        if name not in ts or want != name:
            bad += 1
            print('%s SHIFT %s->%s:%s  base %s, port %s  -> %s  used by %s' % (
                app, c, name, ty, bs, ts, want, sorted(where)[:3]))
    # reflection: names our new classes look up (e.g. "Dx|DM")
    allbase, allport = set(), set()
    for d, acc in ((base, allbase), (theirs, allport)):
        for r, _, fs in os.walk(d):
            for f in fs:
                for x, _ in fields(os.path.join(r, f)):
                    acc.add(x)
    for s, where in sorted(strs.items()):
        names = s.split('|')
        if not all(re.match(r'^[A-Za-z$][\w$]{0,3}$', x) for x in names):
            continue
        hb = [x for x in names if x in allbase]
        if hb and not any(x in allport for x in names):
            bad += 1
            print('%s REFLECT "%s" in %s: in base, none in port' % (app, s, sorted(where)[:2]))
    print(app, n, 'stock field refs checked')
print(bad, 'to look at')
