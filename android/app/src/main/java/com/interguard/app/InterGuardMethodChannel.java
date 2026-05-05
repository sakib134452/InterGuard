package com.interguard.app;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.net.VpnService;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;
import android.util.Log;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class InterGuardMethodChannel {

    private static final String TAG = "IGMethodChannel";
    public static final String CHANNEL       = "com.interguard.app/vpn";
    public static final String EVENT_CHANNEL = "com.interguard.app/vpn_status";
    private static final int VPN_REQUEST_CODE = 9000;

    private static volatile EventChannel.EventSink eventSink = null;
    private static final ExecutorService bgExecutor = Executors.newCachedThreadPool();

    private final Context context;
    private final Activity activity;

    public InterGuardMethodChannel(Context context, Activity activity) {
        this.context  = context;
        this.activity = activity;
    }

    public void register(FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler(this::handleMethod);

        new EventChannel(engine.getDartExecutor().getBinaryMessenger(), EVENT_CHANNEL)
                .setStreamHandler(new EventChannel.StreamHandler() {
                    @Override public void onListen(Object args, EventChannel.EventSink sink) { eventSink = sink; }
                    @Override public void onCancel(Object args) { eventSink = null; }
                });
    }

    public static void sendStatusUpdate(boolean isRunning) {
        EventChannel.EventSink sink = eventSink;
        if (sink != null) {
            new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                try { sink.success(isRunning); }
                catch (Exception e) { Log.w(TAG, "Event sink error: " + e.getMessage()); }
            });
        }
    }

    private void handleMethod(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "startVpn":             handleStartVpn(result); break;
            case "stopVpn":              stopVpn(); result.success(null); break;
            case "isVpnRunning":         result.success(isVpnRunning()); break;
            case "getStats":             result.success(getStats()); break;
            case "getLogs":              result.success(getLogs()); break;
            case "clearLogs":            QueryLogger.getInstance().clear(); result.success(null); break;
            case "setDoHUrl":            handleSetDoHUrl(call, result); break;
            case "getDoHUrl":            result.success(InterGuardPrefs.getDoHUrl(context)); break;
            case "setFallbackDoHUrl":    handleSetFallbackDoHUrl(call, result); break;
            case "getFallbackDoHUrl":    result.success(InterGuardPrefs.getFallbackDoHUrl(context)); break;
            case "setStartOnBoot":       handleSetStartOnBoot(call, result); break;
            case "getStartOnBoot":       result.success(InterGuardPrefs.getStartOnBoot(context)); break;
            case "testConnection":       handleTestConnection(call, result); break;
            case "openVpnSettings":      openVpnSettings(); result.success(null); break;

            // Device identity
            case "getDeviceName":        result.success(InterGuardPrefs.getDeviceName(context)); break;
            case "setDeviceName":        handleSetDeviceName(call, result); break;
            case "getVirtualIp":         result.success(InterGuardPrefs.getVirtualIp(context)); break;

            // Battery optimization
            case "isBatteryOptimizationIgnored": result.success(isBatteryOptIgnored()); break;
            case "requestBatteryOptimization":   requestBatteryOpt(); result.success(null); break;

            // Per-app filtering
            case "getInstalledApps":     handleGetInstalledApps(result); break;
            case "getDisallowedApps":    result.success(new ArrayList<>(InterGuardPrefs.getDisallowedApps(context))); break;
            case "setDisallowedApps":    handleSetDisallowedApps(call, result); break;

            // First-launch setup
            case "isFirstLaunchDone":    result.success(InterGuardPrefs.isFirstLaunchDone(context)); break;
            case "completeFirstLaunch":  handleCompleteFirstLaunch(call, result); break;

            default: result.notImplemented();
        }
    }

    // ─── VPN start/stop ───────────────────────────────────────────────────────

    private void handleStartVpn(MethodChannel.Result result) {
        Intent prepareIntent = VpnService.prepare(context);
        if (prepareIntent == null) {
            startVpnService();
            result.success(true);
        } else {
            activity.startActivityForResult(prepareIntent, VPN_REQUEST_CODE);
            result.success(true);
        }
    }

    public void startVpnService() {
        InterGuardPrefs.setVpnEnabled(context, true);
        Intent intent = new Intent(context, InterGuardVpnService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    private void stopVpn() {
        InterGuardPrefs.setVpnEnabled(context, false);
        InterGuardVpnService svc = InterGuardVpnService.instance;
        if (svc != null) svc.stopTunnel();
        context.stopService(new Intent(context, InterGuardVpnService.class));
    }

    private boolean isVpnRunning() {
        InterGuardVpnService svc = InterGuardVpnService.instance;
        return svc != null && svc.isRunning();
    }

    // ─── DoH URL ──────────────────────────────────────────────────────────────

    private void handleSetDoHUrl(MethodCall call, MethodChannel.Result result) {
        String url = call.argument("url");
        if (url != null) {
            InterGuardPrefs.setDoHUrl(context, url);
            InterGuardVpnService svc = InterGuardVpnService.instance;
            if (svc != null) svc.updateDoHUrl(url);
        }
        result.success(null);
    }

    private void handleSetFallbackDoHUrl(MethodCall call, MethodChannel.Result result) {
        String url = call.argument("url");
        if (url != null) {
            InterGuardPrefs.setFallbackDoHUrl(context, url);
            InterGuardVpnService svc = InterGuardVpnService.instance;
            if (svc != null) svc.updateFallbackDoHUrl(url);
        }
        result.success(null);
    }

    // ─── Device identity ──────────────────────────────────────────────────────

    private void handleSetDeviceName(MethodCall call, MethodChannel.Result result) {
        String name = call.argument("name");
        if (name != null && !name.trim().isEmpty()) {
            InterGuardPrefs.setDeviceName(context, name.trim());

            // Update the DoH URL to use the new name (replace old suffix)
            String currentUrl = InterGuardPrefs.getDoHUrl(context);
            String baseUrl    = InterGuardPrefs.getBaseDoHUrl(context);
            String newUrl     = DeviceIdentity.buildDoHUrl(baseUrl, name.trim());
            InterGuardPrefs.setDoHUrl(context, newUrl);
            InterGuardVpnService svc = InterGuardVpnService.instance;
            if (svc != null) svc.updateDoHUrl(newUrl);
        }
        result.success(null);
    }

    // ─── First launch ─────────────────────────────────────────────────────────

    private void handleCompleteFirstLaunch(MethodCall call, MethodChannel.Result result) {
        String deviceName = call.argument("deviceName");
        String baseUrl    = call.argument("baseUrl");

        if (deviceName != null && !deviceName.trim().isEmpty()) {
            InterGuardPrefs.setDeviceName(context, deviceName.trim());
        } else {
            deviceName = InterGuardPrefs.getDeviceName(context);
        }

        if (baseUrl == null || baseUrl.isEmpty()) {
            baseUrl = InterGuardPrefs.DEFAULT_BASE_DOH_URL;
        }

        InterGuardPrefs.setBaseDoHUrl(context, baseUrl);
        String fullUrl = DeviceIdentity.buildDoHUrl(baseUrl, deviceName.trim());
        InterGuardPrefs.setDoHUrl(context, fullUrl);

        // Initialise virtual IP
        InterGuardPrefs.getVirtualIp(context);

        InterGuardPrefs.setFirstLaunchDone(context, true);
        result.success(fullUrl);
    }

    // ─── Battery optimization ─────────────────────────────────────────────────

    private boolean isBatteryOptIgnored() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
            return pm != null && pm.isIgnoringBatteryOptimizations(context.getPackageName());
        }
        return true; // Not applicable on older Android
    }

    private void requestBatteryOpt() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                Intent intent = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
                intent.setData(Uri.parse("package:" + context.getPackageName()));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(intent);
            } catch (Exception e) {
                Log.e(TAG, "Cannot open battery opt settings: " + e.getMessage());
                // Fallback: open battery settings page
                try {
                    Intent fallback = new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
                    fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    context.startActivity(fallback);
                } catch (Exception ignored) {}
            }
        }
    }

    // ─── Per-app filtering ────────────────────────────────────────────────────

    private void handleGetInstalledApps(MethodChannel.Result result) {
        bgExecutor.execute(() -> {
            List<Map<String, Object>> apps = new ArrayList<>();
            try {
                PackageManager pm = context.getPackageManager();
                List<ApplicationInfo> installed;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    installed = pm.getInstalledApplications(
                            PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA));
                } else {
                    //noinspection deprecation
                    installed = pm.getInstalledApplications(PackageManager.GET_META_DATA);
                }
                String selfPkg = context.getPackageName();
                for (ApplicationInfo ai : installed) {
                    if (ai.packageName.equals(selfPkg)) continue;
                    // Skip system apps without launcher
                    boolean isSystem = (ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
                    Map<String, Object> app = new HashMap<>();
                    app.put("package", ai.packageName);
                    app.put("name", pm.getApplicationLabel(ai).toString());
                    app.put("isSystem", isSystem);
                    apps.add(app);
                }
            } catch (Exception e) {
                Log.e(TAG, "getInstalledApps error: " + e.getMessage());
            }
            new android.os.Handler(android.os.Looper.getMainLooper())
                    .post(() -> result.success(apps));
        });
    }

    private void handleSetDisallowedApps(MethodCall call, MethodChannel.Result result) {
        List<String> packages = call.argument("packages");
        Set<String> set = packages != null ? new HashSet<>(packages) : new HashSet<>();
        InterGuardPrefs.setDisallowedApps(context, set);
        // Restart VPN to apply new per-app rules if currently running
        InterGuardVpnService svc = InterGuardVpnService.instance;
        if (svc != null && svc.isRunning()) {
            svc.stopTunnel();
            // Restart after brief delay
            new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
                startVpnService();
            }, 500);
        }
        result.success(null);
    }

    // ─── Stats & logs ─────────────────────────────────────────────────────────

    private Map<String, Object> getStats() {
        Map<String, Object> map = new HashMap<>();
        InterGuardVpnService svc = InterGuardVpnService.instance;
        QueryLogger logger = QueryLogger.getInstance();
        map.put("totalQueries",   (int) logger.getTotalQueries());
        map.put("blockedQueries", (int) logger.getBlockedQueries());
        map.put("uptimeMs",       svc != null ? (int) svc.getUptimeMs() : 0);
        return map;
    }

    private List<Map<String, Object>> getLogs() {
        List<QueryLogger.Entry> entries = QueryLogger.getInstance().getEntries();
        List<Map<String, Object>> list = new ArrayList<>(entries.size());
        for (QueryLogger.Entry e : entries) {
            Map<String, Object> m = new HashMap<>();
            m.put("domain",    e.domain);
            m.put("timestamp", e.timestamp);
            m.put("blocked",   e.blocked);
            m.put("type",      e.type);
            list.add(m);
        }
        return list;
    }

    // ─── Misc ─────────────────────────────────────────────────────────────────

    private void handleSetStartOnBoot(MethodCall call, MethodChannel.Result result) {
        Boolean enabled = call.argument("enabled");
        if (enabled != null) InterGuardPrefs.setStartOnBoot(context, enabled);
        result.success(null);
    }

    private void handleTestConnection(MethodCall call, MethodChannel.Result result) {
        String url = call.argument("url");
        if (url == null || url.isEmpty()) {
            Map<String, Object> r = new HashMap<>();
            r.put("success", false); r.put("message", "No URL provided");
            result.success(r); return;
        }
        bgExecutor.execute(() -> {
            Map<String, Object> testResult = DoHForwarder.testConnection(url);
            new android.os.Handler(android.os.Looper.getMainLooper())
                    .post(() -> result.success(testResult));
        });
    }

    private void openVpnSettings() {
        try {
            Intent i = new Intent("android.settings.VPN_SETTINGS");
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(i);
        } catch (Exception e) {
            Log.e(TAG, "Cannot open VPN settings: " + e.getMessage());
        }
    }
}
