#!/usr/bin/env python3
"""Rewrite a package's NEMESIS.data in the store format (descriptor 1.1, see the NEMESIS docs
04-Packages.md and 07-Submit-a-Package.md). Keeps the hooks and the [app.0] status entry.

usage: store_descriptor.py <pkg dir> bridge|tbt
os is matched against ro.build.product, models against the last part of ro.mobis.targetdir
(G70: ikfl_us, Stinger: ckpe23_us).
"""
import os, sys

# packages that patch the same apps or system files (NEMESIS's own projection packages and ours)
OTHERS = ['wireless.projection', 'wireless.carplay.aa', 'projection.tbt', 'enhanced.projection', 'carplay.session']

PKGS = {
    'bridge': dict(
        id='g70.carplay.bt',
        name='G70 Wireless CarPlay / Android Auto',
        version='1.4',
        short='Wireless CarPlay/AA, turn-by-turn on the HUD and cluster',
        detail=('Wireless CarPlay and Android Auto for the Genesis G70, with the phone\'s turn-by-turn, '
                'lanes and approach bar on the HUD and cluster. Firmware 251120, 250818, 260507; '
                'it picks the build made for your files. Uninstall restores stock.'),
        os=['IKFL.USA.*.251120', 'IKFL.USA.*.250818', 'IKFL.USA.*.260507'],
        models=['ikfl_*'],
        depends=['!g70.tbt'] + ['!' + o for o in OTHERS],
    ),
    'tbt': dict(
        id='stinger.tbt',
        name='Kia Stinger turn-by-turn',
        version='1.1',
        short='Phone turn-by-turn on the Stinger HUD and cluster',
        detail=('CarPlay and Android Auto turn-by-turn, lanes and approach bar on the Kia Stinger\'s HUD '
                'and cluster, with wired projection or a wireless dongle. Firmware 251120, 260507. '
                'Does not add wireless. Uninstall restores stock.'),
        os=['CKPE23.USA.*.251120', 'CKPE23.USA.*.260507'],
        models=['ckpe23_*'],
        depends=['!g70.carplay.bt', '!g70.tbt'] + ['!' + o for o in OTHERS if o not in ('wireless.projection', 'wireless.carplay.aa')],
    ),
}


def main():
    pkg, kind = sys.argv[1], sys.argv[2]
    p = PKGS[kind]
    assert len(p['short']) <= 64, len(p['short'])
    assert len(p['detail']) <= 256, len(p['detail'])
    nd = os.path.join(pkg, 'NEMESIS.data')
    old = open(nd).read()
    ids = {'bridge': ['g70.carplay.bt'], 'tbt': ['g70.tbt', 'stinger.tbt']}[kind]
    assert any(('id=' + i + '\n') in old for i in ids), 'wrong package for ' + kind
    t = '\n'.join([
        '[nemesis]',
        'version=1.1',
        'id=' + p['id'],
        'name=' + p['name'],
        'type=application',
        'package-version=' + p['version'],
        'short-desc="%s"' % p['short'],
        'detailed-desc="%s"' % p['detail'],
        'os="%s"' % ','.join(p['os']),
        'models="%s"' % ','.join(p['models']),
        'depends="%s"' % ','.join(p['depends']),
        'preinstall=scripts/pre.sh',
        'postinstall=scripts/post.sh',
        'preuninstall=scripts/preun.sh',
        '',
        '[app.0]',
        'kind=sh',
        'path=bin/status.sh',
        'uid=root',
        '',
    ])
    open(nd, 'w', newline='\n').write(t)
    print(t)


if __name__ == '__main__':
    main()
