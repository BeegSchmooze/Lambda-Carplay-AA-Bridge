package com.mnsoft.navi;

import android.os.Parcel;

import com.hkmc.cluster.NavigationCluster;

/**
 * Genesis G70 bridge, update 26: the HUD approach bar while the phone guides.
 *
 * The HUD draws its approach bar from the trap frame's barGraphLevel (NaviTbtTrapInfo, 0-100, the
 * "TBT_BarGraph100Level" signal), not from the turn frame. Only this navigation sends trap frames:
 * with its own route it counts 100 -> 10 toward the turn (drive log 2026-10-31); with no route it
 * sends 100 or 0, and it kept doing that while the phone guided, so the bar never moved.
 *
 * Every trap frame this navigation sends goes through send(): the latest one is kept (a copy).
 * While the phone guides (sys.leafia.phonetbt fresh, same rule as LeafiaTbtMute) its bar is
 * replaced by the phone's level (sys.leafia.phonebar, from LeafiaBar in GPM / DiPO), and a
 * background thread re-sends the kept frame whenever that level changes. When the phone stops,
 * the navigation's own bar is sent back once. Every other field of the frame (speed limit,
 * cameras, toll gate) is the navigation's own, unchanged.
 *
 * GPL-3.0 (Genesis G70 bridge).
 */
public final class LeafiaTrapBar {
    static final String TAG = "LeafiaTBT";
    static final long FRESH_S = 90;

    static NavigationCluster sCluster;
    static NavigationCluster.NaviTbtTrapInfo sLast;
    static int sSent = -1;
    static Thread sThread;

    private LeafiaTrapBar() {
    }

    /** the phone's bar 0-100 while it guides, else -1 */
    public static int phoneBar(long stampS, long nowS, String bar) {
        if (stampS <= 0 || nowS - stampS >= FRESH_S || nowS < stampS) return -1;
        try {
            int b = Integer.parseInt(bar.trim());
            return b >= 0 && b <= 100 ? b : -1;
        } catch (Throwable t) {
            return -1;
        }
    }

    static String prop(String k) {
        try {
            Object v = Class.forName("android.os.SystemProperties")
                    .getMethod("get", String.class, String.class).invoke(null, k, "");
            return v == null ? "" : (String) v;
        } catch (Throwable t) {
            return "";
        }
    }

    static int phoneBar() {
        long stamp;
        try {
            stamp = Long.parseLong(prop("sys.leafia.phonetbt").trim());
        } catch (Throwable t) {
            return -1;
        }
        return phoneBar(stamp, android.os.SystemClock.elapsedRealtime() / 1000, prop("sys.leafia.phonebar"));
    }

    static NavigationCluster.NaviTbtTrapInfo copy(NavigationCluster.NaviTbtTrapInfo i) {
        Parcel p = Parcel.obtain();
        try {
            i.writeToParcel(p, 0);
            p.setDataPosition(0);
            return new NavigationCluster.NaviTbtTrapInfo(p);
        } finally {
            p.recycle();
        }
    }

    static void log(String s) {
        try {
            android.util.Log.i(TAG, "Leafia: " + s);
        } catch (Throwable t) {
            // off the car
        }
    }

    /** stands in for c.updateTBTTrapInfoNew(i) */
    public static void send(NavigationCluster c, NavigationCluster.NaviTbtTrapInfo i) {
        NavigationCluster.NaviTbtTrapInfo out = i;
        try {
            if (c != null && i != null) {
                NavigationCluster.NaviTbtTrapInfo keep = copy(i);
                int b = phoneBar();
                if (b >= 0) {
                    out = copy(i);
                    out.barGraphLevel = b;
                }
                synchronized (LeafiaTrapBar.class) {
                    sCluster = c;
                    sLast = keep;
                    sSent = out.barGraphLevel;
                    start();
                }
            }
        } catch (Throwable t) {
            out = i;
        }
        c.updateTBTTrapInfoNew(out);
    }

    static void start() {
        if (sThread != null) return;
        sThread = new Thread("LeafiaTrapBar") {
            @Override
            public void run() {
                boolean phone = false;
                while (true) {
                    try {
                        Thread.sleep(1000);
                        tick();
                        boolean p = phoneBar() >= 0;
                        if (p != phone) {
                            phone = p;
                            log(p ? "phone guidance: HUD approach bar from the phone" : "phone guidance over: HUD approach bar back to the navigation");
                        }
                    } catch (Throwable t) {
                        // keep going
                    }
                }
            }
        };
        sThread.setDaemon(true);
        sThread.start();
    }

    /** re-send the kept frame when the bar it should carry changed */
    static void tick() {
        NavigationCluster c;
        NavigationCluster.NaviTbtTrapInfo out;
        synchronized (LeafiaTrapBar.class) {
            if (sCluster == null || sLast == null) return;
            int b = phoneBar();
            int want = b >= 0 ? b : sLast.barGraphLevel;
            if (want == sSent) return;
            out = copy(sLast);
            out.barGraphLevel = want;
            sSent = want;
            c = sCluster;
        }
        c.updateTBTTrapInfoNew(out);
    }

    /** off-car check: java com.mnsoft.navi.LeafiaTrapBar */
    public static void main(String[] a) {
        int f = 0;
        f += t("fresh, 60", phoneBar(100, 110, "60") == 60);
        f += t("fresh, 0", phoneBar(100, 189, "0") == 0);
        f += t("stale (90 s)", phoneBar(100, 190, "60") == -1);
        f += t("never set", phoneBar(0, 110, "60") == -1);
        f += t("cleared (0)", phoneBar(0, 5, "") == -1);
        f += t("bad value", phoneBar(100, 110, "x") == -1);
        f += t("out of range", phoneBar(100, 110, "254") == -1);
        f += t("clock went back", phoneBar(100, 50, "60") == -1);
        System.out.println(f == 0 ? "ALL PASS" : f + " FAILED");
    }

    static int t(String what, boolean ok) {
        System.out.println((ok ? "ok   " : "FAIL ") + what);
        return ok ? 0 : 1;
    }
}
