package com.google.android.projection.leafia;

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
    /** metres before the turn where the bar starts to shrink (about 1000 ft) */
    public static final float WINDOW_M = 300f;

    private LeafiaBar() {
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

    /** barGraphLevel 0..100 in steps of 10 for this distance; 100 when it can't be told */
    public static int level(float d, int unit) {
        float m = meters(d, unit);
        if (m < 0f) return 100;
        int l = (int) Math.ceil(m * 10f / WINDOW_M);
        return Math.max(0, Math.min(10, l)) * 10;
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
    }
}
