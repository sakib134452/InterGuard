package com.interguard.app;

import android.util.Log;

import java.io.IOException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

/**
 * Forwards DNS queries as DNS-over-HTTPS (RFC 8484) POST requests.
 * Uses OkHttp to support HTTP/2, which is required by Quad9 as of Dec 2025.
 */
public class DoHForwarder {

    private static final String TAG = "DoHForwarder";
    private static final String CONTENT_TYPE = "application/dns-message";
    private static final MediaType MEDIA_TYPE_DNS = MediaType.parse(CONTENT_TYPE);
    
    private static final int CONNECT_TIMEOUT_MS = 5000;
    private static final int READ_TIMEOUT_MS    = 8000;
    private static final int MAX_RETRIES        = 2;
    private static final long RETRY_DELAY_MS    = 300;

    private final AtomicReference<String> dohUrl;
    private final AtomicReference<String> fallbackUrl;
    private final String clientIp;
    private final OkHttpClient client;

    public DoHForwarder(String url, String fallbackUrl, String clientIp) {
        this.dohUrl = new AtomicReference<>(url);
        this.fallbackUrl = new AtomicReference<>(fallbackUrl != null ? fallbackUrl : "");
        this.clientIp = clientIp;
        
        // OkHttp handles HTTP/2 automatically and performs much better than HttpURLConnection
        this.client = new OkHttpClient.Builder()
                .connectTimeout(CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                .readTimeout(READ_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                .retryOnConnectionFailure(true)
                .build();
    }

    public void updateUrl(String url) {
        this.dohUrl.set(url);
        Log.i(TAG, "DoH URL updated to: " + url);
    }

    public void updateFallbackUrl(String url) {
        this.fallbackUrl.set(url != null ? url : "");
        Log.i(TAG, "DoH Fallback URL updated to: " + url);
    }

    public static class Result {
        public final byte[] response;
        public final int httpStatus;
        public final long latencyMs;

        Result(byte[] response, int httpStatus, long latencyMs) {
            this.response  = response;
            this.httpStatus = httpStatus;
            this.latencyMs = latencyMs;
        }
    }

    /**
     * Performs the DoH POST request with up to MAX_RETRIES retries.
     */
    public Result forward(byte[] dnsQuery) {
        long globalStart = System.currentTimeMillis();
        Result lastResult = null;

        for (int attempt = 0; attempt <= MAX_RETRIES; attempt++) {
            lastResult = forwardOnce(dnsQuery, dohUrl.get());
            if (lastResult.response != null) {
                return lastResult; // Success
            }
            
            if (attempt < MAX_RETRIES) {
                try {
                    Thread.sleep(RETRY_DELAY_MS * (attempt + 1));
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }

        String fbUrl = fallbackUrl.get();
        if (fbUrl != null && !fbUrl.isEmpty()) {
            Result fbResult = forwardOnce(dnsQuery, fbUrl);
            if (fbResult.response != null) {
                return fbResult; // Success with fallback
            }
        }

        return lastResult != null ? lastResult
                : new Result(null, -1, System.currentTimeMillis() - globalStart);
    }

    private Result forwardOnce(byte[] dnsQuery, String url) {
        long start = System.currentTimeMillis();
        
        try {
            RequestBody body = RequestBody.create(dnsQuery, MEDIA_TYPE_DNS);
            Request request = new Request.Builder()
                    .url(url)
                    .post(body)
                    .header("Content-Type", CONTENT_TYPE)
                    .header("Accept", CONTENT_TYPE)
                    .header("X-Forwarded-For", clientIp)
                    .build();

            try (Response response = client.newCall(request).execute()) {
                long latency = System.currentTimeMillis() - start;
                int status = response.code();

                if (response.isSuccessful() && response.body() != null) {
                    byte[] responseData = response.body().bytes();
                    return new Result(responseData, status, latency);
                } else {
                    Log.w(TAG, "DoH HTTP " + status + " for: " + url);
                    return new Result(null, status, latency);
                }
            }
        } catch (Exception e) {
            long latency = System.currentTimeMillis() - start;
            Log.w(TAG, "DoH request failed: " + e.getMessage());
            return new Result(null, -1, latency);
        }
    }

    /** Tests the DoH connection by sending an A query for example.com. */
    public static java.util.Map<String, Object> testConnection(String url) {
        java.util.Map<String, Object> map = new java.util.HashMap<>();
        byte[] testQuery = buildTestQuery();
        DoHForwarder forwarder = new DoHForwarder(url, "", "127.0.0.1");
        long start = System.currentTimeMillis();

        try {
            Result result = forwarder.forward(testQuery);
            long elapsed = System.currentTimeMillis() - start;

            if (result.response != null && result.response.length >= 4) {
                map.put("success", true);
                map.put("latencyMs", (int) result.latencyMs);
                map.put("message", "Resolved in " + result.latencyMs + "ms");
            } else {
                map.put("success", false);
                map.put("latencyMs", (int) elapsed);
                map.put("message", "Server returned HTTP " + result.httpStatus);
            }
        } catch (Exception e) {
            map.put("success", false);
            map.put("latencyMs", 0);
            map.put("message", e.getMessage() != null ? e.getMessage() : "Unknown error");
        }
        return map;
    }

    private static byte[] buildTestQuery() {
        return new byte[]{
            0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x07, 'e','x','a','m','p','l','e',
            0x03, 'c','o','m', 0x00,
            0x00, 0x01, 0x00, 0x01
        };
    }
}
