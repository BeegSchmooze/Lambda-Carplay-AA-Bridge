/*
 * Genesis G70 bridge, update 26: CarPlay turns that stock DiPO drops.
 *
 * DiPO's route guidance analyzer (e/u) looks the iPhone's maneuver up in a fixed table before
 * it sends anything to the cluster. Left and right turns map only with an exact junction exit
 * angle (left: -120/-90/-60/-45, right: 45/60/90/120); keep left / keep right never map. With
 * no match e/u sends nothing, so the cluster and HUD keep showing the car navigation's compass.
 * Newer iPhones leave the exit angle out of most maneuvers (2026-11 tester logs: Apple Maps on
 * iOS 27.1 sent it for 17 of 259 maneuvers, Google Maps for none; an iOS 16.2 phone sends it), so
 * their turns never reached the cluster.
 *
 * e/u calls unmapped() where its table found nothing. When LeafiaCpTurn can draw the maneuver
 * itself (drawn() != null), we return a placeholder display type that e/u sends as usual;
 * LeafiaCpTurn.updateTBTInfo then replaces it with the drawn turn. Anything LeafiaCpTurn does not
 * draw stays unsent, as in stock.
 *
 * GPL-3.0 (Genesis G70 bridge).
 */
package com.daudio.app.dipo;

import android.util.Log;

public final class LeafiaCpGap {
    /** a display type e/u sends for US cars (left turn); always replaced by LeafiaCpTurn */
    static final int PLACEHOLDER = 0x46;
    static int sLastLogged = Integer.MIN_VALUE;

    private LeafiaCpGap() {
    }

    /** e/u found no display type for the current maneuver: the placeholder, or 0 to send nothing */
    public static int unmapped() {
        try {
            Object m = LeafiaCpTurn.sCurrent;
            if (m == null) return 0;
            int maneuver = LeafiaCpTurn.intField(m, "Dx|DM", -1);
            int junction = LeafiaCpTurn.intField(m, "DD|DS", -1);
            int exit = LeafiaCpTurn.intField(m, "DF|DU", 0);
            int[] d = LeafiaCpTurn.drawn(maneuver, junction, exit, null, 1);
            int key = maneuver * 1000 + junction * 10 + (d == null ? 0 : 1);
            if (key != sLastLogged) {
                sLastLogged = key;
                Log.i(LeafiaCpTurn.TAG, "Leafia: CarPlay maneuver " + maneuver + " junction " + junction + " exit " + exit
                        + (d == null ? " not in DiPO's table - not sent (as stock)" : " not in DiPO's table - sent as a drawn turn"));
            }
            return d == null ? 0 : PLACEHOLDER;
        } catch (Throwable t) {
            return 0;
        }
    }
}
