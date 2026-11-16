/*
 * Genesis G70 bridge: the Wi-Fi network name and password Android Auto (GPM WirelessExplorer)
 * and CarPlay (Iap2Service) send to the phone.
 *
 * Stock reads WifiConfiguration.ConnectivitySSID / ConnectivityPSK: the "projection" network.
 * Firmware built for wireless projection (the G70) starts the hotspot with exactly those. Firmware
 * that never shipped it (the Kia Stinger) starts the hotspot with the passenger-hotspot SSID /
 * preSharedKey instead, so the phone was told to join a network that isn't on the air. These read
 * the running hotspot's own config (/data/misc/wifi/hostapd.conf): when it broadcasts the plain
 * SSID and not the connectivity one, the plain SSID / preSharedKey are sent; otherwise (the G70)
 * the stock connectivity values, unchanged.
 *
 * GPM and iap2server can't read hostapd.conf on the car (uid system without group wifi: EACCES,
 * Stinger test 6b log 2026-11-14). Then the package's hint decides: the Stinger package sets
 * persist.leafia.ap.plain=t (its hotspot always broadcasts the plain SSID); the G70 never sets it.
 *
 * GPL-3.0 (Genesis G70 bridge).
 */
package com.leafia.wifi;

import android.net.wifi.WifiConfiguration;
import android.util.Log;

import java.io.BufferedReader;
import java.io.FileReader;

public final class LeafiaApName {
    static final String TAG = "LeafiaCP";
    static final String HOSTAPD_CONF = "/data/misc/wifi/hostapd.conf";
    static String sLast;

    private LeafiaApName() {
    }

    static final String PLAIN_PROP = "persist.leafia.ap.plain";

    /** true: the hotspot broadcasts the plain SSID (send SSID / preSharedKey) */
    public static boolean usePlain(String hostapdSsid, String ssid, String connSsid) {
        return usePlain(hostapdSsid, ssid, connSsid, false);
    }

    /** hint: the package says this unit's hotspot broadcasts the plain SSID (used when hostapd.conf can't be read) */
    public static boolean usePlain(String hostapdSsid, String ssid, String connSsid, boolean hint) {
        if (ssid == null || ssid.length() == 0 || ssid.equals(connSsid)) return false;
        if (hostapdSsid != null) return hostapdSsid.equals(ssid);
        return hint;
    }

    static boolean hint() {
        try {
            Object v = Class.forName("android.os.SystemProperties")
                    .getMethod("get", String.class, String.class).invoke(null, PLAIN_PROP, "");
            return "t".equals(v);
        } catch (Throwable t) {
            return false;
        }
    }

    static String field(WifiConfiguration c, String name) {
        try {
            return (String) WifiConfiguration.class.getField(name).get(c);
        } catch (Throwable t) {
            return null;
        }
    }

    static String hostapdSsid() {
        BufferedReader r = null;
        try {
            r = new BufferedReader(new FileReader(HOSTAPD_CONF));
            for (String l; (l = r.readLine()) != null; )
                if (l.startsWith("ssid=")) return l.substring(5);
        } catch (Throwable t) {
            note("can't read " + HOSTAPD_CONF + " (" + t + "): " + PLAIN_PROP + "=" + (hint() ? "t" : "unset") + " decides");
        } finally {
            try {
                if (r != null) r.close();
            } catch (Throwable ignored) {
            }
        }
        return null;
    }

    static void note(String s) {
        if (!s.equals(sLast)) {
            sLast = s;
            Log.i(TAG, "Leafia: " + s);
        }
    }

    static boolean plain(WifiConfiguration c) {
        if (c == null) return false;
        String connSsid = field(c, "ConnectivitySSID");
        boolean p = usePlain(hostapdSsid(), c.SSID, connSsid, hint());
        note(p ? "the hotspot broadcasts its passenger-hotspot name: sending the phone that network (not the projection one)"
                : "sending the phone the projection network (the hotspot broadcasts it)");
        return p;
    }

    /** stands in for c.ConnectivitySSID */
    public static String ssid(WifiConfiguration c) {
        try {
            return plain(c) ? c.SSID : field(c, "ConnectivitySSID");
        } catch (Throwable t) {
            return field(c, "ConnectivitySSID");
        }
    }

    /** stands in for c.ConnectivityPSK */
    public static String psk(WifiConfiguration c) {
        try {
            return plain(c) ? c.preSharedKey : field(c, "ConnectivityPSK");
        } catch (Throwable t) {
            return field(c, "ConnectivityPSK");
        }
    }
}
