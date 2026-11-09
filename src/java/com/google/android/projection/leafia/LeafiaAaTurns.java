/*
 * Genesis G70 bridge: Android Auto turn-by-turn on the cluster and HUD.
 *
 * Port of HMG-API's AaTurns (VysseCodes, https://github.com/VysseCodes/HMG-API,
 * mods/wireless-carplay-aa, AGPL-3.0) to the G70's GPM: the same handling of the AA
 * library's callbacks (turn, distance, HUD turn list and distance, lanes, the turns
 * ahead, remaining distance and arrival time, destination name), sent straight to the
 * G70's NavigationCluster (LeafiaCluster) instead of HMG-API's hook API. It never sends
 * navigation alive or operation status.
 *
 * G70 additions (marked "G70:"):
 *  - this car's library maps Google's "head toward ..." start step to STRAIGHT; while the
 *    current step is straight and the phone has said what comes next, the cluster shows
 *    that next real maneuver (as the built-in navigation does);
 *  - a late phone distance never makes the count-down jump back up (BOUNCE_METERS);
 *  - between the phone's distance updates (about 1 s) the distance counts down from the
 *    car's speed, four times a second;
 *  - the car navigation's own turn frames stay muted while the phone guides
 *    (LeafiaTbtMark, read by the navigation app).
 *  - distance unit: the phone's (imperial/metric), since this build has no owner
 *    setting hook.
 *  - turns, exits and forks use the built-in navigation's drawn display types (13 turn,
 *    17/18 exit right/left, 25 fork: arrow drawn from the direction, side roads from the
 *    side-street bits) instead of fixed icons; the HUD turn list uses the built-in layout;
 *  - the cross name and the HUD turn list share one transport channel to the cluster, so
 *    they go out at least TP_GAP_MS apart (back to back the second cuts the first off).
 *
 * Everything runs on one thread (LeafiaAa's handler), in the order the callbacks came.
 *
 * AGPL-3.0 (derived from HMG-API).
 */
package com.google.android.projection.leafia;

import android.content.Context;
import android.os.Handler;
import android.os.SystemClock;
import android.text.format.DateFormat;
import android.util.Log;

import com.google.android.projection.sink.navigation.LeafiaTbtMark;

import java.util.Calendar;

final class LeafiaAaTurns {
    // AA protocol numbers (Protos.NavigationNextTurnEvent)
    static final int UNKNOWN = 0, DEPART = 1, NAME_CHANGE = 2, SLIGHT_TURN = 3, TURN = 4, SHARP_TURN = 5, U_TURN = 6,
            ON_RAMP = 7, OFF_RAMP = 8, FORK = 9, MERGE = 10, ROUNDABOUT_ENTER = 11, ROUNDABOUT_EXIT = 12,
            ROUNDABOUT_ENTER_AND_EXIT = 13, STRAIGHT = 14, FERRY_BOAT = 16, FERRY_TRAIN = 17, DESTINATION = 19;
    static final int LEFT = 1, RIGHT = 2, UNSPECIFIED = 3;
    static final int METERS = 1, KILOMETERS = 2, KILOMETERS_P1 = 3, MILES = 4, MILES_P1 = 5, FEET = 6, YARDS = 7;
    // the library's extra events and flags
    static final int EV_DEST_NAME = 32, EV_DUMP = 33, EV_LANES = 34, EV_AHEAD = 64, EV_AHEAD_END = 67;
    static final int FLAG_TRIP = 0x100, FLAG_AHEAD = 0x200, FLAG_POINT = 0x800;
    static final byte HUD_LIST = (byte) 0xF2, LANES = (byte) 0xF1;
    // owner's unit, as HMG-API's Car.distanceUnit (here: from the phone)
    static final int DISTANCE_KM = 0, DISTANCE_MILES = 1;
    // G70: count down between phone updates; a late phone value up to this much above
    // the estimate is ignored instead of making the number jump back up
    static final int BOUNCE_METERS = 150;
    static final long TICK_MS = 250, FRESH_MS = 200, STALE_MS = 4000;
    // G70: the built-in navigation's drawn display types (libExSLNavi SetCaseTurnPoint,
    // SetCaseExpExit); direction is degrees clockwise from straight ahead
    static final int DRAWN_TURN = 13, EXIT_RIGHT = 17, EXIT_LEFT = 18, DRAWN_FORK = 25;
    static final long TP_GAP_MS = 700;

    final Context context;
    final LeafiaCluster cluster;
    final Handler handler;
    final Runnable tick = new Runnable() {
        @Override
        public void run() {
            unitTick();
        }
    };
    final Runnable countdown = new Runnable() {
        @Override
        public void run() {
            countdownTick();
        }
    };

    // the next turn
    int event, turnSide, turnAngle, turnNumber, displayType, direction, unit;
    String road;
    float distance = -1f;   // G70: unknown until the phone's first distance
    boolean navLive;
    // G70: a new maneuver waits for its distance (it comes in the same phone update),
    // so it is never drawn with the previous turn's distance
    String turnKey;
    boolean awaitDistance;
    // destination and the remaining trip
    String destName;
    int estPoint;
    int tripMeters = -1, tripSeconds = -1, tripUnit, tripGen, sentGen;
    int lastUsm = -2;
    int usm = -1;
    // HUD turn list (what was sent last)
    int hudType = -1, hudNext;
    boolean hudFresh;
    String hudRoad, laneKey;
    // the turns ahead (index 0..2)
    final String[] aheadName = new String[3];
    final int[] aheadEv = new int[3], aheadSide = new int[3], aheadAng = new int[3], aheadExit = new int[3];
    final int[] aheadMeters = new int[3], aheadUnit = new int[3], aheadE3 = new int[3];
    final boolean[] aheadOk = new boolean[3];
    // G70: turns ahead seen at least once (kept across messages, for the first-turn shift)
    final boolean[] aheadKnown = new boolean[3];
    boolean shifted;
    // G70: transport channel pacing (cross name, HUD turn list)
    long tpFree;
    String crossSent;
    boolean hudListQueued;
    byte[] hudPending;   // the turn list frame that follows the clear frame
    final Runnable hudListRun = new Runnable() {
        @Override
        public void run() {
            hudListQueued = false;
            sendHudList();
        }
    };
    // G70: count-down
    int stepMeters = 0;      // distance to the turn now (phone value or estimate)
    int phoneMeters = -1;    // the phone's last value
    int phoneUnit;           // the phone's unit for it
    long phoneTime;          // when it came
    float sentDistance = -2f;
    int sentUnit = -1, sentType = -1;
    static volatile int speedKmh;

    LeafiaAaTurns(Context context, LeafiaCluster cluster, Handler handler) {
        this.context = context;
        this.cluster = cluster;
        this.handler = handler;
    }

    // ---- from the AA library

    void nextTurn(String str, int side, int ev, int angle, int number) {
        if (ev == EV_DUMP) {
            Log.d("NAVDUMP", String.valueOf(str));
            return;
        }
        if (ev == EV_LANES) {
            sendLanes(str);
            return;
        }
        if (ev == EV_DEST_NAME) {
            if (str == null || str.length() == 0) {
                destName = "";
                sendDestName();
                destName = null;
                return;
            }
            if (number >= 0) estPoint = number;
            if (!str.equals(destName)) {
                destName = str;
                sendDestName();
            }
            return;
        }
        if (ev == EV_AHEAD_END) {
            if (number > 0) sendAhead(Math.min(number, 3));
            return;
        }
        if (ev >= EV_AHEAD && ev < EV_AHEAD_END) {
            int k = ev - EV_AHEAD;
            aheadName[k] = str == null ? "" : str;
            aheadSide[k] = side;
            aheadAng[k] = angle;
            aheadEv[k] = number & 0xff;
            aheadExit[k] = (number >> 8) & 0xff;
            aheadOk[k] = false;
            aheadKnown[k] = true;
            return;
        }
        if (ev >= 32) return;   // any other library event: not a maneuver
        hudFresh = false;
        boolean first = road == null;
        // G70: a straight step ("head toward ..." from a standstill, or "continue"):
        // show the next real maneuver the phone told us about
        shifted = false;
        if (ev == STRAIGHT && aheadKnown[0] && isManeuver(aheadEv[0])) {
            ev = aheadEv[0];
            side = aheadSide[0];
            angle = aheadAng[0];
            number = aheadExit[0] == 255 ? -1 : aheadExit[0];
            str = aheadName[0];
            shifted = true;
        }
        event = ev;
        road = str;
        turnSide = side;
        turnAngle = angle;
        turnNumber = number;
        switch (ev) {
            case DEPART:
                if (first) {
                    cluster.destinationName(0, road);
                    distance = -1f;
                } else {
                    cross(road);
                    setTurnType(ev, turnSide);
                }
                break;
            case NAME_CHANGE: case SLIGHT_TURN: case TURN: case SHARP_TURN: case STRAIGHT: case MERGE:
                cross(road);
                setTurnType(ev, turnSide);
                break;
            case U_TURN:
                if (side == UNSPECIFIED) turnSide = LEFT;
                cross(road);
                setTurnType(ev, turnSide);
                break;
            case ON_RAMP: case OFF_RAMP: case FORK: case FERRY_BOAT:
                cross(road);
                setRampType(ev, turnSide);
                break;
            case ROUNDABOUT_EXIT: case ROUNDABOUT_ENTER_AND_EXIT:
                cross(road);
                setRoundaboutType(ev, turnSide, turnAngle);
                break;
            case DESTINATION:
                displayType = 3;
                break;
            case UNKNOWN:
                displayType = 64;
                break;
            default:
                return;   // ROUNDABOUT_ENTER, FERRY_TRAIN: not for the cluster
        }
        // G70: a different maneuver: draw it when its distance arrives
        String key = ev + "/" + turnSide + "/" + road;
        if (!key.equals(turnKey)) {
            turnKey = key;
            awaitDistance = true;
            return;
        }
        if (awaitDistance) return;
        sendTurn();
    }

    /** G70: a maneuver worth showing instead of a straight step */
    static boolean isManeuver(int ev) {
        switch (ev) {
            case SLIGHT_TURN: case TURN: case SHARP_TURN: case U_TURN: case ON_RAMP: case OFF_RAMP: case FORK:
            case MERGE: case ROUNDABOUT_EXIT: case ROUNDABOUT_ENTER_AND_EXIT: case FERRY_BOAT: case DESTINATION:
                return true;
            default:
                return false;
        }
    }

    void nextTurnDistance(int meters, int seconds, int e3, int unitFlags) {
        if ((unitFlags & FLAG_AHEAD) != 0) {
            int k = (unitFlags >> 10) & 3;
            if (k > 2) return;
            aheadMeters[k] = meters;
            aheadE3[k] = e3;
            aheadUnit[k] = unitFlags & 0xff;
            aheadOk[k] = true;
            return;
        }
        if ((unitFlags & FLAG_TRIP) != 0) {
            if ((unitFlags & FLAG_POINT) != 0) {
                int p = (unitFlags >> 12) & 15;
                estPoint = p > 4 ? 0 : p;
            }
            tripMeters = meters;
            tripSeconds = seconds;
            tripUnit = unitFlags & 0xff;
            tripGen++;
            sendRemain();
            return;
        }
        // G70: the phone's value arrives about once a second and a little late. While
        // moving toward the same turn, a phone value above the count-down's estimate is
        // stale: keep counting from the estimate so the number never bounces back up
        // (a much larger value, e.g. after a reroute, is taken as it is).
        int u = unitFlags & 0xff;
        if (!awaitDistance && speedKmh > 0 && phoneMeters >= 0 && meters > stepMeters
                && meters - stepMeters < BOUNCE_METERS) {
            meters = stepMeters;
            e3 = e3For(meters, u);
        }
        phoneMeters = meters;
        phoneUnit = u;
        phoneTime = SystemClock.elapsedRealtime();
        if (meters >= 0) stepMeters = meters;
        awaitDistance = false;
        setDistance(meters, e3, u);
        setTurnType(event, turnSide);
        sendTurn();
        scheduleCountdown();
    }

    void status(int s) {
        if (s == 1 || s == 3) {   // active, rerouting
            navLive = true;
            return;
        }
        handler.removeCallbacks(tick);
        handler.removeCallbacks(countdown);
        destName = null;
        navLive = false;
        tripMeters = -1;
        tripSeconds = -1;
        estPoint = 0;
        release();
    }

    /** The car's navigation took over (focus native): forget the turn. */
    void stop() {
        event = 0;
        road = null;
        turnSide = 0;
        turnAngle = 0;
        turnNumber = 0;
        unit = 0;
        displayType = 0;
        direction = 0;
        phoneMeters = -1;
        distance = -1f;
        turnKey = null;
        crossSent = null;
        handler.removeCallbacks(countdown);
    }

    /** The connection ended: clear what we showed, if a route was on. */
    void end() {
        handler.removeCallbacks(tick);
        handler.removeCallbacks(countdown);
        if (navLive) status(2);
    }

    // ---- the next turn

    void sendTurn() {
        if (!navLive) return;
        LeafiaTbtMark.mark();   // G70: keep the car navigation's turn frames muted
        // update 25: the HUD's approach bar, filled as the car navigation does (aa-port/bar)
        int bar = LeafiaBar.level(distance, unit), barErr = 0;
        if (distance < 0f) {
            bar = 254;
            barErr = -2;
            if (displayType < 64 && !isDrawn(displayType)) displayType = 2;
        }
        // G70: drawn types draw a road for every side-street bit; the phone doesn't say
        // which roads meet the turn, so none (icons keep HMG-API's 65535)
        cluster.tbtInfo(displayType, isDrawn(displayType) ? 0 : 65535, direction, distance, 0, 0, unit, bar, barErr);
        sentDistance = distance;
        sentUnit = unit;
        sentType = displayType;
        queueHudList();
        sendHudDistance();
    }

    static boolean isDrawn(int type) {
        return type == DRAWN_TURN || type == EXIT_RIGHT || type == EXIT_LEFT || type == DRAWN_FORK;
    }

    // ---- G70: the transport channel (cross name, HUD turn list), one message per TP_GAP_MS

    /** Milliseconds until the channel is free (0: free now). */
    long tpWait() {
        return Math.max(0, tpFree - SystemClock.elapsedRealtime());
    }

    /** Marks the channel busy for TP_GAP_MS from now (a message was just sent). */
    void tpUsed() {
        tpFree = SystemClock.elapsedRealtime() + TP_GAP_MS;
    }

    /** The street of the next turn (cross name), when it changed. */
    void cross(String name) {
        if (name == null || name.equals(crossSent)) return;
        crossSent = name;
        sendCrossWhenFree();
    }

    final Runnable crossRun = new Runnable() {
        @Override
        public void run() {
            sendCrossWhenFree();
        }
    };

    void sendCrossWhenFree() {
        handler.removeCallbacks(crossRun);
        long wait = tpWait();
        if (wait > 0) {
            handler.postDelayed(crossRun, wait);
            return;
        }
        if (crossSent == null) return;
        cluster.crossroadName(crossSent);
        tpUsed();
    }

    /** Sends the HUD turn list in the channel's next free slot (it is built then). */
    void queueHudList() {
        if (hudListQueued) return;
        long wait = tpWait();
        if (wait == 0) {
            sendHudList();
        } else {
            hudListQueued = true;
            handler.postDelayed(hudListRun, wait);
        }
    }

    /** Distance to the next turn, in the owner's unit where the phone's differs. */
    void setDistance(int meters, int e3, int u) {
        // G70: the owner's unit is the phone's (imperial or metric)
        if (u >= MILES && u <= YARDS) usm = DISTANCE_MILES;
        else if (u >= METERS && u <= KILOMETERS_P1) usm = DISTANCE_KM;
        if (meters >= 0) {
            if (usm == DISTANCE_KM) {
                if (u >= MILES) {
                    if (meters < 1000) {
                        u = METERS;
                    } else {
                        e3 = meters;
                        u = KILOMETERS;
                    }
                }
            } else if (usm == DISTANCE_MILES) {
                if (meters >= 161) {
                    if (u < MILES) {
                        e3 = meters * 1000 / 1609;
                        u = MILES_P1;
                    }
                } else if (u != FEET && u != YARDS) {
                    e3 = meters * 3281;
                    u = FEET;
                }
            }
        }
        distance = (float) (e3 / 1000.0d);
        if (u == METERS) {
            if (meters >= 1000) {
                distance = (float) (meters / 1000.0d);
                unit = LeafiaCluster.UNIT_KM;
            } else {
                distance = meters;
                unit = LeafiaCluster.UNIT_M;
            }
        } else if (u == KILOMETERS || u == KILOMETERS_P1) {
            unit = LeafiaCluster.UNIT_KM;
        } else if (u == MILES || u == MILES_P1) {
            unit = LeafiaCluster.UNIT_MI;
        } else if (u == FEET) {
            unit = LeafiaCluster.UNIT_FT;
        } else if (u == YARDS) {
            unit = LeafiaCluster.UNIT_YD;
        } else {
            unit = 15;
        }
    }

    void setTurnType(int ev, int side) {
        switch (ev) {
            case STRAIGHT: case MERGE:
                displayType = 65;
                direction = 0;
                break;
            // G70: drawn turns (the built-in navigation's slight/normal/sharp angles)
            case SLIGHT_TURN:
                set(side, DRAWN_TURN, 45, DRAWN_TURN, 315);
                break;
            case TURN:
                set(side, DRAWN_TURN, 90, DRAWN_TURN, 270);
                break;
            case SHARP_TURN:
                set(side, DRAWN_TURN, 135, DRAWN_TURN, 225);
                break;
            case U_TURN:
                displayType = side == RIGHT ? 73 : 72;
                direction = 270;
                break;
            case NAME_CHANGE:
                if (side == RIGHT || side == LEFT) {
                    set(side, DRAWN_TURN, 90, DRAWN_TURN, 270);
                } else {
                    displayType = 65;
                    direction = 0;
                }
                break;
            default:
                break;   // ramps, roundabouts, destination: set by their own
        }
    }

    /** right type/direction, left type/direction, otherwise 64 (unknown) straight */
    private void set(int side, int rType, int rDir, int lType, int lDir) {
        if (side == RIGHT) {
            displayType = rType;
            direction = rDir;
        } else if (side == LEFT) {
            displayType = lType;
            direction = lDir;
        } else {
            displayType = 64;
            direction = 0;
        }
    }

    void setRampType(int ev, int side) {
        if (ev == ON_RAMP) {
            if (side == RIGHT) {
                displayType = 173;
                direction = 30;
            } else if (side == LEFT) {
                displayType = 174;
                direction = 330;
            } else {
                displayType = 172;
                direction = 0;
            }
        } else if (ev == OFF_RAMP) {
            // G70: the built-in navigation's highway exits (SetCaseExpExit: 17 right at 90, 18 left at 270)
            if (side == RIGHT) {
                displayType = EXIT_RIGHT;
                direction = 90;
            } else if (side == LEFT) {
                displayType = EXIT_LEFT;
                direction = 270;
            } else {
                displayType = 86;
                direction = 0;
            }
        } else if (ev == FORK) {
            // G70: the built-in navigation's drawn fork (Y), arrow toward the branch
            if (side == RIGHT) {
                displayType = DRAWN_FORK;
                direction = 45;
            } else if (side == LEFT) {
                displayType = DRAWN_FORK;
                direction = 315;
            } else {
                displayType = 64;
                direction = 0;
            }
        } else if (ev == FERRY_BOAT) {
            displayType = 176;
            direction = 0;
        }
    }

    /** Roundabouts: the exit's angle picks the icon (the cluster draws them for right-hand traffic). */
    void setRoundaboutType(int ev, int side, int a) {
        if (ev == ROUNDABOUT_EXIT) {
            if (side == RIGHT) {
                displayType = 32;
            } else if (side == LEFT) {
                displayType = 33;
            } else {
                displayType = 64;
                direction = 0;
            }
            return;
        }
        if (a == 180) { displayType = 96; direction = 0; }
        else if (a >= 135 && a < 180) { displayType = 97; direction = 45; }
        else if (a >= 90 && a < 135) { displayType = 99; direction = 90; }
        else if (a >= 45 && a < 90) { displayType = 100; direction = 135; }
        else if ((a >= 0 && a < 45) || (a > 315 && a <= 360)) { displayType = 102; direction = 180; }
        else if (a > 270 && a <= 315) { displayType = 103; direction = 225; }
        else if (a > 225 && a <= 270) { displayType = 105; direction = 270; }
        else if (a > 180 && a <= 225) { displayType = 106; direction = 315; }
        else { displayType = 64; direction = 0; }
    }

    // ---- G70: count-down between the phone's updates

    void scheduleCountdown() {
        handler.removeCallbacks(countdown);
        handler.postDelayed(countdown, TICK_MS);
    }

    void countdownTick() {
        if (!navLive || phoneMeters < 0) return;
        long age = SystemClock.elapsedRealtime() - phoneTime;
        if (age > STALE_MS) return;   // no phone update for a while: stop until the next one
        if (age >= FRESH_MS && speedKmh > 0) {
            int est = (int) (phoneMeters - (long) speedKmh * age / 3600L);
            if (est < 0) est = 0;
            if (est != stepMeters) {
                stepMeters = est;
                setDistance(est, e3For(est, phoneUnit), phoneUnit);
                setTurnType(event, turnSide);
                if (distance != sentDistance || unit != sentUnit || displayType != sentType) {
                    sendTurn();
                }
            }
        }
        scheduleCountdown();
    }

    /** The phone's display value (thousandths of the unit) for these meters, rounded as Google shows it. */
    static int e3For(int m, int u) {
        long v;
        switch (u) {
            case FEET: v = ((long) m * 3281L + 5000L) / 10000L * 10000L; break;          // nearest 10 ft
            case YARDS: v = ((long) m * 1094L + 5000L) / 10000L * 10000L; break;
            case MILES: case MILES_P1: v = ((long) m * 100L + 8046L) / 16093L * 100L; break;   // 0.1 mi
            case KILOMETERS: case KILOMETERS_P1: v = ((long) m + 50L) / 100L * 100L; break;   // 0.1 km
            default: v = (long) m * 1000L; break;
        }
        return v > Integer.MAX_VALUE ? Integer.MAX_VALUE : (int) v;
    }

    // ---- HUD

    /** The HUD's turn list: this turn's icon, the next one's (if known) and the road name, when one of them changed. */
    void sendHudList() {
        int type = displayType;
        if (type < 64 && !isDrawn(type)) return;
        int next = 0, third = 0;
        int nk = shifted ? 1 : 0;   // G70: when the shown turn is ahead[0], the next is ahead[1]
        if (aheadOk[nk] || (shifted && aheadKnown[nk])) {
            next = aheadType(aheadEv[nk], aheadSide[nk]);
            if (nk + 1 < 3 && (aheadOk[nk + 1] || aheadKnown[nk + 1])) third = aheadType(aheadEv[nk + 1], aheadSide[nk + 1]);
            hudFresh = true;
        } else if (hudFresh) {
            next = hudNext;
        }
        String r = road == null ? "" : road;
        if (r.startsWith("toward ")) r = r.substring(7);   // G70: the HUD has room for the street only
        if (hudType == type && hudNext == next && r.equals(hudRoad)) return;
        long wait = tpWait();
        if (wait > 0) {   // the cross name just went out: come back when the channel is free
            if (!hudListQueued) {
                hudListQueued = true;
                handler.postDelayed(hudListRun, wait);
            }
            return;
        }
        byte[] f = hudListFrame(type, next, next != 0 ? third : 0, r);
        if (f == null) return;
        if (hudPending == null || !java.util.Arrays.equals(hudPending, f)) {
            // G70: the built-in navigation's order (sendClusterTBTListTPInfo_Android): a
            // clear frame first, the new list on the next round
            cluster.turnListNew(new byte[] { HUD_LIST, 0, 0 });
            tpUsed();
            hudPending = f;
            hudListQueued = true;
            handler.postDelayed(hudListRun, TP_GAP_MS);
            return;
        }
        cluster.turnListNew(f);
        tpUsed();
        hudPending = null;
        hudType = type;
        hudNext = next;
        hudRoad = r;
    }

    /**
     * G70: the built-in navigation's turn list frame (libExSLNavi
     * sendClusterTBTListTPInfo_Android): F2, number of turns (up to 3), the display types
     * of turns 1..3, then turn 1's name in UTF-16LE plus one zero byte, 80 bytes at most.
     */
    static byte[] hudListFrame(int type, int next, int third, String name) {
        byte[] n;
        try {
            n = name.getBytes("UTF-16LE");
        } catch (java.io.UnsupportedEncodingException e) {
            return null;
        }
        int len = Math.min(n.length + 1, 80);
        byte[] f = new byte[5 + len];
        f[0] = HUD_LIST;
        f[1] = (byte) (third != 0 ? 3 : next != 0 ? 2 : 1);
        f[2] = (byte) type;
        f[3] = (byte) next;
        f[4] = (byte) third;
        System.arraycopy(n, 0, f, 5, Math.min(n.length, len));
        return f;
    }

    /** The HUD's distance: whole number (up to 4095) and tenths for km/mi. */
    void sendHudDistance() {
        float d = distance;
        int u = unit;
        if (d < 0f || u < 0 || u > 4) return;
        int whole = Math.min((int) d, 4095);
        int tenths = 0;
        if (u == LeafiaCluster.UNIT_KM || u == LeafiaCluster.UNIT_MI) tenths = Math.max(0, Math.min(9, (int) ((d - whole) * 10f + 0.5f)));
        cluster.tbtSubInfo2C(u, tenths, whole, 0, 0, 0, 0, 0, 0);
    }

    void hudBlank() {
        laneKey = "";
        cluster.tbtSubInfo2C(0, 0, 0, 0, 0, 0, 0, 0, 0);
        byte[] lanes = new byte[81];
        lanes[0] = LANES;
        cluster.laneInfo(lanes);
        hudType = -1;
        hudNext = 0;
        hudFresh = false;
        hudRoad = null;
        // G70: nothing queued for the channel may follow the clear
        handler.removeCallbacks(hudListRun);
        handler.removeCallbacks(crossRun);
        hudListQueued = false;
        hudPending = null;
        crossSent = null;
        cluster.turnListNew(new byte[] { HUD_LIST });
        cluster.turnListNew(new byte[] { HUD_LIST });
        tpUsed();
    }

    /** Clears the turn, the remaining trip, the destination and the HUD. */
    void release() {
        destName = "";
        sendDestName();
        destName = null;
        cluster.tbtInfo(0, 0, 0f, 0f, -1, 0, 0, 0, -1);
        cluster.tbtSubInfo(0f, -1, 0, 0, 0, 0, 0, 0f, -1, 0);
        hudBlank();
        phoneMeters = -1;
        stepMeters = 0;
        distance = -1f;
        turnKey = null;
        awaitDistance = false;
        for (int k = 0; k < 3; k++) {
            aheadOk[k] = false;
            aheadKnown[k] = false;
        }
        LeafiaTbtMark.clear();   // G70: the car navigation may draw again
    }

    void sendDestName() {
        if (destName != null) cluster.destinationName(0, destName);
    }

    // ---- lanes: "nn" lane count, then per lane 8 hex digits (type, then 3 arrow bytes)

    void sendLanes(String s) {
        if (s == null) s = "";
        if (s.equals(laneKey)) return;
        int n = 0;
        if (s.length() >= 2) {
            n = hexByte(s, 0);
            if (n < 0 || n > 8) return;
        }
        byte[] f = new byte[81];
        f[0] = LANES;
        f[1] = (byte) n;
        for (int k = 0; k < n; k++) {
            int at = k * 8 + 2;
            int b = hexByte(s, at);
            if (b < 0) return;
            f[k + 3] = (byte) b;
            for (int j = 0; j < 3; j++) {
                b = hexByte(s, at + 2 + j * 2);
                if (b < 0) return;
                f[k * 3 + 19 + j] = (byte) b;
            }
        }
        cluster.laneInfo(f);
        laneKey = s;
    }

    static int hexByte(String s, int at) {
        if (at + 1 >= s.length()) return -1;
        int hi = hex(s.charAt(at)), lo = hex(s.charAt(at + 1));
        return hi < 0 || lo < 0 ? -1 : hi << 4 | lo;
    }

    static int hex(char c) {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        return -1;
    }

    // ---- the turns ahead (cluster turn list)

    static int aheadType(int ev, int side) {
        switch (ev) {
            case STRAIGHT: case MERGE: return 65;
            // G70: the built-in navigation lists drawn types too
            case SLIGHT_TURN: case TURN: case SHARP_TURN: return side == RIGHT || side == LEFT ? DRAWN_TURN : 64;
            case U_TURN: return side == RIGHT ? 73 : 72;
            case OFF_RAMP: return side == RIGHT ? EXIT_RIGHT : side == LEFT ? EXIT_LEFT : 86;
            case FORK: return side == RIGHT || side == LEFT ? DRAWN_FORK : 64;
            default: return 64;
        }
    }

    void sendAhead(int n) {
        int count = 0;
        for (int k = 0; k < n; k++) if (aheadOk[k]) count++;
        if (count == 0) return;
        LeafiaCluster.Turn[] list = new LeafiaCluster.Turn[count];
        int i = 0;
        for (int k = 0; k < n && i < count; k++) {
            if (!aheadOk[k]) continue;
            LeafiaCluster.Turn t = new LeafiaCluster.Turn();
            t.type = aheadType(aheadEv[k], aheadSide[k]);
            t.direction = Math.max(aheadAng[k], 0);
            t.traffic = 0;
            t.no = i + 1;
            t.name = aheadName[k] == null ? "" : aheadName[k];
            t.exitNumber = aheadExit[k] == 255 || aheadExit[k] < 0 ? "" : String.valueOf(aheadExit[k]);
            int m = aheadMeters[k], e3 = aheadE3[k], u = aheadUnit[k];
            int cu = LeafiaCluster.UNIT_M;
            float d = m;
            if (e3 >= 0) {
                if (u == KILOMETERS || u == KILOMETERS_P1) { cu = LeafiaCluster.UNIT_KM; d = e3 / 1000f; }
                else if (u == MILES || u == MILES_P1) { cu = LeafiaCluster.UNIT_MI; d = e3 / 1000f; }
                else if (u == FEET) { cu = LeafiaCluster.UNIT_FT; d = e3 / 1000f; }
                else if (u == YARDS) { cu = LeafiaCluster.UNIT_FT; d = e3 / 1000f * 3f; }
            }
            if (usm == DISTANCE_KM) {
                if (m < 1000) { cu = LeafiaCluster.UNIT_M; d = m; }
                else { cu = LeafiaCluster.UNIT_KM; d = m / 1000f; }
            } else if (usm == DISTANCE_MILES) {
                if (m < 161) { cu = LeafiaCluster.UNIT_FT; d = m * 3.28084f; }
                else { cu = LeafiaCluster.UNIT_MI; d = m / 1609f; }
            }
            t.distance = Math.max(0f, Math.min(65535f, d));
            t.unit = cu;
            list[i++] = t;
        }
        cluster.turnList(list);
        if (aheadOk[0]) {
            hudNext = aheadType(aheadEv[0], aheadSide[0]);
            hudFresh = true;
        }
        for (int k = 0; k < 3; k++) aheadOk[k] = false;
    }

    // ---- remaining distance and arrival time

    /** Sends the remaining trip when it changed or the owner changed units; then checks again every 250 ms. */
    void sendRemain() {
        if (!navLive || tripMeters < 0) return;
        LeafiaTbtMark.mark();
        if (tripGen == sentGen) {
            if (usm == -1 || usm == lastUsm) return;
        }
        sentGen = tripGen;
        int m = tripMeters, u = tripUnit;
        lastUsm = usm;
        if (usm == DISTANCE_KM) u = m < 1000 ? METERS : KILOMETERS;
        else if (usm == DISTANCE_MILES) u = m < 161 ? FEET : MILES;
        int whole, tenths = 0, cu;
        if (u == KILOMETERS || u == KILOMETERS_P1 || (u != MILES && u != MILES_P1 && u != FEET && u != YARDS && m >= 1000)) {
            whole = m / 1000;
            tenths = m % 1000 / 100;
            cu = LeafiaCluster.UNIT_KM;
        } else if (u == MILES || u == MILES_P1) {
            int t = m * 10 / 1609;
            tenths = t % 10;
            whole = t / 10;
            cu = LeafiaCluster.UNIT_MI;
        } else if (u == FEET) {
            whole = m * 3281 / 1000;
            cu = LeafiaCluster.UNIT_FT;
        } else if (u == YARDS) {
            whole = m * 1094 / 1000;
            cu = LeafiaCluster.UNIT_YD;
        } else {
            whole = m;
            cu = LeafiaCluster.UNIT_M;
        }
        int hour = -1, minute = -1, timeType = -1, timeFormat = -1;
        int s = tripSeconds;
        Calendar c = null;
        if (s >= 500000000) {   // a clock time (seconds since 1970)
            c = Calendar.getInstance();
            c.setTimeInMillis(s * 1000L);
        } else if (s >= 0 && s <= 604800) {   // seconds from now
            c = Calendar.getInstance();
            c.add(Calendar.SECOND, s);
        }
        if (c != null) {
            hour = c.get(Calendar.HOUR_OF_DAY);
            minute = c.get(Calendar.MINUTE);
            timeType = 1;
            timeFormat = context == null || DateFormat.is24HourFormat(context) ? 2 : 1;
        }
        cluster.tbtSubInfo(whole + tenths / 10f, 0, cu, hour, minute, timeType, timeFormat, 0f, -1, estPoint);
        scheduleTick();
    }

    void scheduleTick() {
        if (tripMeters < 0) return;
        handler.removeCallbacks(tick);
        handler.postDelayed(tick, 250);
    }

    void unitTick() {
        if (tripMeters < 0) return;
        sendRemain();
        scheduleTick();
    }
}
