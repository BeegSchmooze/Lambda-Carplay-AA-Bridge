"""Stinger test 8: register svc/appleie.sh as a root NEMESIS service in the package's NEMESIS.data.
Service entries use the 1.1 header (as in the third-party service packages).
usage: nemesis_data.py <pkg>/NEMESIS.data"""
import sys

p = sys.argv[1]
s = open(p, newline='').read()
if '[service.0]' not in s:
    assert 'version=1.0\n' in s and 'types=application\n' in s, 'unexpected NEMESIS.data header'
    s = s.replace('version=1.0\n', 'version=1.1\n', 1)
    s = s.replace('types=application\n', 'type=application,service\nos="*.260507"\nmodels=any\n', 1)
    s = s.rstrip('\n') + '\n\n[service.0]\nname=appleie\nkind=sh\npath=svc/appleie.sh\nuid=root\nmode=restart\n'
    open(p, 'w', newline='').write(s)
assert 'type=application,service' in s and 'path=svc/appleie.sh' in s
assert '\r' not in s
