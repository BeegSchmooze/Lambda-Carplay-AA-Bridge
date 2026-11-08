# Ports the G70 Android Auto turn-by-turn library patch (build_g70_lib.py, made for the 251120
# library) to another build of libautoreceiver_infobank.so. The added segment (from approx.so) only
# reaches the library through its relative table, so a port re-points that table and the three
# hook sites at the other build's addresses (found by mapaddr.py / blmap.py: exported symbols, and
# call sites for the two internal string helpers), and puts that build's own program headers in.
# usage: build_lib_port.py <stock lib> <expected md5> <out> <port name>
import struct, hashlib, sys
STOCK, MD5, OUT, PORT = sys.argv[1:5]
PORTS = {
    # the original (build_g70_lib.py): must reproduce libautoreceiver_infobank.g70tbt.so
    'g70-251120': dict(
        nextTurn=0xaef3e, nextTurnDist=0xaeeae, rangeInit=0xa64dc, dealloc=0xa6454,
        routeRet=0xbccb4, routeHook=0xbccb0, version=0xb7d3e, rds=0x144e9a),
    # 2023 G70, IKFL.USA.0000.V014.010.250818
    'g70-250818': dict(
        nextTurn=0xa8014, nextTurnDist=0xa7f5e, rangeInit=0xa7cbc, dealloc=0xa68d0,
        routeRet=0xb3910, routeHook=0xb390c, version=0xb464a, rds=0x144e5a),
    # G70 on IKFL.USA.0000.V015.012.260507 (2026.07); dealloc is the same _M_deallocate_block with
    # the node allocator inlined (buffer at this+0x14 vs the inline one)
    'g70-260507': dict(
        nextTurn=0xa71c8, nextTurnDist=0xa7112, rangeInit=0xa6bf8, dealloc=0xa6bd8,
        routeRet=0xb681c, routeHook=0xb6818, version=0xb1a2e, rds=0x144efa),
}
# Kia Stinger CKPE23.USA.0000.V014.011.251120: its library is byte-identical to the 250818 one
# (md5 147dac01...), the expected-md5 argument still checks that
PORTS['stinger-251120'] = PORTS['g70-250818']
# Kia Stinger CKPE23.USA.0000.V015.012.260507: library byte-identical to the G70 260507 one (48ee793a)
PORTS['stinger-260507'] = PORTS['g70-260507']
# variants of a port (e.g. g70-260507-nocam) use that port's library
A = PORTS[PORT.replace('-nocam', '')]
g = bytearray(open(STOCK, 'rb').read())
assert hashlib.md5(g).hexdigest() == MD5, 'not the expected stock library'
import os
ap = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'approx.so'), 'rb').read()
SEG = 0x1c4000; END = 0x1c56ca
# the new segment must start past everything the library maps
for k in range(struct.unpack_from('<H', g, 0x2c)[0]):
    t, off, va, pa, fs, ms = struct.unpack_from('<6I', g, 0x34 + 32 * k)
    assert va + ms <= SEG, 'segment overlaps phdr %d' % k
assert len(g) <= SEG
out = bytearray(g)
struct.pack_into('<I', out, 0x1c, SEG); struct.pack_into('<H', out, 0x2c, 9)
out += b'\0' * (SEG - len(out))
seg = bytearray(ap[SEG:END])
# this build's 8 program headers, PT_PHDR moved, plus the new R+X PT_LOAD
ph = bytearray(g[0x34:0x34 + 8 * 32])
assert struct.unpack_from('<I', ph, 0)[0] == 6, 'first phdr is not PT_PHDR'
struct.pack_into('<IIIIIIII', ph, 0, 6, SEG, SEG, SEG, 0x120, 0x120, 4, 4)
ph += struct.pack('<IIIIIIII', 1, SEG, SEG, SEG, END - SEG, END - SEG, 5, 0x1000)
seg[:0x120] = ph
fix = {0x1c437e: '704700207047' + '38b50446',
       0x1c4418: '4ff0ff3005b0bde8f08f', 0x1c44a4: '4ff0ff3005b0bde8f08f',
       0x1c47dd: 'f1000918bf4ff00109',
       0x1c56b8: '00' + b'0123456789abcdef'.hex() + '00'}
for a, h in fix.items():
    b = bytes.fromhex(h); seg[a - SEG:a - SEG + len(b)] = b
T = 0x1c4160
tab = [A['nextTurn'] | 1, A['nextTurnDist'] | 1, A['rangeInit'] | 1, A['dealloc'] | 1, A['routeRet'] | 1]
for i, t in enumerate(tab):
    struct.pack_into('<i', seg, T - SEG + 4 * i, t - T)
out += seg
assert out[A['version']:A['version'] + 2] == bytes.fromhex('0426'); out[A['version']] = 0x06
assert out[A['rds']:A['rds'] + 2] == bytes.fromhex('0228'); out[A['rds']] = 0x03
assert out[A['routeHook']:A['routeHook'] + 4] == bytes.fromhex('6ff0fc04')
assert out[A['nextTurn']:A['nextTurn'] + 4] == bytes.fromhex('a0f11000')
assert out[A['nextTurnDist']:A['nextTurnDist'] + 4] == bytes.fromhex('a0f11000')
def bw(src, dst):
    off = dst - (src + 4); s = 1 if off < 0 else 0; off &= 0x1ffffff
    i1 = (off >> 23) & 1; i2 = (off >> 22) & 1; j1 = (~(i1 ^ s)) & 1; j2 = (~(i2 ^ s)) & 1
    hi = 0xf000 | (s << 10) | ((off >> 12) & 0x3ff); lo = 0x9000 | (j1 << 13) | (j2 << 11) | ((off >> 1) & 0x7ff)
    return struct.pack('<HH', hi, lo)
out[A['routeHook']:A['routeHook'] + 4] = bw(A['routeHook'], 0x1c4120)
open(OUT, 'wb').write(out)
print(len(out), hashlib.md5(out).hexdigest())
