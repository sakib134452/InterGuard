package com.interguard.app;

import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Forwards DNS queries as DNS-over-HTTPS (RFC 8484) POST requests.
 * Content-Type: application/dns-message
 * Method: POST
 * Body: raw DNS wire-format query
 * Response: raw DNS wire-format answer
 */
public class DoHForwarder {

    private static final String TAG = "DoHForwarder";
    private static final String CONTENT_TYPE = "application/dns-message";
    private static final int CONNECT_TIMEOUT_MS = 5000;
    private static final int READ_TIMEOUT_MS = 10000;

    private final AtomicReference<String> dohUrl;

    public DoHForwarder(String url) {
        this.dohUrl = new AtomicReference<>(url);
    }

    public void updateUrl(String url) {
        this.dohUrl.set(url);
        Log.i(TAG, "DoH URL updated to: " + url);
    }

    public static class Result {
        public final byte[] response;
        public final int httpStatus;
        public final long latencyMs;

        Result(byte[] response, int httpStatus, long latencyMs) {
            this.response = response;
            this.httpStatus = httpStatus;
            this.latencyMs = latencyMs;
        }
    }

    /**
     * Performs the DoH POST request synchronously.
     * Must be called from a background thread.
     */
    public Result forward(byte[] dnsQuery) {
        String url = dohUrl.get();
        long start = System.currentTimeMillis();

        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
            conn.setReadTimeout(READ_TIMEOUT_MS);
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", CONTENT_TYPE);
            conn.setRequestProperty("Accept", CONTENT_TYPE);
            conn.setRequestProperty("Content-Length", String.valueOf(dnsQuery.length));
            conn.setDoOutput(true);
            conn.setDoInput(true);
            conn.setUseCaches(false);

            // Write DNS query
            conn.getOutputStream().write(dnsQuery);
            conn.getOutputStream().flush();

            int status = conn.getResponseCode();
            long latency = System.currentTimeMillis() - start;

            if (status == 200) {
                byte[] response = readStream(conn.getInputStream());
                return new Result(response, status, latency);
            } else {
                Log.w(TAG, "DoH returned HTTP " + status + " for URL: " + url);
                return new Result(null, status, latency);
            }

        } catch (Exception e) {
            long latency = System.currentTimeMillis() - start;
            Log.e(TAG, "DoH request failed: " + e.getMessage());
            return new Result(null, -1, latency);
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    /**
     * Test the DoH connection by sending a real DNS query for "dns.google."
     * Returns a result map: {success, latencyMs, message}
     */
    public static java.util.Map<String, Object> testConnection(String url) {
        java.util.Map<String, Object> map = new java.util.HashMap<>();

        // Build a minimal DNS A query for "example.com"
        byte[] testQuery = buildTestQuery();

        DoHForwarder forwarder = new DoHForwarder(url);
        long start = System.currentTimeMillis();

        try {
            Result result = forwarder.forward(testQuery);
            long elapsed = System.currentTimeMillis() - start;

            if (result.response != null && result.response.length >= 4) {
                map.put("success", true);
                map.put("latencyMs", (int) result.latencyMs);
                map.put("message", "Resolved successfully in " + result.latencyMs + "ms");
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

    /** Builds a standard DNS A query for "example.com" for testing. */
    private static byte[] buildTestQuery() {
        // Wire format DNS query for example.com A record
        return new byte[]{
            0x00, 0x01,  // ID = 1
            0x01, 0x00,  // Flags: RD (recursion desired)
            0x00, 0x01,  // QDCOUNT = 1
            0x00, 0x00,  // ANCOUNT = 0
            0x00, 0x00,  // NSCOUNT = 0
            0x00, 0x00,  // ARCOUNT = 0
            // QNAME: example.com
            0x07, 'e','x','a','m','p','l','e',
            0x03, 'c','o','m',
            0x00,        // Root label
            0x00, 0x01,  // QTYPE = A
            0x00, 0x01   // QCLASS = IN
        };
    }

    private static byte[] readStream(InputStream is) throws java.io.IOException {
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        byte[] tmp = new byte[4096];
        int n;
        while ((n = is.read(tmp)) != -1) {
            buf.write(tmp, 0, n);
        }
        return buf.toByteArray();
    }
}
