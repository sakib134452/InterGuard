package com.interguard.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.VpnService;
import android.os.Build;
import android.util.Log;

/**
 * Boot receiver — auto-starts the VPN service after device reboot
 * if "Start on Boot" is enabled and VPN permission was already granted.
 */
public class BootReceiver extends BroadcastReceiver {

    private static final String TAG = "BootReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !"android.intent.action.MY_PACKAGE_REPLACED".equals(action)) {
            return;
        }

        Log.d(TAG, "Boot event received: " + action);

        if (!InterGuardPrefs.getStartOnBoot(context)) {
            Log.d(TAG, "Start-on-boot disabled — skipping autostart");
            return;
        }

        if (!InterGuardPrefs.getVpnEnabled(context)) {
            Log.d(TAG, "Protection was manually turned off before reboot — skipping autostart");
            return;
        }

        // Check if VPN permission is already granted (prepare returns null = granted)
        Intent prepareIntent = VpnService.prepare(context);
        if (prepareIntent != null) {
            Log.w(TAG, "VPN permission not granted — cannot autostart. "
                    + "Launching main activity for user confirmation.");
            Intent ui = new Intent(context, MainActivity.class);
            ui.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(ui);
            return;
        }

        Log.d(TAG, "Autostarting InterGuard VPN service");
        InterGuardPrefs.setVpnEnabled(context, true);

        Intent serviceIntent = new Intent(context, InterGuardVpnService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent);
        } else {
            context.startService(serviceIntent);
        }
    }
}
