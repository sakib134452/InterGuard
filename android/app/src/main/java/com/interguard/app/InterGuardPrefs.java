package com.interguard.app;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * Centralised SharedPreferences access for InterGuard.
 * Stores: DoH URL, VPN enabled flag, start-on-boot, onboarding seen.
 */
public class InterGuardPrefs {

    private static final String PREFS_NAME = "interguard_prefs";
    private static final String KEY_DOH_URL = "doh_url";
    private static final String KEY_VPN_ENABLED = "vpn_enabled";
    private static final String KEY_START_ON_BOOT = "start_on_boot";
    private static final String KEY_ONBOARDING_SEEN = "onboarding_seen";

    public static final String DEFAULT_DOH_URL =
            "https://dns.sacloudserver.top/dns-query";

    private InterGuardPrefs() {}

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getApplicationContext()
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    // ─── DoH URL ──────────────────────────────────────────────────────────────

    public static String getDoHUrl(Context ctx) {
        return prefs(ctx).getString(KEY_DOH_URL, DEFAULT_DOH_URL);
    }

    public static void setDoHUrl(Context ctx, String url) {
        prefs(ctx).edit().putString(KEY_DOH_URL, url).apply();
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
}
