package com.interguard.app;

import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Forwards DNS queries as DNS-over-HTTPS (RFC 8484) POST requests.
 * Includes retry logic with exponential backoff to handle transient
 * connectivity issues (e.g., WiFi/mobile switching, temporary failures).
 */
public class DoHForwarder {

    private static final String TAG = "DoHForwarder";
    private static final String CONTENT_TYPE = "application/dns-message";
    private static final int CONNECT_TIMEOUT_MS = 5000;
    private static final int READ_TIMEOUT_MS    = 8000;
    private static final int MAX_RETRIES        = 2;
    private static final long RETRY_DELAY_MS    = 300;

    private final AtomicReference<String> dohUrl;
    private final AtomicReference<String> fallbackUrl;
    private final String clientIp;

    public DoHForwarder(String url, String fallbackUrl, String clientIp) {
        this.dohUrl = new AtomicReference<>(url);
        this.fallbackUrl = new AtomicReference<>(fallbackUrl != null ? fallbackUrl : "");
        this.clientIp = clientIp;
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
     * Must be called from a background thread.
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
        HttpURLConnection conn = null;

        try {
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
            conn.setReadTimeout(READ_TIMEOUT_MS);
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", CONTENT_TYPE);
            conn.setRequestProperty("Accept", CONTENT_TYPE);
            conn.setRequestProperty("X-Forwarded-For", clientIp);
            conn.setRequestProperty("Content-Length", String.valueOf(dnsQuery.length));
            conn.setDoOutput(true);
            conn.setDoInput(true);
            conn.setUseCaches(false);

            conn.getOutputStream().write(dnsQuery);
            conn.getOutputStream().flush();

            int status = conn.getResponseCode();
            long latency = System.currentTimeMillis() - start;

            if (status == 200) {
                byte[] response = readStream(conn.getInputStream());
                return new Result(response, status, latency);
            } else {
                Log.w(TAG, "DoH HTTP " + status + " for: " + url);
                return new Result(null, status, latency);
            }

        } catch (Exception e) {
            long latency = System.currentTimeMillis() - start;
            Log.w(TAG, "DoH request failed: " + e.getMessage());
            return new Result(null, -1, latency);
        } finally {
            if (conn != null) conn.disconnect();
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

    private static byte[] readStream(InputStream is) throws java.io.IOException {
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        byte[] tmp = new byte[4096];
        int n;
        while ((n = is.read(tmp)) != -1) buf.write(tmp, 0, n);
        return buf.toByteArray();
    }
}
