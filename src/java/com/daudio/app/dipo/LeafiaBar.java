package com.daudio.app.dipo;

/**
 * Genesis G70 bridge: the HUD / cluster approach bar (updateTBTInfo's barGraphLevel) the way the
 * car's own navigation fills it. The navigation engine hands its frame a level 0-10 and
 * HKMC_Navi_ExSL sends level x 10 (e/a.c([I): 14 -> 0 with error -2, 15 -> 0 with error -1).
 * Stock wired Android Auto (GpmNaviTBTManager) always sends 32 and stock CarPlay (DiPO e/u)
 * always sends 0, so the bar never moved with the phone guiding. Here: full until WINDOW_M
 * before the turn, then one step down per tenth of it, empty at the turn.
 * Same file for GPM and DiPO (package filled in by aa-port/bar/build_bar.sh).
 */
public final class LeafiaBar {
    /**
     * metres before the turn where the bar starts to shrink. 500 m matches the car's own navigation
     * (drive log 2026-10-31: 90 at 0.3 mi, 80 at 0.2 mi, 60 at 900 ft, 10 at 100 ft).
     */
    public static final float WINDOW_M = 500f;

    /**
     * Update 26: the HUD draws its approach bar from the trap frame's barGraphLevel (0-100), which
     * only the car's navigation sends. The level is published here; HKMC_Navi_ExSL's LeafiaTrapBar
     * puts it in that frame while the phone guides (sys.leafia.phonetbt fresh).
     */
    static final String BAR_PROP = "sys.leafia.phonebar";
    static int sPublished = -1;

    private LeafiaBar() {
    }

    static void publish(int l) {
        if (l == sPublished) return;
        sPublished = l;
        try {
            Class.forName("android.os.SystemProperties").getMethod("set", String.class, String.class)
                    .invoke(null, BAR_PROP, String.valueOf(l));
        } catch (Throwable t) {
            // off the car (or no permission): the TBT frame still carries the level
        }
    }

    /** metres for a NavigationCluster distance and unit (0 m, 1 km, 2 mi, 3 ft, 4 yd), or -1 */
    public static float meters(float d, int unit) {
        if (d < 0f || Float.isNaN(d) || Float.isInfinite(d)) return -1f;
        switch (unit) {
            case 0: return d;
            case 1: return d * 1000f;
            case 2: return d * 1609.344f;
            case 3: return d * 0.3048f;
            case 4: return d * 0.9144f;
            default: return -1f;
        }
    }

    /**
     * barGraphLevel for this distance, the way the car's own navigation sends it (drive log
     * 2026-10-31): 0 = no bar while the turn is farther than WINDOW_M (and when the distance can't
     * be told); inside it the bar appears at 90 and counts down in tens (10 just before the turn).
     * Update 27 (2026-11-15, owner: "the bar shouldn't appear until it starts counting"): before
     * this, far turns sent 100 (a full bar from far away).
     */
    public static int level(float d, int unit) {
        int l = levelOf(meters(d, unit));
        publish(l);
        return l;
    }

    static int levelOf(float m) {
        if (m <= 0f || m > WINDOW_M) return 0;
        int l = (int) Math.ceil(m * 10f / WINDOW_M);
        return Math.max(1, Math.min(9, l)) * 10;
    }

    /** CarPlay (DiPO e/u's call): our level for a valid distance, else DiPO's own bar */
    public static int cp(float d, int distErr, int unit, int bar) {
        if (distErr != 0 || meters(d, unit) < 0f) return bar;
        return level(d, unit);
    }

    /** CarPlay: the bar error that goes with cp() */
    public static int cpErr(float d, int distErr, int unit, int barErr) {
        if (distErr != 0 || meters(d, unit) < 0f) return barErr;
        return 0;
    }

    /** off-car check: java LeafiaBar */
    public static void main(String[] a) {
        float[][] cases = { { 2f, 2 }, { 0.3f, 2 }, { 0.2f, 2 }, { 1000f, 3 }, { 984f, 3 }, { 500f, 3 }, { 350f, 3 },
                { 100f, 3 }, { 0f, 3 }, { 300f, 0 }, { 150f, 0 }, { 29f, 0 }, { 1.2f, 1 }, { -1f, 0 }, { 5f, 15 } };
        for (float[] c : cases) {
            System.out.println(c[0] + " unit " + (int) c[1] + " -> " + level(c[0], (int) c[1]));
        }
        System.out.println("cp err -1 keeps bar: " + cp(100f, -1, 3, 0) + "/" + cpErr(100f, -1, 3, 0));
        System.out.println("cp 350 ft: " + cp(350f, 0, 3, 0) + "/" + cpErr(350f, 0, 3, 0));
        // the car's own navigation (2026-10-31 log): 0 far away, 90 at 0.3 mi, 80 at 0.2 mi, 60 at 900 ft, 10 at 100 ft
        int[][] want = { { 2000, 2, 0 }, { 400, 2, 0 }, { 32, 2, 0 }, { 28, 2, 90 }, { 22, 2, 80 }, { 900, 3, 60 },
                { 100, 3, 10 }, { 1, 3, 10 }, { 0, 3, 0 }, { -1, 3, 0 }, { 5, 15, 0 } };
        int f = 0;
        for (int[] w : want) {
            float d = w[1] == 2 ? w[0] / 100f : w[0];
            int got = level(d, w[1]);
            if (got != w[2]) {
                System.out.println("FAIL " + d + " unit " + w[1] + ": " + got + ", want " + w[2]);
                f++;
            }
        }
        System.out.println(f == 0 ? "ALL PASS" : f + " FAILED");
        if (f != 0) System.exit(1);
    }
}
