/*
 * Genesis G70 bridge: CarPlay turn-by-turn drawn like the built-in navigation.
 *
 * DiPO's route guidance analyzer (e/u) sends the iPhone's maneuver as a fixed cluster icon
 * with no direction and no side roads. The built-in navigation draws ordinary turns as
 * display type 13 (arrow from the direction, a road for every side-street bit), highway
 * exits as 17/18 and forks as 25 (libExSLNavi; confirmed on the G70 HUD). The iPhone sends
 * what that needs: the exit angle and the angle of every road at the junction
 * (RouteGuidanceManeuverUpdate JunctionElementExitAngle / JunctionElementAngle, kept by
 * DiPO in e/v). e/u's updateTBTInfo call goes through here; e/u reports the maneuver it
 * just looked up (current). Anything not recognised passes through unchanged. Also sends
 * the HUD distance (updateTBTSubInfo2C), which e/u never does.
 *
 * Angles: iAP2 gives -180..180 degrees; the side of positive angles is
 * persist.leafia.g70.cpangle (1: clockwise = right, the default; -1: the other way).
 *
 * GPL-3.0 (Genesis G70 bridge).
 */
package com.daudio.app.dipo;

import android.util.Log;

import com.hkmc.cluster.NavigationCluster;

import java.lang.reflect.Field;
import java.util.Arrays;

public final class LeafiaCpTurn {
    static final String TAG = "LeafiaCP";
    static final int DRAWN_TURN = 13, EXIT_RIGHT = 17, EXIT_LEFT = 18, DRAWN_FORK = 25;
    // iAP2 RouteGuidanceManeuverType
    static final int LEFT = 1, RIGHT = 2, KEEP_LEFT = 13, KEEP_RIGHT = 14, LEFT_AT_END = 20, RIGHT_AT_END = 21,
            OFF_RAMP_LEFT = 22, OFF_RAMP_RIGHT = 23, SHARP_LEFT = 47, SHARP_RIGHT = 48, SLIGHT_LEFT = 49, SLIGHT_RIGHT = 50;
    static final int JUNCTION_INTERSECTION = 0;

    /** the maneuver e/u is about to send (an e/v), its fields read by name */
    static volatile Object sCurrent;
    static String sLastLog;

    private LeafiaCpTurn() {
    }

    public static void current(Object maneuver) {
        sCurrent = maneuver;
    }

    static int sign() {
        try {
            Object v = Class.forName("android.os.SystemProperties").getMethod("get", String.class, String.class)
                    .invoke(null, "persist.leafia.g70.cpangle", "1");
            return "-1".equals(v) ? -1 : 1;
        } catch (Throwable t) {
            return 1;
        }
    }

    /** the first of the '|'-separated field names this firmware's e/v has (the obfuscated names shift) */
    static Object field(Object o, String names) {
        for (String name : names.split("\\|")) {
            try {
                Field f = o.getClass().getDeclaredField(name);
                f.setAccessible(true);
                return f.get(o);
            } catch (Throwable t) {
                // not this firmware's name
            }
        }
        return null;
    }

    static int intField(Object o, String name, int def) {
        Object v = field(o, name);
        return v instanceof Integer ? (Integer) v : def;
    }

    /** iAP2 angle (-180..180, sign as configured) to degrees clockwise from straight ahead (0..359) */
    static int clockwise(int a, int sign) {
        int d = (a * sign) % 360;
        return d < 0 ? d + 360 : d;
    }

    /**
     * The built-in navigation's side-street bits (libExSLNavi SetSideStreetBit): bit 0 a road
     * straight ahead (within 12 degrees), bits 1..7 the right side in 22.5 degree steps from
     * 12 degrees, bits 8..14 the left side from 192 degrees; the road behind (169..192) has no bit.
     */
    static int sideBit(int cw) {
        if (cw < 12 || cw > 348) return 1;
        int lo = 12;
        int bit = 1;
        for (int k = 0; k < 15; k++) {
            int hi = lo + (k % 2 == 0 ? 22 : 23);
            if (k != 7) {
                if (cw >= lo && cw < hi) return 1 << bit;
                bit++;
            }
            lo = hi;
        }
        return 0;
    }

    /** side roads: every junction road except the exit and the one we come in on */
    static int sideStreets(int[] angles, int exitCw, int sign) {
        if (angles == null) return 0;
        int bits = 0;
        for (int a : angles) {
            int cw = clockwise(a, sign);
            int diff = Math.abs(cw - exitCw);
            if (Math.min(diff, 360 - diff) < 12) continue;   // the exit itself
            bits |= sideBit(cw);
        }
        return bits & 0x7fff;
    }

    /** direction for a maneuver with no exit angle */
    static int defaultDirection(int m) {
        switch (m) {
            case LEFT: case LEFT_AT_END: return 270;
            case RIGHT: case RIGHT_AT_END: return 90;
            case SHARP_LEFT: return 225;
            case SHARP_RIGHT: return 135;
            case SLIGHT_LEFT: return 315;
            case SLIGHT_RIGHT: return 45;
            default: return -1;
        }
    }

    /** {type, side streets, direction} for the maneuver, or null to keep e/u's values */
    static int[] drawn(int maneuver, int junction, int exitAngle, int[] angles, int sign) {
        switch (maneuver) {
            case LEFT: case RIGHT: case LEFT_AT_END: case RIGHT_AT_END:
            case SHARP_LEFT: case SHARP_RIGHT: case SLIGHT_LEFT: case SLIGHT_RIGHT: {
                if (junction != JUNCTION_INTERSECTION) return null;
                int dir = defaultDirection(maneuver);
                int side = 0;
                if (exitAngle != 0 && exitAngle >= -180 && exitAngle <= 180) {
                    int cw = clockwise(exitAngle, sign);
                    // trust the angle only when it agrees with the maneuver's side
                    boolean right = maneuver == RIGHT || maneuver == RIGHT_AT_END || maneuver == SHARP_RIGHT || maneuver == SLIGHT_RIGHT;
                    if (right ? cw > 0 && cw < 180 : cw > 180) {
                        dir = cw;
                        side = sideStreets(angles, cw, sign);
                    }
                }
                return new int[] { DRAWN_TURN, side, dir };
            }
            case OFF_RAMP_RIGHT:
                return new int[] { EXIT_RIGHT, 0, 90 };
            case OFF_RAMP_LEFT:
                return new int[] { EXIT_LEFT, 0, 270 };
            case KEEP_RIGHT:
                return new int[] { DRAWN_FORK, 0, 45 };
            case KEEP_LEFT:
                return new int[] { DRAWN_FORK, 0, 315 };
            default:
                return null;
        }
    }

    /** e/u's NavigationCluster.updateTBTInfo call */
    public static void updateTBTInfo(NavigationCluster nc, int type, int side, float dir, float dist, int distErr,
            int combi, int unit, int bar, int barErr) {
        LeafiaCpLane.cluster(nc);
        try {
            Object m = sCurrent;
            if (m != null) {
                // e/v fields: 251120 / 250818 names | 260507 names (same class, renamed)
                int maneuver = intField(m, "Dx|DM", -1);
                int junction = intField(m, "DD|DS", -1);
                int exit = intField(m, "DF|DU", 0);
                Object a = field(m, "DE|DT");
                int[] angles = a instanceof int[] ? (int[]) a : null;
                int sign = sign();
                int[] d = drawn(maneuver, junction, exit, angles, sign);
                String log = "maneuver " + maneuver + " junction " + junction + " exit " + exit + " angles " + Arrays.toString(angles)
                        + " icon " + type + (d == null ? " (kept)" : " -> type " + d[0] + " dir " + d[2] + " side 0x" + Integer.toHexString(d[1]));
                if (!log.equals(sLastLog)) {
                    sLastLog = log;
                    Log.i(TAG, "Leafia: CarPlay turn " + log);
                }
                if (d != null) {
                    type = d[0];
                    side = d[1];
                    dir = d[2];
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "Leafia: CarPlay turn mapping failed: " + t);
        }
        // update 25: the HUD's approach bar (DiPO sends 0), filled as the car navigation does
        int bar0 = bar;
        bar = LeafiaBar.cp(dist, distErr, unit, bar0);
        barErr = LeafiaBar.cpErr(dist, distErr, unit, barErr);
        nc.updateTBTInfo(type, side, dir, dist, distErr, combi, unit, bar, barErr);
        try {
            // the HUD's distance (as the Android Auto path sends it)
            if (dist >= 0f && unit >= 0 && unit <= 4) {
                int whole = Math.min((int) dist, 4095);
                int tenths = unit == 1 || unit == 2 ? Math.max(0, Math.min(9, (int) ((dist - whole) * 10f + 0.5f))) : 0;
                nc.updateTBTSubInfo2C(unit, tenths, whole, 0, 0, 0, 0, 0, 0);
            }
        } catch (Throwable t) {
            Log.w(TAG, "Leafia: CarPlay HUD distance failed: " + t);
        }
    }
}
