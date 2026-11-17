/*
 * leafiaie: send one Android Wi-Fi driver private command (the "driver_cmd" path) and print the reply.
 *
 *   leafiaie <iface> <word>...        e.g.  leafiaie wlan0 add_ie 0 00A040 0000020021
 *   leafiaie -n <iface> <word>...     dry run: print the command, send nothing
 *
 * The G70's hostapd (260507, hostapd_add_carplay_ie) puts the wireless CarPlay Apple device IE in the
 * projection hotspot this way: snprintf "add_ie %d %s %s" (0 = beacon, 1 = probe response, 2 = assoc
 * response, OUI "00A040", apple_device_ie) and its nl80211 driver_cmd sends it with
 * ioctl(SIOCDEVPRIVATE + 1) on wlan0, ifr_data -> { buf, used_len = total_len = 512 }. The Stinger's
 * hostapd has no apple_device_ie option, so the Stinger's appleie service sends the same commands.
 *
 * Exit 0 when the driver accepted it (ioctl >= 0), 1 when it refused, 2 on bad arguments.
 * Freestanding ARM (raw syscalls, no libc), built by build.sh. GPL-3.0 (Genesis G70 bridge).
 */
#define BUFLEN 512
#define SIOCDEVPRIVATE_1 0x89F1

#if defined(__arm__)
static long sys3(long n, long a, long b, long c) {
    register long r7 __asm__("r7") = n;
    register long r0 __asm__("r0") = a;
    register long r1 __asm__("r1") = b;
    register long r2 __asm__("r2") = c;
    __asm__ volatile("svc #0" : "+r"(r0) : "r"(r7), "r"(r1), "r"(r2) : "memory");
    return r0;
}
#define NR_EXIT 1
#define NR_WRITE 4
#define NR_IOCTL 54
#define NR_SOCKET 281
#else
#error "ARM only"
#endif

struct priv_cmd { char *buf; int used_len; int total_len; };
struct ifreq_s { char name[16]; void *data; char pad[12]; };

static int slen(const char *s) { int n = 0; while (s[n]) n++; return n; }
static void out(const char *s) { sys3(NR_WRITE, 1, (long)s, slen(s)); }
static void outn(long v) {
    char b[24]; int i = 23; int neg = v < 0; unsigned long u = neg ? -v : v;
    b[i] = 0;
    do { b[--i] = '0' + u % 10; u /= 10; } while (u);
    if (neg) b[--i] = '-';
    out(b + i);
}
__attribute__((noreturn)) static void quit(int c) { sys3(NR_EXIT, c, 0, 0); for (;;) {} }

static char buf[BUFLEN];

int main(int argc, char **argv) {
    int a = 1, dry = 0, n = 0, i, j;
    struct ifreq_s ifr;
    struct priv_cmd pc;
    long fd, r;
    if (a < argc && argv[a][0] == '-' && argv[a][1] == 'n' && !argv[a][2]) { dry = 1; a++; }
    if (argc - a < 2) { out("usage: leafiaie [-n] <iface> <word>...\n"); return 2; }
    const char *ifn = argv[a++];
    if (slen(ifn) >= 16) { out("leafiaie: interface name too long\n"); return 2; }
    for (i = a; i < argc; i++) {
        int l = slen(argv[i]);
        if (n + l + 2 > BUFLEN) { out("leafiaie: command too long\n"); return 2; }
        if (i > a) buf[n++] = ' ';
        for (j = 0; j < l; j++) buf[n++] = argv[i][j];
    }
    buf[n] = 0;
    out("cmd: "); out(buf); out("\n");
    if (dry) return 0;
    for (i = 0; i < 16; i++) ifr.name[i] = 0;
    for (i = 0; ifn[i]; i++) ifr.name[i] = ifn[i];
    for (i = 0; i < 12; i++) ifr.pad[i] = 0;
    pc.buf = buf; pc.used_len = BUFLEN; pc.total_len = BUFLEN;
    ifr.data = &pc;
    fd = sys3(NR_SOCKET, 2 /* AF_INET */, 2 /* SOCK_DGRAM */, 0);
    if (fd < 0) { out("socket failed: "); outn(fd); out("\n"); return 1; }
    r = sys3(NR_IOCTL, fd, SIOCDEVPRIVATE_1, (long)&ifr);
    out("ret: "); outn(r); out("\n");
    buf[BUFLEN - 1] = 0;
    if (r >= 0 && buf[0]) { out("reply: "); out(buf); out("\n"); }
    return r >= 0 ? 0 : 1;
}

/* entry: sp -> argc, argv[0..], NULL (ARM EABI static, no libc) */
__attribute__((naked, noreturn)) void _start(void) {
    __asm__ volatile(
        "mov r0, sp\n"
        "bl start_c\n");
}
__attribute__((used, noreturn)) void start_c(long *sp) {
    quit(main((int)sp[0], (char **)(sp + 1)));
}
