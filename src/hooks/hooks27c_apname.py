"""Update 27c: the Wi-Fi network sent to the phone by Android Auto (GPM WirelessExplorer.getWiFiInfo)
and CarPlay (Iap2Service) comes from LeafiaApName.ssid()/psk() instead of the WifiConfiguration's
ConnectivitySSID / ConnectivityPSK fields (same value on firmware whose hotspot broadcasts them; the
broadcast name/password on firmware that doesn't, the Kia Stinger). LeafiaApName.smali
(com/leafia/wifi) must already be in the tree. Idempotent.
usage: hooks27c_apname.py <smali tree>  (a GPM or an Iap2ServerApp tree)"""
import os, re, sys

tree = sys.argv[1]
FILES = ['com/google/android/projection/protocol/WirelessExplorer.smali', 'com/tcc/iap2server/Iap2Service.smali']
CLS = 'Lcom/leafia/wifi/LeafiaApName;'
assert os.path.exists(os.path.join(tree, 'com/leafia/wifi/LeafiaApName.smali'))
pat = re.compile(r'^(\s*)iget-object (v\d+), (v\d+), Landroid/net/wifi/WifiConfiguration;->Connectivity(SSID|PSK):Ljava/lang/String;$', re.M)
done = 0
for rel in FILES:
    p = os.path.join(tree, rel)
    if not os.path.exists(p):
        continue
    s = open(p, encoding='utf-8').read()
    if CLS in s:
        print('already hooked:', rel); done += 1; continue

    def rep(m):
        ind, dst, src, which = m.groups()
        assert int(src[1:]) < 16 and int(dst[1:]) < 256
        meth = 'ssid' if which == 'SSID' else 'psk'
        return ('%s# Leafia G70 (update 27c): the network the hotspot really broadcasts\n'
                '%sinvoke-static {%s}, %s->%s(Landroid/net/wifi/WifiConfiguration;)Ljava/lang/String;\n\n'
                '%smove-result-object %s' % (ind, ind, src, CLS, meth, ind, dst))
    s2, n = pat.subn(rep, s)
    assert n == 2, '%s: expected 2 reads, found %d' % (rel, n)
    open(p, 'w', encoding='utf-8', newline='\n').write(s2)
    print('hooked:', rel, n)
    done += 1
assert done == 1, 'not a GPM or Iap2ServerApp tree'
