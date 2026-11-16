/*
 * Genesis G70 bridge: make sure the car's projection hotspot is on.
 *
 * Wireless CarPlay and Android Auto run over the head unit's own hotspot ("Wi-Fi AP for
 * connectivity", AP mode 2). At boot WifiService starts it only when Settings.Global
 * wifi_ap_on is 1 and Wi-Fi client mode is off, and the stock PhoneProjection app turns it back
 * on (WifiManager.setWifiApEnabledForConnectivity) only after a passkey renewal or its
 * "hotspot continues" popup. Once the car has joined a home network, the hotspot stays off:
 * phones then get "wireless Android Auto / CarPlay available" over Bluetooth but there is no
 * car network to join.
 *
 * This does what PhoneProjection's turnOnWiFi does, by itself: about 20 s after DiPO starts,
 * whenever a Bluetooth device connects, 3 s after the car comes back on (WifiService turns the
 * hotspot off at ACC off and never on again), and 8 s after the hotspot goes off while the car
 * is on (unless the car joined a Wi-Fi network). Never while the car is off (ACC 0xff).
 * Once it is up it also makes the network name phones are told to join match the one the
 * hotspot really broadcasts (see needSync). Only when the unit has the wireless projection features
 * and no AP is up at all (a passenger hotspot in another mode is left alone). Hidden WifiManager
 * methods are called by reflection. DiPO runs as the system user (CHANGE_WIFI_STATE).
 *
 * GPL-3.0 (Genesis G70 bridge).
 */
package com.daudio.app.dipo;

import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import java.lang.reflect.Method;

public final class LeafiaHotspot {
    static final String TAG = "LeafiaCP";
    static final int AP_MODE_CONNECTIVITY = 2;
    static final long BOOT_DELAY_MS = 20000, CONNECT_DELAY_MS = 1500, ACC_ON_DELAY_MS = 3000,
            AP_OFF_DELAY_MS = 8000, MIN_GAP_MS = 15000;
    static final String ACTION_ACC = "com.hkmc.intent.action.ACTION_ACC_STATUS_CHANGED";
    static final String EXTRA_ACC = "android.ibox.mode.EXTRA_ACC_STATUS";
    static final String ACTION_AP = "android.net.wifi.WIFI_AP_STATE_CHANGED";
    /** ACC states (WifiService): 0 on, 1 login, 2 ADM, 5 system ready, 6 off-delay, 0xff off */
    static final int ACC_OFF = 0xff, AP_DISABLED = 11, AP_ENABLED = 13;
    static final long SYNC_DELAY_MS = 1500;
    static final String HOSTAPD_CONF = "/data/misc/wifi/hostapd.conf";

    static Context sContext;
    static Handler sHandler;
    static long sLastTry = -MIN_GAP_MS;
    /** last ACC state seen (-1 unknown): WifiService turns the hotspot off at ACC off and never
     *  back on, so the hotspot is turned on again at the next ACC change that is not off */
    static volatile int sAcc = -1;
    static String sLastState;

    private LeafiaHotspot() {
    }

    /** DipoService.onCreate */
    public static synchronized void init(Context c) {
        try {
            if (sContext != null || c == null) return;
            sContext = c.getApplicationContext() != null ? c.getApplicationContext() : c;
            sHandler = new Handler(Looper.getMainLooper());
            IntentFilter f = new IntentFilter(BluetoothDevice.ACTION_ACL_CONNECTED);
            f.addAction(ACTION_ACC);
            f.addAction(ACTION_AP);
            sContext.registerReceiver(new BroadcastReceiver() {
                @Override
                public void onReceive(Context ctx, Intent i) {
                    String a = i.getAction();
                    if (ACTION_ACC.equals(a)) {
                        sAcc = i.getIntExtra(EXTRA_ACC, -1);
                        if (sAcc != ACC_OFF && sAcc != -1) later("car on again (ACC " + sAcc + ")", ACC_ON_DELAY_MS, false);
                    } else if (ACTION_AP.equals(a)) {
                        int st = i.getIntExtra("wifi_state", -1);
                        if (st == AP_DISABLED) later("hotspot turned off", AP_OFF_DELAY_MS, true);
                        else if (st == AP_ENABLED) syncLater("hotspot on", SYNC_DELAY_MS);
                    } else {
                        sync("phone connected over Bluetooth");
                        later("phone connected over Bluetooth", CONNECT_DELAY_MS, false);
                    }
                }
            }, f);
            later("start", BOOT_DELAY_MS, false);
        } catch (Throwable t) {
            Log.w(TAG, "Leafia: hotspot watch not started: " + t);
        }
    }

    /** soft: leave it off while the car is on a Wi-Fi network (the owner chose that; a phone
     *  connecting or the next car start still turns the hotspot on) */
    static void later(final String why, long delay, final boolean soft) {
        sHandler.postDelayed(new Runnable() {
            @Override
            public void run() {
                ensure(why, soft);
            }
        }, delay);
    }

    static void syncLater(final String why, long delay) {
        sHandler.postDelayed(new Runnable() {
            @Override
            public void run() {
                sync(why);
            }
        }, delay);
    }

    /** The phone joins the network Android Auto / CarPlay name (ConnectivitySSID / ConnectivityPSK
     *  of the AP config). Firmware built for wireless projection (the G70) starts the hotspot in
     *  mode 2 with exactly those; firmware that never shipped it (the Kia Stinger) starts it with
     *  the passenger-hotspot SSID / preSharedKey, so phones look for a network that isn't there.
     *  True when the running hotspot broadcasts the plain SSID while the connectivity SSID differs:
     *  then the connectivity name/password are set to the broadcast ones. */
    public static boolean needSync(boolean apOn, int apMode, String hostapdSsid, String ssid, String connSsid) {
        if (!apOn || apMode != AP_MODE_CONNECTIVITY || hostapdSsid == null || ssid == null) return false;
        return hostapdSsid.equals(ssid) && !ssid.equals(connSsid);
    }

    static String hostapdSsid() {
        java.io.BufferedReader r = null;
        try {
            r = new java.io.BufferedReader(new java.io.FileReader(HOSTAPD_CONF));
            for (String l; (l = r.readLine()) != null; )
                if (l.startsWith("ssid=")) return l.substring(5);
        } catch (Throwable t) {
            Log.w(TAG, "Leafia: can't read " + HOSTAPD_CONF + ": " + t);
        } finally {
            try {
                if (r != null) r.close();
            } catch (Throwable ignored) {
            }
        }
        return null;
    }

    static synchronized void sync(String why) {
        try {
            WifiManager wm = (WifiManager) sContext.getSystemService(Context.WIFI_SERVICE);
            if (wm == null) return;
            boolean on = (Boolean) WifiManager.class.getMethod("isWifiApEnabled").invoke(wm);
            int mode = (Integer) WifiManager.class.getMethod("getWifiApMode").invoke(wm);
            if (!on) return;
            WifiConfiguration cfg = (WifiConfiguration) WifiManager.class.getMethod("getWifiApConfiguration").invoke(wm);
            if (cfg == null) return;
            java.lang.reflect.Field fs = WifiConfiguration.class.getField("ConnectivitySSID");
            java.lang.reflect.Field fp = WifiConfiguration.class.getField("ConnectivityPSK");
            String connSsid = (String) fs.get(cfg);
            String hs = hostapdSsid();
            boolean need = needSync(on, mode, hs, cfg.SSID, connSsid);
            String state = "AP mode " + mode + ", broadcast " + (hs == null ? "unknown" : hs.equals(cfg.SSID) ? "= hotspot name"
                    : hs.equals(connSsid) ? "= projection name" : "other") + ", names " + (cfg.SSID != null && cfg.SSID.equals(connSsid) ? "equal" : "differ");
            if (!state.equals(sLastState)) {
                sLastState = state;
                Log.i(TAG, "Leafia: projection network check (" + why + "): " + state + (need ? " -> fixing" : ""));
            }
            if (!need) return;
            WifiConfiguration n = WifiConfiguration.class.getConstructor(WifiConfiguration.class).newInstance(cfg);
            fs.set(n, cfg.SSID);
            fp.set(n, cfg.preSharedKey);
            Object r = WifiManager.class.getMethod("setWifiApConfiguration", WifiConfiguration.class).invoke(wm, n);
            Log.i(TAG, "Leafia: this firmware's hotspot broadcasts its own network name, not the one phones are told to join:"
                    + " set the projection network name/password to the broadcast ones (" + why + ") -> " + r);
        } catch (Throwable t) {
            Log.w(TAG, "Leafia: matching the projection network name failed (" + why + "): " + t);
        }
    }

    static boolean wireless(Context c) {
        PackageManager pm = c.getPackageManager();
        return pm.hasSystemFeature("com.hkmc.software.connectivity.carplay_wireless")
                || pm.hasSystemFeature("com.hkmc.software.connectivity.androidauto_wireless");
    }

    /** what to do: 0 nothing (no wireless features, an AP already up in any mode, the car is
     *  off, or a soft trigger while the Wi-Fi client is on), 1 turn the projection hotspot on */
    public static int decide(boolean wireless, boolean apEnabled, int acc, boolean clientOn, boolean soft) {
        if (!wireless || apEnabled || acc == ACC_OFF) return 0;
        if (soft && clientOn) return 0;
        return 1;
    }

    static synchronized void ensure(String why, boolean soft) {
        // the hotspot may already be up (started at boot before DiPO listened): check the name
        sync(why);
        try {
            long now = SystemClock.elapsedRealtime();
            if (now - sLastTry < MIN_GAP_MS) return;
            Context c = sContext;
            WifiManager wm = (WifiManager) c.getSystemService(Context.WIFI_SERVICE);
            if (wm == null) return;
            boolean on = (Boolean) WifiManager.class.getMethod("isWifiApEnabled").invoke(wm);
            int mode = (Integer) WifiManager.class.getMethod("getWifiApMode").invoke(wm);
            WifiConfiguration cfg = (WifiConfiguration) WifiManager.class.getMethod("getWifiApConfiguration").invoke(wm);
            if (decide(wireless(c), on, sAcc, wm.isWifiEnabled(), soft) == 0) return;
            sLastTry = now;
            Method set = WifiManager.class.getMethod("setWifiApEnabledForConnectivity", WifiConfiguration.class, boolean.class);
            Object r = set.invoke(wm, cfg, Boolean.TRUE);
            Log.i(TAG, "Leafia: projection hotspot was off (Wi-Fi client " + (wm.isWifiEnabled() ? "on" : "off")
                    + ", AP mode " + mode + (cfg == null ? ", no saved AP config" : "") + "): turned it on (" + why + ") -> " + r);
        } catch (Throwable t) {
            Log.w(TAG, "Leafia: turning the projection hotspot on failed (" + why + "): " + t);
        }
    }
}
