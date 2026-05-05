package com.interguard.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.io.IOException;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * InterGuard VPN Service.
 *
 * KEY FIXES vs. original:
 *  1. stopTunnel() now closes the TUN fd BEFORE stopping the processor,
 *     so the blocking read() in DnsPacketProcessor exits via IOException.
 *  2. START_NOT_STICKY when VPN is intentionally off (system-restarted intent
 *     with null action OR vpnEnabled=false) → no background spinning.
 *  3. Virtual IP (172.16.x.x) added to VPN address so AdGuard Home sees
 *     each device individually.
 *  4. Per-app disallow list honoured when building the VPN interface.
 *  5. executor.shutdownNow() + awaitTermination in onDestroy for clean exit.
 */
public class InterGuardVpnService extends VpnService {

    private static final String TAG = "InterGuardVPN";
    public static final String FAKE_DNS_IP = "10.111.222.2";
    public static final String VPN_ADDRESS = "10.111.222.1";
    public static final String VPN_ADDRESS_V6 = "fd00:1:fd00:1:fd00:1:fd00:1";
    public static final String FAKE_DNS_V6 = "fd00:1:fd00:1:fd00:1:fd00:2";
    public static final int VPN_PREFIX_LENGTH = 32;
    public static final int DNS_PORT = 53;
    public static final int MTU = 1280; // Safe for cellular

    private static final String CHANNEL_ID = "interguard_vpn";
    private static final int NOTIF_ID = 1001;

    static final String DEFAULT_DOH_URL = InterGuardPrefs.DEFAULT_BASE_DOH_URL;

    /** Singleton reference used by method channel. */
    static volatile InterGuardVpnService instance = null;

    private ParcelFileDescriptor vpnInterface = null;
    private final AtomicBoolean running = new AtomicBoolean(false);
    private ExecutorService executor;
    private DnsPacketProcessor packetProcessor;
    private DoHForwarder dohForwarder;
    private QueryLogger queryLogger;
    private long startTimeMs = 0;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        queryLogger = QueryLogger.getInstance();
        Log.i(TAG, "InterGuard VPN Service created");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // If restarted by system after process death (intent==null or no explicit action)
        // AND the user has disabled VPN, don't restart — just stop.
        if (!InterGuardPrefs.getVpnEnabled(this)) {
            Log.i(TAG, "VPN disabled by user — stopping service (not restarting)");
            stopSelf();
            return START_NOT_STICKY;
        }

        if (running.get()) {
            Log.i(TAG, "Already running, ignoring start command");
            return START_STICKY;
        }

        String dohUrl = InterGuardPrefs.getDoHUrl(this);
        String fallbackDohUrl = InterGuardPrefs.getFallbackDoHUrl(this);
        String virtualIp = InterGuardPrefs.getVirtualIp(this);
        Log.i(TAG, "Starting VPN with DoH URL: " + dohUrl + " Fallback: " + fallbackDohUrl + " Virtual IP: " + virtualIp);

        dohForwarder = new DoHForwarder(dohUrl, fallbackDohUrl, virtualIp);
        showNotification();

        executor = Executors.newCachedThreadPool();
        executor.execute(this::startVpnTunnel);

        return START_STICKY;
    }

    private void startVpnTunnel() {
        try {
            Builder builder = new Builder();
            builder.setMtu(MTU);

            // Primary VPN address (TUN device IP)
            builder.addAddress(VPN_ADDRESS, VPN_PREFIX_LENGTH);
            
            // IPv6 support (Required for Cellular networks)
            builder.addAddress(VPN_ADDRESS_V6, 128);

            // Virtual client IP for AdGuard Home device identification
            String virtualIp = InterGuardPrefs.getVirtualIp(this);
            try {
                // Add as secondary address so outbound packets carry this IP
                // (works on Android 12+; silently ignored on older versions)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.addAddress(virtualIp, 32);
                }
            } catch (Exception e) {
                Log.w(TAG, "Could not add virtual IP: " + e.getMessage());
            }

            builder.addDnsServer(FAKE_DNS_IP);
            builder.addRoute(FAKE_DNS_IP, 32);

            builder.addDnsServer(FAKE_DNS_V6);
            builder.addRoute(FAKE_DNS_V6, 128);

            builder.setSession("InterGuard");
            builder.allowBypass();

            // Always exclude self so we can reach the DoH server
            try {
                builder.addDisallowedApplication(getPackageName());
            } catch (Exception e) {
                Log.w(TAG, "Could not exclude self: " + e.getMessage());
            }

            // Per-app disallow list (apps that bypass VPN)
            Set<String> disallowedApps = InterGuardPrefs.getDisallowedApps(this);
            for (String pkg : disallowedApps) {
                try {
                    builder.addDisallowedApplication(pkg);
                } catch (Exception e) {
                    Log.w(TAG, "Could not disallow app " + pkg + ": " + e.getMessage());
                }
            }

            vpnInterface = builder.establish();
            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VPN — permission may be revoked");
                stopSelf();
                return;
            }

            running.set(true);
            startTimeMs = System.currentTimeMillis();
            Log.i(TAG, "VPN tunnel established — intercepting DNS. Virtual IP: " + virtualIp);

            InterGuardMethodChannel.sendStatusUpdate(true);

            packetProcessor = new DnsPacketProcessor(
                    vpnInterface, dohForwarder, queryLogger, this);
            packetProcessor.run(executor);

        } catch (Exception e) {
            Log.e(TAG, "VPN tunnel error: " + e.getMessage(), e);
            stopSelf();
        }
    }

    /**
     * CRITICAL FIX: Close the TUN fd FIRST, THEN stop the processor.
     * Closing the fd causes the blocking read() in DnsPacketProcessor to
     * throw IOException, which exits the readLoop naturally.
     * Previous order (stop processor first) left the loop spinning forever.
     */
    public void stopTunnel() {
        running.set(false);
        closeTunnel();           // ← CLOSE FD FIRST (breaks blocking read)
        if (packetProcessor != null) {
            packetProcessor.stop(); // ← THEN stop dispatch executor
            packetProcessor = null;
        }
    }

    private void closeTunnel() {
        if (vpnInterface != null) {
            try {
                vpnInterface.close();
            } catch (IOException e) {
                Log.w(TAG, "Error closing VPN interface: " + e.getMessage());
            }
            vpnInterface = null;
        }
    }

    public boolean isRunning() {
        return running.get() && vpnInterface != null;
    }

    public long getUptimeMs() {
        if (!running.get() || startTimeMs == 0) return 0;
        return System.currentTimeMillis() - startTimeMs;
    }

    public QueryLogger getQueryLogger() {
        return queryLogger;
    }

    public void updateDoHUrl(String url) {
        if (dohForwarder != null) dohForwarder.updateUrl(url);
    }

    public void updateFallbackDoHUrl(String url) {
        if (dohForwarder != null) dohForwarder.updateFallbackUrl(url);
    }

    // ─── Notification ─────────────────────────────────────────────────────────

    private void showNotification() {
        NotificationManager nm = getSystemService(NotificationManager.class);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID, "InterGuard Protection",
                    NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("DNS protection status");
            ch.setShowBadge(false);
            nm.createNotificationChannel(ch);
        }

        Intent tapIntent = new Intent(this, MainActivity.class);
        tapIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pi = PendingIntent.getActivity(
                this, 0, tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification.Builder nb;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nb = new Notification.Builder(this, CHANNEL_ID);
        } else {
            nb = new Notification.Builder(this);
        }

        String deviceName = InterGuardPrefs.getDeviceName(this);
        nb.setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentTitle("InterGuard Active")
                .setContentText("DNS protection enabled · " + deviceName)
                .setContentIntent(pi)
                .setOngoing(true);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            nb.setVisibility(Notification.VISIBILITY_SECRET);
        }

        Notification notif = nb.build();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_NONE);
        } else {
            startForeground(NOTIF_ID, notif);
        }
    }

    @Override
    public void onRevoke() {
        Log.w(TAG, "VPN permission revoked");
        InterGuardPrefs.setVpnEnabled(this, false);
        stopTunnel();
        InterGuardMethodChannel.sendStatusUpdate(false);
        stopSelf();
    }

    @Override
    public void onDestroy() {
        running.set(false);
        stopTunnel();
        if (executor != null) {
            executor.shutdownNow();
            try { executor.awaitTermination(2, TimeUnit.SECONDS); }
            catch (InterruptedException ignored) {}
            executor = null;
        }
        stopForeground(true);
        instance = null;
        InterGuardMethodChannel.sendStatusUpdate(false);
        Log.i(TAG, "VPN service destroyed — all threads stopped");
        super.onDestroy();
    }
}
