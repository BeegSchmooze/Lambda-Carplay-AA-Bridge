"""Re-merge a class merge.py merged onto the wrong file because the port renamed it (classmatch.py):
base/ours = <old path> in the base port's stock / our tree, theirs = <new path> in the port. The old
class name is rewritten to the new one in base and ours first; the old path in the output goes back
to the port's own stock class.
usage: merge_moved.py <base port> <ours prefix> <port> <tree> <app> <old rel path> <new rel path>"""
import os, re, shutil, subprocess, sys

W = '/work'
base_p, ours_p, port, tree, app, old, new = sys.argv[1:8]
COMMENT = re.compile(r'^\s*# (invokes|getter for|setter for|operator for):')


def clean(p):
    return '\n'.join(l for l in open(p, encoding='utf-8').read().replace('\r\n', '\n').split('\n') if not COMMENT.match(l))


oc = 'L' + old[:-len('.smali')] + ';'
nc = 'L' + new[:-len('.smali')] + ';'
b = clean('%s/ports/%s/smali/%s/%s' % (W, base_p, app, old)).replace(oc, nc)
o = clean('%s/build/%s-%s/%s' % (W, ours_p, tree, old)).replace(oc, nc)
t = clean('%s/ports/%s/smali/%s/%s' % (W, port, app, new))
out = '%s/build/%s-%s' % (W, port, tree)
tmp = '/tmp/merge-moved'
shutil.rmtree(tmp, ignore_errors=True)
os.makedirs(tmp)
for n, c in (('o', o), ('b', b), ('t', t)):
    open(tmp + '/' + n, 'w').write(c + '\n')
rc = subprocess.call(['git', 'merge-file', '-L', 'ours', '-L', 'base', '-L', 'theirs', tmp + '/o', tmp + '/b', tmp + '/t'])
shutil.copy(tmp + '/o', os.path.join(out, new))
shutil.copy('%s/ports/%s/smali/%s/%s' % (W, port, app, old), os.path.join(out, old))
print('%s -> %s: %s' % (old, new, 'merged clean' if rc == 0 else 'CONFLICTS %d' % rc))
# our other classes that name the old class
for root, _, fs in os.walk(out):
    for f in fs:
        p = os.path.join(root, f)
        if f.endswith('.smali') and p != os.path.join(out, old) and oc in open(p, encoding='utf-8').read():
            print('  still names %s: %s' % (oc, os.path.relpath(p, out)))
sys.exit(0 if rc == 0 else 1)
