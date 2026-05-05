package com.interguard.app;

import android.content.Context;
import android.os.Build;
import android.provider.Settings;

/**
 * Generates stable device-specific identity values:
 *  - Device name (from Build.MODEL, sanitized for URL use)
 *  - Virtual IP in 172.16.x.x range (derived from Android ID hash)
 *
 * The virtual IP lets AdGuard Home distinguish each device separately
 * even when they share the same physical network IP.
 */
public class DeviceIdentity {

    private DeviceIdentity() {}

    /**
     * Returns a URL-safe device name derived from Build.MODEL.
     * Spaces and special chars replaced with underscores.
     * Max 32 chars.
     */
    public static String getDefaultDeviceName() {
        String raw = Build.MODEL != null ? Build.MODEL : "InterGuard_Device";
        // Replace anything not alphanumeric, dash, or underscore
        String clean = raw.replaceAll("[^a-zA-Z0-9_\\-]", "_")
                          .replaceAll("_+", "_")  // collapse multiple underscores
                          .replaceAll("^_|_$", ""); // trim leading/trailing
        if (clean.isEmpty()) clean = "InterGuard_Device";
        // Truncate to 32 chars
        if (clean.length() > 32) clean = clean.substring(0, 32);
        return clean;
    }

    /**
     * Generates a deterministic virtual IP in the 172.16.0.0/12 range
     * from the device's Android ID. The IP is stable across reboots and
     * reinstalls as long as the Android ID doesn't change.
     *
     * Range used: 172.16.1.1 – 172.31.254.254 (avoids .0.0 and .255.255)
     */
    public static String generateVirtualIp(Context context) {
        String androidId = null;
        try {
            androidId = Settings.Secure.getString(
                    context.getContentResolver(), Settings.Secure.ANDROID_ID);
        } catch (Exception ignored) {}

        if (androidId == null || androidId.isEmpty()) {
            androidId = Build.FINGERPRINT != null ? Build.FINGERPRINT : "default";
        }

        int hash = Math.abs(androidId.hashCode());

        // 172.16.x.y where x in [1,30], y in [1,254]
        int octet3 = (hash % 30) + 1;        // 1–30  (stays in 172.16–172.31 range for /12)
        int octet4 = ((hash >> 8) % 254) + 1; // 1–254

        return "172.16." + octet3 + "." + octet4;
    }

    /**
     * Appends the device name to a base DoH URL.
     * e.g., "https://dns.example.com/dns-query" + "MyPhone"
     *    → "https://dns.example.com/dns-query/MyPhone"
     *
     * If the URL already ends with the device name, returns as-is.
     */
    public static String buildDoHUrl(String baseUrl, String deviceName) {
        if (baseUrl == null || baseUrl.isEmpty()) return baseUrl;
        if (deviceName == null || deviceName.trim().isEmpty()) return baseUrl;

        // Only append device name if it is the InterGuard Default server
        if (!baseUrl.startsWith(InterGuardPrefs.DEFAULT_BASE_DOH_URL)) {
            return baseUrl;
        }

        String name = deviceName.trim();
        // Remove trailing slash from base
        String base = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;

        // Check if it already ends with this name
        if (base.endsWith("/" + name)) return base;

        return base + "/" + name;
    }

    /**
     * Strips a device name suffix from a DoH URL, returning just the base URL.
     * Useful when changing the device name.
     */
    public static String stripDeviceName(String url, String deviceName) {
        if (url == null || deviceName == null || deviceName.isEmpty()) return url;
        String suffix = "/" + deviceName.trim();
        if (url.endsWith(suffix)) {
            return url.substring(0, url.length() - suffix.length());
        }
        return url;
    }
}
