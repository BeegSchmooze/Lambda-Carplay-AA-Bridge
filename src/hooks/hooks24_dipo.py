import os, sys
# Update 24 DiPO hook: switching navigation apps on the iPhone.
# When the iPhone moves the turn display to another app (Apple Maps -> Google Maps), DiPO gets
# stopTurnByTurn (e/u.nS) and then startTurnByTurn (e/u.nR) for the new app, but stock only
# wipes its cached route guidance (e/u.nT: the per-component state and the maneuver list) on a
# disconnect. The old app's maneuvers stayed cached and our "phone is guiding" mark
# (sys.leafia.phonetbt) stayed set, so the car navigation's own frames were held off for 90 s.
# Hook: nS() calls nT() first, exactly as disconnected() does (nT also clears the mark via
# LeafiaTbtMark.clear). The next app starts from an empty state.
# usage: hooks24_dipo.py <DiPO smali tree>
tree = sys.argv[1]
p = os.path.join(tree, 'com/daudio/app/dipo/e/u.smali')
lines = open(p, encoding='utf-8').read().split('\n')
CALL = '    invoke-direct {p0}, Lcom/daudio/app/dipo/e/u;->nT()V'
HEAD = '.method public final nS()V'

nt = [l for l in lines if l.strip() == '.method private nT()V']
assert len(nt) == 1, 'nT()V not found once'
# nT must be the cache wipe (the one disconnected() calls), not some other method
dis = [i for i, l in enumerate(lines) if l.strip() == '.method public final disconnected()V']
assert len(dis) == 1
dend = next(j for j in range(dis[0], len(lines)) if lines[j].strip() == '.end method')
assert CALL in lines[dis[0]:dend], 'disconnected() does not call nT() here'

idx = [i for i, l in enumerate(lines) if l.strip() == HEAD]
assert len(idx) == 1, 'method not found once: ' + HEAD
i = idx[0]
end = next(j for j in range(i, len(lines)) if lines[j].strip() == '.end method')
body = lines[i:end]
assert 'stopTurnByTurn()' in '\n'.join(body), 'nS is not stopTurnByTurn here'
if CALL in body:
    print('already hooked:', HEAD)
    sys.exit(0)
# after the lane clear that update 23 put first in nS (or the first instruction)
at = None
for j in range(i + 1, end):
    s = lines[j].strip()
    if 'LeafiaCpLane;->clear()V' in s:
        at = j + 1
        break
if at is None:
    for j in range(i + 1, end):
        s = lines[j].strip()
        if s and not s.startswith('.') and not s.startswith('#'):
            at = j
            break
assert at is not None
lines[at:at] = ['', '    # Leafia G70: the iPhone moved the turns to another app - drop the old app\'s cached',
                '    # guidance and the phone-guiding mark, as a disconnect does', CALL]
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
print('hooked:', HEAD)
