package com.interguard.app;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;

public class MainActivity extends FlutterActivity {

    private static final String TAG = "MainActivity";
    private static final int VPN_REQUEST_CODE = 9000;

    private InterGuardMethodChannel methodChannel;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        methodChannel = new InterGuardMethodChannel(this, this);
        methodChannel.register(flutterEngine);
        Log.i(TAG, "Flutter engine configured with InterGuard method channels");
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == RESULT_OK) {
                Log.i(TAG, "VPN permission granted — starting service");
                if (methodChannel != null) {
                    methodChannel.startVpnService();
                }
                InterGuardMethodChannel.sendStatusUpdate(true);
            } else {
                Log.w(TAG, "VPN permission denied by user");
                InterGuardMethodChannel.sendStatusUpdate(false);
            }
        }
    }
}
