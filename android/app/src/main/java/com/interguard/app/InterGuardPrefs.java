package com.interguard.app;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

/**
 * Centralised SharedPreferences access for InterGuard.
 */
public class InterGuardPrefs {

    private static final String PREFS_NAME = "interguard_prefs";

    private static final String KEY_DOH_URL        = "doh_url";
    private static final String KEY_FALLBACK_DOH_URL = "fallback_doh_url";
    private static final String KEY_BASE_DOH_URL   = "base_doh_url";
    private static final String KEY_DEVICE_NAME    = "device_name";
    private static final String KEY_VIRTUAL_IP     = "virtual_ip";
    private static final String KEY_VPN_ENABLED    = "vpn_enabled";
    private static final String KEY_START_ON_BOOT  = "start_on_boot";
    private static final String KEY_ONBOARDING_SEEN = "onboarding_seen";
    private static final String KEY_FIRST_LAUNCH   = "first_launch_done";
    private static final String KEY_DISALLOWED_APPS = "disallowed_apps";

    public static final String DEFAULT_BASE_DOH_URL =
            "https://dns.sacloudserver.top/dns-query";
    public static final String DEFAULT_FALLBACK_DOH_URL =
            "https://cloudflare-dns.com/dns-query";

    private InterGuardPrefs() {}

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getApplicationContext()
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    // ─── DoH URL ──────────────────────────────────────────────────────────────

    public static String getDoHUrl(Context ctx) {
        return prefs(ctx).getString(KEY_DOH_URL, DEFAULT_BASE_DOH_URL);
    }

    public static void setDoHUrl(Context ctx, String url) {
        prefs(ctx).edit().putString(KEY_DOH_URL, url).apply();
    }

    // ─── Fallback DoH URL ─────────────────────────────────────────────────────

    public static String getFallbackDoHUrl(Context ctx) {
        return prefs(ctx).getString(KEY_FALLBACK_DOH_URL, DEFAULT_FALLBACK_DOH_URL);
    }

    public static void setFallbackDoHUrl(Context ctx, String url) {
        prefs(ctx).edit().putString(KEY_FALLBACK_DOH_URL, url).apply();
    }

    // ─── Base DoH URL (without device name suffix) ────────────────────────────

    public static String getBaseDoHUrl(Context ctx) {
        return prefs(ctx).getString(KEY_BASE_DOH_URL, DEFAULT_BASE_DOH_URL);
    }

    public static void setBaseDoHUrl(Context ctx, String url) {
        prefs(ctx).edit().putString(KEY_BASE_DOH_URL, url).apply();
    }

    // ─── Device Name ──────────────────────────────────────────────────────────

    public static String getDeviceName(Context ctx) {
        return prefs(ctx).getString(KEY_DEVICE_NAME, DeviceIdentity.getDefaultDeviceName());
    }

    public static void setDeviceName(Context ctx, String name) {
        prefs(ctx).edit().putString(KEY_DEVICE_NAME, name).apply();
    }

    // ─── Virtual IP ───────────────────────────────────────────────────────────

    public static String getVirtualIp(Context ctx) {
        String stored = prefs(ctx).getString(KEY_VIRTUAL_IP, null);
        if (stored == null) {
            stored = DeviceIdentity.generateVirtualIp(ctx);
            setVirtualIp(ctx, stored);
        }
        return stored;
    }

    public static void setVirtualIp(Context ctx, String ip) {
        prefs(ctx).edit().putString(KEY_VIRTUAL_IP, ip).apply();
    }

    // ─── VPN Enabled ──────────────────────────────────────────────────────────

    public static boolean getVpnEnabled(Context ctx) {
        return prefs(ctx).getBoolean(KEY_VPN_ENABLED, false);
    }

    public static void setVpnEnabled(Context ctx, boolean enabled) {
        prefs(ctx).edit().putBoolean(KEY_VPN_ENABLED, enabled).apply();
    }

    // ─── Start on Boot ────────────────────────────────────────────────────────

    public static boolean getStartOnBoot(Context ctx) {
        return prefs(ctx).getBoolean(KEY_START_ON_BOOT, false);
    }

    public static void setStartOnBoot(Context ctx, boolean enabled) {
        prefs(ctx).edit().putBoolean(KEY_START_ON_BOOT, enabled).apply();
    }

    // ─── Onboarding ───────────────────────────────────────────────────────────

    public static boolean getOnboardingSeen(Context ctx) {
        return prefs(ctx).getBoolean(KEY_ONBOARDING_SEEN, false);
    }

    public static void setOnboardingSeen(Context ctx, boolean seen) {
        prefs(ctx).edit().putBoolean(KEY_ONBOARDING_SEEN, seen).apply();
    }

    // ─── First Launch Setup ───────────────────────────────────────────────────

    public static boolean isFirstLaunchDone(Context ctx) {
        return prefs(ctx).getBoolean(KEY_FIRST_LAUNCH, false);
    }

    public static void setFirstLaunchDone(Context ctx, boolean done) {
        prefs(ctx).edit().putBoolean(KEY_FIRST_LAUNCH, done).apply();
    }

    // ─── Per-App Filtering (Disallowed apps bypass VPN) ───────────────────────

    public static Set<String> getDisallowedApps(Context ctx) {
        return prefs(ctx).getStringSet(KEY_DISALLOWED_APPS, Collections.emptySet());
    }

    public static void setDisallowedApps(Context ctx, Set<String> packages) {
        prefs(ctx).edit().putStringSet(KEY_DISALLOWED_APPS, packages).apply();
    }
}
