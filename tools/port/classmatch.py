"""For a port whose obfuscated class names may have shifted: every stock class we modify (ours !=
base) is matched to the port's class with the most similar string constants + method signatures.
Reports classes whose best match has a different name (merge.py would have merged the wrong file).
usage: classmatch.py <base port> <ours prefix> <port>   e.g. g70-260507 g70-260507-nocam g70-260903"""
import os, re, sys

W = '/work'
base_p, ours_p, port = sys.argv[1:4]
APPS = [('HKMC_DiPO', 'dipo18'), ('HKMC_GPM', 'gpm15'), ('HKMC_Navi_ExSL', 'navi14'), ('Iap2ServerApp', 'iap2')]
STR = re.compile(r'const-string(?:/jumbo)? \w+, "(.*)"$')
MET = re.compile(r'^\.method (.*)$')
COMMENT = re.compile(r'^\s*(# (invokes|getter for|setter for|operator for):|\.line )')
OBF = re.compile(r'L(com/mnsoft/navi|com/daudio/app/dipo|com/google/android/projection/sink|com/telechips|com/hkmc)[\w/$]*;')


def feats(p):
    s, m = set(), set()
    for l in open(p, encoding='utf-8', errors='replace'):
        l = l.rstrip('\n')
        x = STR.search(l)
        if x:
            s.add(x.group(1))
        x = MET.match(l)
        if x:
            # keep only framework/java types in signatures (app class names are obfuscated)
            m.add(OBF.sub('L*;', re.sub(r' [\w$<>]+\(', ' (', x.group(1))))
    return s, m


def clean(p):
    return '\n'.join(l for l in open(p, encoding='utf-8', errors='replace').read().split('\n') if not COMMENT.match(l))


def sim(a, b):
    (sa, ma), (sb, mb) = a, b
    js = len(sa & sb) / max(1, len(sa | sb))
    jm = len(ma & mb) / max(1, len(ma | mb))
    return (js * 2 + jm) / 3 if (sa or sb) else jm


bad = 0
for app, t in APPS:
    base = '%s/ports/%s/smali/%s' % (W, base_p, app)
    ours = '%s/build/%s-%s' % (W, ours_p, t)
    theirs = '%s/ports/%s/smali/%s' % (W, port, app)
    idx = {}
    for root, _, fs in os.walk(theirs):
        for f in fs:
            if f.endswith('.smali'):
                q = os.path.join(root, f)
                idx[os.path.relpath(q, theirs)] = feats(q)
    for root, _, fs in os.walk(ours):
        for f in fs:
            r = os.path.relpath(os.path.join(root, f), ours)
            b = os.path.join(base, r)
            if not os.path.exists(b) or clean(b) == clean(os.path.join(ours, r)):
                continue
            fb = feats(b)
            ranked = sorted(((sim(fb, v), k) for k, v in idx.items()), reverse=True)[:3]
            same = sim(fb, idx[r]) if r in idx else -1
            flag = 'OK  ' if ranked[0][1] == r else 'MOVED'
            if flag != 'OK  ':
                bad += 1
            print('%s %s %s: same name %.2f; best %s' % (flag, app, r, same,
                  ', '.join('%s %.2f' % (k, v) for v, k in ranked)))
print('moved:', bad)
