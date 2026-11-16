"""Update 27a: DipoService.onCreate starts LeafiaHotspot (keeps the projection hotspot on: about
20 s after start and whenever a Bluetooth device connects). LeafiaHotspot*.smali must already be
in the tree. Idempotent.  usage: hooks27_hotspot.py <DiPO smali tree>"""
import os, sys

tree = sys.argv[1]
p = os.path.join(tree, 'com/daudio/app/dipo/service/DipoService.smali')
s = open(p, encoding='utf-8').read()
CALL = 'Lcom/daudio/app/dipo/LeafiaHotspot;->init(Landroid/content/Context;)V'
if CALL in s:
    print('already hooked:', p); sys.exit(0)
assert os.path.exists(os.path.join(tree, 'com/daudio/app/dipo/LeafiaHotspot.smali'))
head = '.method public onCreate()V\n'
assert s.count(head) == 1
i = s.index(head)
body = s[i:s.index('.end method', i)]
sup = '    invoke-super {p0}, Lcom/hkmc/app/HKMCService;->onCreate()V\n'
assert body.count(sup) == 1, 'onCreate without the expected super call'
regs = int(body.split('.registers', 1)[1].split()[0])
assert regs <= 16, 'p0 not addressable by invoke-static {p0}'
j = i + body.index(sup) + len(sup)
ins = ('\n    # Leafia G70 (update 27a): keep the projection hotspot on\n'
       '    invoke-static {p0}, ' + CALL + '\n')
s = s[:j] + ins + s[j:]
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('hooked:', p)
