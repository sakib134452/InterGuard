package com.interguard.app;

import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Reads raw IP packets from the TUN file descriptor, identifies DNS queries
 * (UDP packets to port 53 targeting our fake DNS IP), forwards them to DoH,
 * and writes response packets back through the TUN interface.
 *
 * IP packet structure:
 *   Byte 0: Version (upper 4 bits) + IHL (lower 4 bits, in 32-bit words)
 *   Bytes 9: Protocol (17 = UDP)
 *   Bytes 12-15: Source IP
 *   Bytes 16-19: Dest IP
 *   [IP options if IHL > 5]
 *   UDP header (8 bytes): src port, dst port, length, checksum
 *   UDP payload = raw DNS message
 */
public class DnsPacketProcessor {

    private static final String TAG = "DnsPacketProcessor";
    private static final int PROTOCOL_UDP = 17;

    private final ParcelFileDescriptor tun;
    private final DoHForwarder dohForwarder;
    private final QueryLogger queryLogger;
    private final InterGuardVpnService service;
    private final AtomicBoolean active = new AtomicBoolean(true);
    private final ExecutorService executor;

    public DnsPacketProcessor(
            ParcelFileDescriptor tun,
            DoHForwarder dohForwarder,
            QueryLogger queryLogger,
            InterGuardVpnService service) {
        this.tun = tun;
        this.dohForwarder = dohForwarder;
        this.queryLogger = queryLogger;
        this.service = service;
        this.executor = java.util.concurrent.Executors.newCachedThreadPool();
    }

    public void run(ExecutorService executor) {
        executor.execute(this::readLoop);
    }

    public void stop() {
        active.set(false);
        if (executor != null) {
            executor.shutdownNow();
        }
    }

    private void readLoop() {
        FileInputStream in = new FileInputStream(tun.getFileDescriptor());
        FileOutputStream out = new FileOutputStream(tun.getFileDescriptor());
        ByteBuffer packet = ByteBuffer.allocate(InterGuardVpnService.MTU);

        Log.i(TAG, "DNS packet read loop started");

        while (active.get()) {
            packet.clear();
            try {
                int len = in.read(packet.array());
                if (len <= 0) continue;
                packet.limit(len);

                processPacket(packet, out);
            } catch (IOException e) {
                if (active.get()) {
                    Log.w(TAG, "Read error: " + e.getMessage());
                }
                break;
            }
        }

        Log.i(TAG, "DNS packet read loop ended");
        try { in.close(); } catch (IOException ignored) {}
        try { out.close(); } catch (IOException ignored) {}
    }

    private void processPacket(ByteBuffer packet, FileOutputStream out) throws IOException {
        if (packet.limit() < 20) return; // Too short to be an IP packet

        byte[] data = packet.array();
        int len = packet.limit();

        // Parse IP header
        int versionIhl = data[0] & 0xFF;
        int version = (versionIhl >> 4) & 0xF;
        if (version != 4) return; // Only IPv4 for now

        int ihl = (versionIhl & 0x0F) * 4; // Header length in bytes
        if (ihl < 20 || ihl >= len) return;

        int protocol = data[9] & 0xFF;
        if (protocol != PROTOCOL_UDP) {
            // Pass non-UDP through unchanged
            writePacket(out, data, len);
            return;
        }

        // Parse UDP header (starts at ihl offset)
        if (len < ihl + 8) return;
        int srcPort = ((data[ihl] & 0xFF) << 8) | (data[ihl + 1] & 0xFF);
        int dstPort = ((data[ihl + 2] & 0xFF) << 8) | (data[ihl + 3] & 0xFF);

        if (dstPort != InterGuardVpnService.DNS_PORT) {
            // Not DNS — pass through
            writePacket(out, data, len);
            return;
        }

        // Extract DNS query payload
        int udpPayloadOffset = ihl + 8;
        int dnsLen = len - udpPayloadOffset;
        if (dnsLen <= 0) return;

        byte[] dnsQuery = Arrays.copyOfRange(data, udpPayloadOffset, udpPayloadOffset + dnsLen);

        // Extract source IP and port for response routing
        byte[] srcIp = Arrays.copyOfRange(data, 12, 16);
        byte[] dstIp = Arrays.copyOfRange(data, 16, 20);

        // Forward to DoH in background, write response back to TUN
        forwardDns(dnsQuery, srcIp, dstIp, srcPort, out);
    }

    private void forwardDns(byte[] dnsQuery,
                             byte[] srcIp,
                             byte[] dstIp,
                             int srcPort,
                             FileOutputStream out) {
        String domain = DnsParser.extractDomain(dnsQuery);
        long queryTime = System.currentTimeMillis();

        executor.execute(() -> {
            try {
            DoHForwarder.Result result = dohForwarder.forward(dnsQuery);

            // Log query
            boolean blocked = isBlocked(result.response);
            queryLogger.log(domain, queryTime, blocked,
                    DnsParser.extractQueryType(dnsQuery));

            if (result.response == null) {
                Log.w(TAG, "Null DoH response for: " + domain);
                return;
            }

            // Build response IP packet and write to TUN
            byte[] responsePacket = buildResponsePacket(
                    result.response, srcIp, dstIp, srcPort);
            if (responsePacket != null) {
                writePacket(out, responsePacket, responsePacket.length);
            }

        } catch (Exception e) {
            Log.e(TAG, "DoH forward error for " + domain + ": " + e.getMessage());
        }
        });
    }

    /**
     * Builds a UDP/IP response packet to send back through TUN.
     * Swaps source/dest so the response looks like it came from our fake DNS IP.
     */
    private byte[] buildResponsePacket(byte[] dnsResponse,
                                        byte[] originalSrcIp,
                                        byte[] originalDstIp,
                                        int originalSrcPort) {
        if (dnsResponse == null) return null;

        int udpPayloadLen = dnsResponse.length;
        int udpLen = 8 + udpPayloadLen;
        int ipLen = 20 + udpLen;

        byte[] packet = new byte[ipLen];

        // ── IP header ────────────────────────────────────────────────────────
        packet[0] = 0x45;                        // Version=4, IHL=5
        packet[1] = 0;                            // DSCP/ECN
        packet[2] = (byte) ((ipLen >> 8) & 0xFF);
        packet[3] = (byte) (ipLen & 0xFF);
        packet[4] = 0; packet[5] = 0;            // Identification
        packet[6] = 0x40; packet[7] = 0;        // Flags: Don't fragment
        packet[8] = 64;                           // TTL
        packet[9] = PROTOCOL_UDP;                 // Protocol
        // Checksum (bytes 10-11) — fill after
        // Source IP = original dst (our fake DNS IP)
        System.arraycopy(originalDstIp, 0, packet, 12, 4);
        // Dest IP = original src (the app's IP)
        System.arraycopy(originalSrcIp, 0, packet, 16, 4);

        // IP checksum
        int checksum = ipChecksum(packet, 0, 20);
        packet[10] = (byte) ((checksum >> 8) & 0xFF);
        packet[11] = (byte) (checksum & 0xFF);

        // ── UDP header ───────────────────────────────────────────────────────
        // Source port = DNS port (53)
        packet[20] = (byte) ((InterGuardVpnService.DNS_PORT >> 8) & 0xFF);
        packet[21] = (byte) (InterGuardVpnService.DNS_PORT & 0xFF);
        // Dest port = original source port
        packet[22] = (byte) ((originalSrcPort >> 8) & 0xFF);
        packet[23] = (byte) (originalSrcPort & 0xFF);
        // UDP length
        packet[24] = (byte) ((udpLen >> 8) & 0xFF);
        packet[25] = (byte) (udpLen & 0xFF);
        // UDP checksum — can be zero for IPv4
        packet[26] = 0;
        packet[27] = 0;

        // ── DNS payload ──────────────────────────────────────────────────────
        System.arraycopy(dnsResponse, 0, packet, 28, udpPayloadLen);

        return packet;
    }

    private int ipChecksum(byte[] buf, int offset, int length) {
        int sum = 0;
        for (int i = offset; i < offset + length; i += 2) {
            int word = ((buf[i] & 0xFF) << 8);
            if (i + 1 < offset + length) {
                word |= (buf[i + 1] & 0xFF);
            }
            sum += word;
        }
        while ((sum >> 16) != 0) {
            sum = (sum & 0xFFFF) + (sum >> 16);
        }
        return ~sum & 0xFFFF;
    }

    private boolean isBlocked(byte[] response) {
        if (response == null || response.length < 4) return false;
        // RCODE = lower 4 bits of byte 3
        int rcode = response[3] & 0x0F;
        // NXDOMAIN (3) = blocked by upstream AdGuard Home
        if (rcode == 3) return true;
        // Check if answer count is 0 with NOERROR — also effectively blocked
        if (response.length >= 8) {
            int ancount = ((response[6] & 0xFF) << 8) | (response[7] & 0xFF);
            return ancount == 0 && rcode == 0;
        }
        return false;
    }

    private void writePacket(FileOutputStream out, byte[] data, int len) {
        try {
            synchronized (out) {
                out.write(data, 0, len);
            }
        } catch (IOException e) {
            Log.w(TAG, "Write error: " + e.getMessage());
        }
    }
}
