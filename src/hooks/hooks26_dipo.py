"""Update 26: CarPlay turns stock DiPO drops (no junction exit angle; keep left/right).
In e/u's updateTBTInfo analyzer, the maneuver table's no-match branch (`move v1, v2` right after
`packed-switch v1, :pswitch_data_*`, which leaves display type 0 = send nothing) asks
LeafiaCpGap.unmapped() for a placeholder when LeafiaCpTurn can draw the maneuver itself.
LeafiaCpGap.smali must already be in the tree (aa-port/gap/build_gap.sh copies it).
Idempotent: a patched tree is left alone.
usage: hooks26_dipo.py <DiPO smali tree>"""
import os, sys

tree = sys.argv[1]
p = os.path.join(tree, 'com/daudio/app/dipo/e/u.smali')
lines = open(p, encoding='utf-8').read().split('\n')
CALL = '    invoke-static {}, Lcom/daudio/app/dipo/LeafiaCpGap;->unmapped()I'
if any(l == CALL for l in lines):
    print('already hooked:', p)
    sys.exit(0)
assert os.path.exists(os.path.join(tree, 'com/daudio/app/dipo/LeafiaCpGap.smali')), 'LeafiaCpGap.smali missing'

log = [i for i, l in enumerate(lines) if '"updateTBTInfo mManeuverType["' in l]
assert len(log) == 1, 'maneuver log not found once'
sw = next(i for i in range(log[0], log[0] + 200) if lines[i].strip().startswith('packed-switch v1, :pswitch_data_'))
code = [i for i in range(sw + 1, sw + 20) if lines[i].strip()]
c1, c2, mv, nxt = code[:4]
assert lines[c1].strip().startswith(':cond_'), lines[c1]
assert lines[c2].strip().startswith(':pswitch_'), lines[c2]
assert lines[mv].strip() == 'move v1, v2', lines[mv]
after = lines[nxt].strip()
assert after.startswith(':cond_'), after   # where the mapped cases continue (display type in v1)
lines[mv + 1:mv + 1] = [
    '',
    '    # Leafia G70 (update 26): no table entry (no exit angle from newer iPhones, keep left/right) -',
    '    # a placeholder when LeafiaCpTurn draws this maneuver itself, else 0 as stock',
    '    if-nez v1, ' + after,
    '',
    CALL,
    '',
    '    move-result v1',
]
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
print('hooked:', p, 'after line', mv + 1, '->', after)
