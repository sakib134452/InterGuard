package com.interguard.app;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.VpnService;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Handles all Flutter <-> Android method channel communication.
 *
 * Method channel: com.interguard.app/vpn
 * Event channel:  com.interguard.app/vpn_status
 *
 * Supported methods:
 *   startVpn         → Boolean
 *   stopVpn          → void
 *   isVpnRunning     → Boolean
 *   getStats         → Map{totalQueries, blockedQueries, uptimeMs}
 *   getLogs          → List<Map{domain, timestamp, blocked, type}>
 *   clearLogs        → void
 *   setDoHUrl        → void
 *   getDoHUrl        → String
 *   setStartOnBoot   → void
 *   getStartOnBoot   → Boolean
 *   testConnection   → Map{success, latencyMs, message}
 *   openVpnSettings  → void
 */
public class InterGuardMethodChannel {

    private static final String TAG = "IGMethodChannel";
    public static final String CHANNEL = "com.interguard.app/vpn";
    public static final String EVENT_CHANNEL = "com.interguard.app/vpn_status";
    private static final int VPN_REQUEST_CODE = 9000;

    private static volatile EventChannel.EventSink eventSink = null;
    private static final ExecutorService bgExecutor = Executors.newCachedThreadPool();

    private final Context context;
    private final Activity activity;

    public InterGuardMethodChannel(Context context, Activity activity) {
        this.context = context;
        this.activity = activity;
    }

    public void register(FlutterEngine engine) {
        // Method channel
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler(this::handleMethod);

        // Event channel (VPN status updates pushed from native → Flutter)
        new EventChannel(engine.getDartExecutor().getBinaryMessenger(), EVENT_CHANNEL)
                .setStreamHandler(new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object args, EventChannel.EventSink sink) {
                        eventSink = sink;
                    }

                    @Override
                    public void onCancel(Object args) {
                        eventSink = null;
                    }
                });
    }

    /** Called from VPN service to push status to Flutter. */
    public static void sendStatusUpdate(boolean isRunning) {
        EventChannel.EventSink sink = eventSink;
        if (sink != null) {
            // Event sink must be called on main thread
            android.os.Handler main = new android.os.Handler(
                    android.os.Looper.getMainLooper());
            main.post(() -> {
                try {
                    sink.success(isRunning);
                } catch (Exception e) {
                    Log.w(TAG, "Event sink error: " + e.getMessage());
                }
            });
        }
    }

    private void handleMethod(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {

            case "startVpn":
                handleStartVpn(result);
                break;

            case "stopVpn":
                stopVpn();
                result.success(null);
                break;

            case "isVpnRunning":
                result.success(isVpnRunning());
                break;

            case "getStats":
                result.success(getStats());
                break;

            case "getLogs":
                result.success(getLogs());
                break;

            case "clearLogs":
                QueryLogger.getInstance().clear();
                result.success(null);
                break;

            case "setDoHUrl": {
                String url = call.argument("url");
                if (url != null) {
                    InterGuardPrefs.setDoHUrl(context, url);
                    if (InterGuardVpnService.instance != null) {
                        InterGuardVpnService.instance.updateDoHUrl(url);
                    }
                }
                result.success(null);
                break;
            }

            case "getDoHUrl":
                result.success(InterGuardPrefs.getDoHUrl(context));
                break;

            case "setStartOnBoot": {
                Boolean enabled = call.argument("enabled");
                if (enabled != null) {
                    InterGuardPrefs.setStartOnBoot(context, enabled);
                }
                result.success(null);
                break;
            }

            case "getStartOnBoot":
                result.success(InterGuardPrefs.getStartOnBoot(context));
                break;

            case "testConnection":
                handleTestConnection(call, result);
                break;

            case "openVpnSettings":
                openVpnSettings();
                result.success(null);
                break;

            default:
                result.notImplemented();
        }
    }

    private void handleStartVpn(MethodChannel.Result result) {
        // Check if VPN permission is already granted
        Intent prepareIntent = VpnService.prepare(context);
        if (prepareIntent == null) {
            // Permission already granted — start directly
            startVpnService();
            result.success(true);
        } else {
            // Need to request VPN permission from user
            // We'll start it anyway and handle in MainActivity.onActivityResult
            activity.startActivityForResult(prepareIntent, VPN_REQUEST_CODE);
            // For now, return true optimistically; MainActivity will handle the callback
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
        if (svc != null) {
            svc.stopTunnel();
        }
        Intent intent = new Intent(context, InterGuardVpnService.class);
        context.stopService(intent);
    }

    private boolean isVpnRunning() {
        InterGuardVpnService svc = InterGuardVpnService.instance;
        return svc != null && svc.isRunning();
    }

    private Map<String, Object> getStats() {
        Map<String, Object> map = new HashMap<>();
        InterGuardVpnService svc = InterGuardVpnService.instance;
        QueryLogger logger = QueryLogger.getInstance();

        map.put("totalQueries", (int) logger.getTotalQueries());
        map.put("blockedQueries", (int) logger.getBlockedQueries());
        map.put("uptimeMs", svc != null ? (int) svc.getUptimeMs() : 0);
        return map;
    }

    private List<Map<String, Object>> getLogs() {
        List<QueryLogger.Entry> entries = QueryLogger.getInstance().getEntries();
        List<Map<String, Object>> list = new ArrayList<>(entries.size());
        for (QueryLogger.Entry e : entries) {
            Map<String, Object> m = new HashMap<>();
            m.put("domain", e.domain);
            m.put("timestamp", e.timestamp);
            m.put("blocked", e.blocked);
            m.put("type", e.type);
            list.add(m);
        }
        return list;
    }

    private void handleTestConnection(MethodCall call, MethodChannel.Result result) {
        String url = call.argument("url");
        if (url == null || url.isEmpty()) {
            Map<String, Object> r = new HashMap<>();
            r.put("success", false);
            r.put("message", "No URL provided");
            result.success(r);
            return;
        }
        // Run on background thread
        final String testUrl = url;
        bgExecutor.execute(() -> {
            Map<String, Object> testResult = DoHForwarder.testConnection(testUrl);
            android.os.Handler main =
                    new android.os.Handler(android.os.Looper.getMainLooper());
            main.post(() -> result.success(testResult));
        });
    }

    private void openVpnSettings() {
        try {
            Intent intent = new Intent("android.settings.VPN_SETTINGS");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
        } catch (Exception e) {
            Log.e(TAG, "Cannot open VPN settings: " + e.getMessage());
        }
    }
}
