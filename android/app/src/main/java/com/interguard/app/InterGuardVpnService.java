package com.interguard.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * InterGuard VPN Service — intercepts all DNS queries (UDP port 53),
 * forwards them as DoH (RFC 8484) to the configured server, and returns answers.
 *
 * Architecture (rewritten from Intra's approach, no Go dependency):
 *   1. Build VPN tunnel via VpnService.Builder
 *   2. Set fake DNS IP (10.111.222.2) so all DNS traffic comes through TUN
 *   3. Read raw IP packets from TUN file descriptor
 *   4. Detect UDP/port-53 packets → extract DNS payload
 *   5. POST DNS wire format to DoH server (RFC 8484, OkHttp)
 *   6. Write DNS response back through TUN fd
 */
public class InterGuardVpnService extends VpnService {

    private static final String TAG = "InterGuardVPN";
    public static final String FAKE_DNS_IP = "10.111.222.2";
    public static final String VPN_ADDRESS = "10.111.222.1";
    public static final int VPN_PREFIX_LENGTH = 32;
    public static final int DNS_PORT = 53;
    public static final int MTU = 1500;

    private static final String CHANNEL_ID = "interguard_vpn";
    private static final int NOTIF_ID = 1001;

    // Default DoH server
    static final String DEFAULT_DOH_URL = "https://dns.sacloudserver.top/dns-query";

    // Singleton reference for method channel access
    static volatile InterGuardVpnService instance = null;

    private ParcelFileDescriptor vpnInterface = null;
    private final AtomicBoolean running = new AtomicBoolean(false);
    private ExecutorService executor;
    private DnsPacketProcessor packetProcessor;
    private DoHForwarder dohForwarder;
    private QueryLogger queryLogger;
    private long startTimeMs = 0;
    
    private ConnectivityManager connectivityManager;
    private ConnectivityManager.NetworkCallback networkCallback;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        queryLogger = QueryLogger.getInstance();
        connectivityManager = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        Log.i(TAG, "InterGuard VPN Service created");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (running.get()) {
            Log.i(TAG, "Already running, ignoring start command");
            return START_STICKY;
        }

        String dohUrl = InterGuardPrefs.getDoHUrl(this);
        Log.i(TAG, "Starting VPN with DoH URL: " + dohUrl);

        dohForwarder = new DoHForwarder(dohUrl);

        // Show persistent notification
        showNotification();

        // Start VPN in background thread
        executor = Executors.newCachedThreadPool();
        executor.execute(this::startVpnTunnel);

        return START_STICKY;
    }

    private void startVpnTunnel() {
        try {
            // Build TUN interface
            Builder builder = new Builder();
            builder.setMtu(MTU);
            builder.addAddress(VPN_ADDRESS, VPN_PREFIX_LENGTH);
            builder.addDnsServer(FAKE_DNS_IP);
            builder.addRoute(FAKE_DNS_IP, 32);   // Only route the fake DNS IP
            builder.setSession("InterGuard");
            builder.allowBypass();

            // Exclude ourselves so we can reach the DoH server
            try {
                builder.addDisallowedApplication(getPackageName());
            } catch (Exception e) {
                Log.w(TAG, "Could not exclude self: " + e.getMessage());
            }

            vpnInterface = builder.establish();
            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VPN interface — permission may be revoked");
                stopSelf();
                return;
            }

            running.set(true);
            startTimeMs = System.currentTimeMillis();
            Log.i(TAG, "VPN tunnel established — intercepting DNS");

            // Notify Flutter
            InterGuardMethodChannel.sendStatusUpdate(true);

            // Register network callback for graceful switching (WiFi <-> Mobile)
            registerNetworkCallback();

            // Start reading packets from TUN
            packetProcessor = new DnsPacketProcessor(
                    vpnInterface, dohForwarder, queryLogger, this);
            packetProcessor.run(executor);

        } catch (Exception e) {
            Log.e(TAG, "VPN tunnel error: " + e.getMessage(), e);
            stopSelf();
        }
    }

    private void registerNetworkCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            networkCallback = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onAvailable(Network network) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                        setUnderlyingNetworks(new Network[]{network});
                    }
                    Log.i(TAG, "Network available, setting underlying network");
                }

                @Override
                public void onLost(Network network) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                        setUnderlyingNetworks(null);
                    }
                    Log.i(TAG, "Network lost, removing underlying network");
                }
            };
            try {
                connectivityManager.registerDefaultNetworkCallback(networkCallback);
            } catch (Exception e) {
                Log.w(TAG, "Could not register network callback", e);
            }
        }
    }

    private void unregisterNetworkCallback() {
        if (networkCallback != null && connectivityManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                connectivityManager.unregisterNetworkCallback(networkCallback);
            } catch (Exception e) {
                Log.w(TAG, "Could not unregister network callback", e);
            }
            networkCallback = null;
        }
    }

    public void stopTunnel() {
        running.set(false);
        unregisterNetworkCallback();
        if (packetProcessor != null) {
            packetProcessor.stop();
        }
        closeTunnel();
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
        if (dohForwarder != null) {
            dohForwarder.updateUrl(url);
        }
    }

    // ─── Notification ─────────────────────────────────────────────────────────

    private void showNotification() {
        NotificationManager nm = getSystemService(NotificationManager.class);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID,
                    "InterGuard Protection",
                    NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("VPN protection status");
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

        nb.setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentTitle("InterGuard Active")
                .setContentText("Blocking ads by DNS")
                .setContentIntent(pi)
                .setOngoing(true);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            nb.setVisibility(Notification.VISIBILITY_SECRET);
        }

        Notification notif = nb.build();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_NONE);
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
        if (executor != null) executor.shutdownNow();
        stopForeground(true);
        instance = null;
        InterGuardMethodChannel.sendStatusUpdate(false);
        Log.i(TAG, "VPN service destroyed");
        super.onDestroy();
    }
}
