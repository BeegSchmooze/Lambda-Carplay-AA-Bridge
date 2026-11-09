"""Update 25: the HUD approach bar. Patches a GPM tree (LeafiaAaTurns.sendTurn: bar 32 ->
LeafiaBar.level(distance, unit)) and/or a DiPO tree (LeafiaCpTurn.updateTBTInfo: bar/barErr ->
LeafiaBar.cp/cpErr just before the NavigationCluster call). LeafiaBar.smali must already be in
the tree (aa-port/bar/build_bar.sh copies it). Idempotent: a patched tree is left alone.
usage: hooks25_bar.py gpm <tree> | dipo <tree>"""
import os, sys

kind, tree = sys.argv[1], sys.argv[2]

if kind == 'gpm':
    p = os.path.join(tree, 'com/google/android/projection/leafia/LeafiaAaTurns.smali')
    s = open(p).read()
    if 'LeafiaBar;->level' in s:
        print('gpm: already patched'); sys.exit(0)
    i = s.index('.method sendTurn()V')
    j = s.index('.end method', i)
    body = s[i:j]
    old = '    const/16 v8, 0x20\n'
    assert body.count(old) == 1, 'gpm: bar constant not found once'
    new = ('    iget v0, p0, Lcom/google/android/projection/leafia/LeafiaAaTurns;->distance:F\n\n'
           '    iget v1, p0, Lcom/google/android/projection/leafia/LeafiaAaTurns;->unit:I\n\n'
           '    invoke-static {v0, v1}, Lcom/google/android/projection/leafia/LeafiaBar;->level(FI)I\n\n'
           '    move-result v8\n')
    s = s[:i] + body.replace(old, new) + s[j:]
    assert os.path.exists(os.path.join(tree, 'com/google/android/projection/leafia/LeafiaBar.smali'))
elif kind == 'dipo':
    p = os.path.join(tree, 'com/daudio/app/dipo/LeafiaCpTurn.smali')
    s = open(p).read()
    if 'LeafiaBar;->cp' in s:
        print('dipo: already patched'); sys.exit(0)
    old = ('    move/from16 v10, p9\n\n'
           '    .line 190\n'
           '    invoke-virtual/range {v1 .. v10}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTInfo(IIFFIIIII)V\n')
    assert s.count(old) == 1, 'dipo: call site not found once'
    # v5 dist, v6 distErr, v8 unit, v9 bar, v10 barErr
    new = ('    move/from16 v10, p9\n\n'
           '    invoke-static {v5, v6, v8, v9}, Lcom/daudio/app/dipo/LeafiaBar;->cp(FIII)I\n\n'
           '    move-result v9\n\n'
           '    invoke-static {v5, v6, v8, v10}, Lcom/daudio/app/dipo/LeafiaBar;->cpErr(FIII)I\n\n'
           '    move-result v10\n\n'
           '    .line 190\n'
           '    invoke-virtual/range {v1 .. v10}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTInfo(IIFFIIIII)V\n')
    s = s.replace(old, new)
    assert os.path.exists(os.path.join(tree, 'com/daudio/app/dipo/LeafiaBar.smali'))
else:
    sys.exit('kind must be gpm or dipo')
open(p, 'w', newline='\n').write(s)
print(kind + ': patched ' + p)
