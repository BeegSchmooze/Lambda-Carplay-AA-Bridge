#!/usr/bin/env python3
"""Give the Stinger turn-by-turn package its own id, stinger.tbt (it was g70.tbt, the id of the
G70 turn-by-turn package it was ported from). Rewrites the package scripts in place (idempotent):
the id, its backup/build/log paths, the on-screen messages and the USB-drive file name, and adds a
refusal while the old g70.tbt is installed (NEMESIS sees a different id as another package, so
the old one has to be uninstalled first; its backup folder marks it as installed).

usage: stinger_id.py <pkg dir>
"""
import os, re, sys

pkg = sys.argv[1]
sc = os.path.join(pkg, 'scripts')


def edit(name, fn):
    p = os.path.join(sc, name)
    s = open(p).read()
    t = fn(s)
    open(p, 'w', newline='\n').write(t)


def common(s):
    if 'PKG=stinger.tbt' in s:
        return s
    for a, b in [
        ('# g70.tbt - ', '# stinger.tbt - '),
        ('PKG=g70.tbt\n', 'PKG=stinger.tbt\n'),
        ('/data/nemesis/backup/g70.tbt', '/data/nemesis/backup/stinger.tbt'),
        ('/data/nemesis/build/g70.tbt', '/data/nemesis/build/stinger.tbt'),
        ('/data/nemesis/g70.tbt.log', '/data/nemesis/stinger.tbt.log'),
        ('/data/nemesis/g70.tbt.stopped', '/data/nemesis/stinger.tbt.stopped'),
        ("grep -q 'g70\\.tbt\\.zip'", "grep -q 'stinger\\.tbt\\.zip'"),
    ]:
        assert a in s, a
        s = s.replace(a, b)
    assert 'g70.tbt' not in s, re.findall(r'.*g70\.tbt.*', s)
    old = 'BRIDGE_BACKUP=/data/nemesis/backup/g70.carplay.bt\n'
    assert s.count(old) == 1
    s = s.replace(old, old + '# the same package under its earlier id (v1.0 and the test builds)\n'
                  'OLD_TBT_BACKUP=/data/nemesis/backup/g70.tbt\n')
    old = '''    if [ -d "$BRIDGE_BACKUP" ]; then
        log "FAIL: the G70 bridge (g70.carplay.bt) is installed and already includes turn-by-turn - uninstall it first to use this package instead"
        return 1
    fi
'''
    assert s.count(old) == 1
    s = s.replace(old, old + '''    if [ -d "$OLD_TBT_BACKUP" ]; then
        log "FAIL: the earlier Stinger turn-by-turn (g70.tbt) is installed - uninstall it first (NEMESIS Manager, My Packages, g70.tbt), restart, then install this"
        return 1
    fi
''')
    return s


def pre(s):
    if 'OLD_TBT_BACKUP' in s:
        return s
    s = s.replace('G70 turn-by-turn', 'Stinger turn-by-turn')
    old = 'if ! check_unit; then\n'
    assert s.count(old) == 1
    return s.replace(old, '''if [ -d "$OLD_TBT_BACKUP" ]; then
    log "FAIL: the earlier Stinger turn-by-turn (g70.tbt) is installed"
    toast "Stinger turn-by-turn: uninstall the earlier version (g70.tbt) in NEMESIS Manager first, restart, then install this. Nothing was changed."
    exit 1
fi
''' + old)


edit('common.sh', common)
edit('pre.sh', pre)
for f in os.listdir(sc) + ['../bin/status.sh']:
    edit(f, lambda s: s.replace('G70 turn-by-turn', 'Stinger turn-by-turn'))
print('stinger.tbt:', pkg)
