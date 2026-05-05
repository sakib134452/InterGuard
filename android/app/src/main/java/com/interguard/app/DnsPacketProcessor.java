package com.interguard.app;

import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Arrays;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Reads raw IP packets from the TUN file descriptor, identifies DNS queries
 * (UDP packets to port 53), forwards them to DoH, and writes responses back.
 */
public class DnsPacketProcessor {

    private static final String TAG = "DnsPacketProcessor";
    private static final int PROTOCOL_UDP = 17;

    private final ParcelFileDescriptor tun;
    private final DoHForwarder dohForwarder;
    private final QueryLogger queryLogger;
    private final InterGuardVpnService service;
    private final AtomicBoolean active = new AtomicBoolean(true);

    // The executor that runs forwardDns tasks (separate from the read loop thread)
    private ExecutorService dispatchExecutor;

    public DnsPacketProcessor(
            ParcelFileDescriptor tun,
            DoHForwarder dohForwarder,
            QueryLogger queryLogger,
            InterGuardVpnService service) {
        this.tun = tun;
        this.dohForwarder = dohForwarder;
        this.queryLogger = queryLogger;
        this.service = service;
    }

    /**
     * Starts the packet read loop on the provided executor.
     * A separate thread pool is used for DoH dispatch so the read loop is never blocked.
     */
    public void run(ExecutorService loopExecutor) {
        // Small fixed pool for DoH dispatch tasks
        dispatchExecutor = java.util.concurrent.Executors.newFixedThreadPool(4);
        loopExecutor.execute(this::readLoop);
    }

    /**
     * Signals the read loop to stop.
     * The actual loop exit happens when closeTunnel() (called before this)
     * closes the underlying file descriptor, causing read() to throw IOException.
     */
    public void stop() {
        active.set(false);
        if (dispatchExecutor != null) {
            dispatchExecutor.shutdownNow();
        }
    }

    private void readLoop() {
        FileInputStream in = null;
        FileOutputStream out = null;
        try {
            in = new FileInputStream(tun.getFileDescriptor());
            out = new FileOutputStream(tun.getFileDescriptor());
            byte[] packetBuf = new byte[InterGuardVpnService.MTU];

            Log.i(TAG, "DNS packet read loop started");

            while (active.get()) {
                int len;
                try {
                    len = in.read(packetBuf);
                } catch (IOException e) {
                    // TUN fd was closed (by stopTunnel) → normal exit
                    if (active.get()) {
                        Log.w(TAG, "Read error (fd closed?): " + e.getMessage());
                    }
                    break;
                }

                if (len <= 0) {
                    if (len == -1) break; // EOF, break instead of spinning
                    try { Thread.sleep(5); } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                    continue;
                }

                byte[] packet = Arrays.copyOf(packetBuf, len);
                processPacket(packet, out);
            }
        } catch (Exception e) {
            if (active.get()) {
                Log.e(TAG, "Unexpected read loop error: " + e.getMessage());
            }
        } finally {
            Log.i(TAG, "DNS packet read loop ended");
            if (in != null) { try { in.close(); } catch (IOException ignored) {} }
            if (out != null) { try { out.close(); } catch (IOException ignored) {} }
        }
    }

    private void processPacket(byte[] data, FileOutputStream out) {
        int len = data.length;
        if (len < 20) return; // Too short to be an IP packet

        int versionIhl = data[0] & 0xFF;
        int version = (versionIhl >> 4) & 0xF;

        if (version == 4) {
            processIpv4(data, len, out);
        } else if (version == 6) {
            processIpv6(data, len, out);
        } else {
            writePacket(out, data, len);
        }
    }

    private void processIpv4(byte[] data, int len, FileOutputStream out) {
        int ihl = (data[0] & 0x0F) * 4;
        if (ihl < 20 || ihl >= len) return;

        int protocol = data[9] & 0xFF;
        if (protocol != PROTOCOL_UDP) {
            writePacket(out, data, len);
            return;
        }

        if (len < ihl + 8) return;
        int dstPort = ((data[ihl + 2] & 0xFF) << 8) | (data[ihl + 3] & 0xFF);

        if (dstPort != InterGuardVpnService.DNS_PORT) {
            writePacket(out, data, len);
            return;
        }

        int udpPayloadOffset = ihl + 8;
        int dnsLen = len - udpPayloadOffset;
        if (dnsLen <= 0) return;

        byte[] dnsQuery = Arrays.copyOfRange(data, udpPayloadOffset, udpPayloadOffset + dnsLen);
        int srcPort = ((data[ihl] & 0xFF) << 8) | (data[ihl + 1] & 0xFF);
        byte[] srcIp = Arrays.copyOfRange(data, 12, 16);
        byte[] dstIp = Arrays.copyOfRange(data, 16, 20);

        forwardDns(dnsQuery, srcIp, dstIp, srcPort, out);
    }

    private void processIpv6(byte[] data, int len, FileOutputStream out) {
        if (len < 40) return; // IPv6 header is 40 bytes

        int nextHeader = data[6] & 0xFF;
        if (nextHeader != PROTOCOL_UDP) {
            writePacket(out, data, len);
            return;
        }

        if (len < 48) return; // 40 + 8 for UDP

        int dstPort = ((data[42] & 0xFF) << 8) | (data[43] & 0xFF);

        if (dstPort != InterGuardVpnService.DNS_PORT) {
            writePacket(out, data, len);
            return;
        }

        int udpPayloadOffset = 48;
        int dnsLen = len - udpPayloadOffset;
        if (dnsLen <= 0) return;

        byte[] dnsQuery = Arrays.copyOfRange(data, udpPayloadOffset, udpPayloadOffset + dnsLen);
        int srcPort = ((data[40] & 0xFF) << 8) | (data[41] & 0xFF);
        byte[] srcIp = Arrays.copyOfRange(data, 8, 24);
        byte[] dstIp = Arrays.copyOfRange(data, 24, 40);

        forwardDns(dnsQuery, srcIp, dstIp, srcPort, out);
    }

    private void forwardDns(byte[] dnsQuery, byte[] srcIp, byte[] dstIp,
                             int srcPort, FileOutputStream out) {
        String domain = DnsParser.extractDomain(dnsQuery);
        long queryTime = System.currentTimeMillis();
        String qtype = DnsParser.extractQueryType(dnsQuery);

        if (dispatchExecutor == null || dispatchExecutor.isShutdown()) return;

        dispatchExecutor.execute(() -> {
            try {
                DoHForwarder.Result result = dohForwarder.forward(dnsQuery);

                boolean blocked = isBlocked(result.response);
                queryLogger.log(domain, queryTime, blocked, qtype);

                if (result.response == null) {
                    Log.w(TAG, "Null DoH response for: " + domain);
                    byte[] servfail = buildServfail(dnsQuery);
                    if (servfail != null) {
                        byte[] responsePacket = buildResponsePacket(servfail, srcIp, dstIp, srcPort);
                        if (responsePacket != null) writePacket(out, responsePacket, responsePacket.length);
                    }
                    return;
                }

                byte[] responsePacket = buildResponsePacket(result.response, srcIp, dstIp, srcPort);
                if (responsePacket != null) {
                    writePacket(out, responsePacket, responsePacket.length);
                }
            } catch (Exception e) {
                Log.e(TAG, "DoH forward error for " + domain + ": " + e.getMessage());
            }
        });
    }

    private boolean isBlocked(byte[] response) {
        if (response == null || response.length < 12) return false;
        int rcode = response[3] & 0x0F;
        if (rcode == 3 || rcode == 5) return true;
        if (rcode != 0) return false;
        int ancount = ((response[6] & 0xFF) << 8) | (response[7] & 0xFF);
        if (ancount == 0) return false;
        return hasNullRouteAnswer(response);
    }

    private boolean hasNullRouteAnswer(byte[] resp) {
        try {
            int qdcount = ((resp[4] & 0xFF) << 8) | (resp[5] & 0xFF);
            int ancount = ((resp[6] & 0xFF) << 8) | (resp[7] & 0xFF);
            int pos = 12;

            // Skip question section
            for (int q = 0; q < qdcount && pos < resp.length; q++) {
                pos = skipName(resp, pos);
                pos += 4; // QTYPE + QCLASS
            }

            // Parse answers
            for (int a = 0; a < ancount && pos < resp.length; a++) {
                pos = skipName(resp, pos);
                
                if (pos + 10 > resp.length) break;
                int rtype = ((resp[pos] & 0xFF) << 8) | (resp[pos + 1] & 0xFF);
                int rdlength = ((resp[pos + 8] & 0xFF) << 8) | (resp[pos + 9] & 0xFF);
                pos += 10;

                if (rtype == 1 && rdlength == 4 && pos + 4 <= resp.length) { // A Record
                    // Check for 0.0.0.0 or 127.0.0.1
                    if (resp[pos] == 0 && resp[pos+1] == 0 && resp[pos+2] == 0 && resp[pos+3] == 0) return true;
                    if (resp[pos] == 127 && resp[pos+1] == 0 && resp[pos+2] == 0 && resp[pos+3] == 1) return true;
                } else if (rtype == 28 && rdlength == 16 && pos + 16 <= resp.length) { // AAAA Record
                    // Check for :: (all zeros) or ::1
                    boolean allZero = true;
                    for (int i = 0; i < 15; i++) if (resp[pos+i] != 0) { allZero = false; break; }
                    if (allZero && (resp[pos+15] == 0 || resp[pos+15] == 1)) return true;
                }
                pos += rdlength;
            }
        } catch (Exception e) {
            Log.w(TAG, "Error parsing DNS response for blocking check: " + e.getMessage());
        }
        return false;
    }

    private int skipName(byte[] resp, int pos) {
        int p = pos;
        while (p < resp.length) {
            int len = resp[p] & 0xFF;
            if (len == 0) {
                p++;
                break;
            } else if ((len & 0xC0) == 0xC0) {
                p += 2; // Compression pointer is always 2 bytes
                break;
            } else {
                p += len + 1;
            }
        }
        return p;
    }

    private byte[] buildServfail(byte[] query) {
        if (query == null || query.length < 2) return null;
        byte[] resp = new byte[12];
        resp[0] = query[0]; resp[1] = query[1]; // Copy ID
        resp[2] = (byte) 0x81; resp[3] = (byte) 0x82; // QR=1, RA=1, RCODE=SERVFAIL(2)
        return resp;
    }

    private byte[] buildResponsePacket(byte[] dnsResponse,
                                        byte[] originalSrcIp,
                                        byte[] originalDstIp,
                                        int originalSrcPort) {
        if (dnsResponse == null) return null;
        boolean isIpv6 = originalSrcIp.length == 16;
        int udpPayloadLen = dnsResponse.length;
        int udpLen = 8 + udpPayloadLen;

        if (isIpv6) {
            int ipLen = 40 + udpLen;
            byte[] packet = new byte[ipLen];

            // IPv6 Header
            packet[0] = 0x60; // Version 6
            packet[1] = 0; packet[2] = 0; packet[3] = 0; // Traffic class & Flow label
            packet[4] = (byte) ((udpLen >> 8) & 0xFF);
            packet[5] = (byte) (udpLen & 0xFF);
            packet[6] = PROTOCOL_UDP; // Next Header
            packet[7] = 64; // Hop Limit
            System.arraycopy(originalDstIp, 0, packet, 8, 16); // Source
            System.arraycopy(originalSrcIp, 0, packet, 24, 16); // Dest

            // UDP Header
            packet[40] = (byte) ((InterGuardVpnService.DNS_PORT >> 8) & 0xFF);
            packet[41] = (byte) (InterGuardVpnService.DNS_PORT & 0xFF);
            packet[42] = (byte) ((originalSrcPort >> 8) & 0xFF);
            packet[43] = (byte) (originalSrcPort & 0xFF);
            packet[44] = (byte) ((udpLen >> 8) & 0xFF);
            packet[45] = (byte) (udpLen & 0xFF);
            
            // Payload
            System.arraycopy(dnsResponse, 0, packet, 48, udpPayloadLen);

            // IPv6 UDP Checksum
            int checksum = ipv6UdpChecksum(originalDstIp, originalSrcIp, packet, 40, udpLen);
            packet[46] = (byte) ((checksum >> 8) & 0xFF);
            packet[47] = (byte) (checksum & 0xFF);

            return packet;
        } else {
            int ipLen = 20 + udpLen;
            byte[] packet = new byte[ipLen];

            packet[0] = 0x45;
            packet[2] = (byte) ((ipLen >> 8) & 0xFF);
            packet[3] = (byte) (ipLen & 0xFF);
            packet[6] = 0x40;
            packet[8] = 64;
            packet[9] = PROTOCOL_UDP;
            System.arraycopy(originalDstIp, 0, packet, 12, 4);
            System.arraycopy(originalSrcIp, 0, packet, 16, 4);

            int checksum = ipChecksum(packet, 0, 20);
            packet[10] = (byte) ((checksum >> 8) & 0xFF);
            packet[11] = (byte) (checksum & 0xFF);

            packet[20] = (byte) ((InterGuardVpnService.DNS_PORT >> 8) & 0xFF);
            packet[21] = (byte) (InterGuardVpnService.DNS_PORT & 0xFF);
            packet[22] = (byte) ((originalSrcPort >> 8) & 0xFF);
            packet[23] = (byte) (originalSrcPort & 0xFF);
            packet[24] = (byte) ((udpLen >> 8) & 0xFF);
            packet[25] = (byte) (udpLen & 0xFF);

            System.arraycopy(dnsResponse, 0, packet, 28, udpPayloadLen);
            return packet;
        }
    }

    private int ipChecksum(byte[] buf, int offset, int length) {
        int sum = 0;
        for (int i = offset; i < offset + length; i += 2) {
            int word = ((buf[i] & 0xFF) << 8);
            if (i + 1 < offset + length) word |= (buf[i + 1] & 0xFF);
            sum += word;
        }
        while ((sum >> 16) != 0) sum = (sum & 0xFFFF) + (sum >> 16);
        return ~sum & 0xFFFF;
    }

    private int ipv6UdpChecksum(byte[] srcIp, byte[] dstIp, byte[] packet, int udpOffset, int udpLen) {
        int sum = 0;
        for (int i = 0; i < 16; i += 2) sum += ((srcIp[i] & 0xFF) << 8) | (srcIp[i+1] & 0xFF);
        for (int i = 0; i < 16; i += 2) sum += ((dstIp[i] & 0xFF) << 8) | (dstIp[i+1] & 0xFF);
        sum += (udpLen >> 16) & 0xFFFF;
        sum += udpLen & 0xFFFF;
        sum += PROTOCOL_UDP;

        for (int i = 0; i < udpLen; i += 2) {
            int word = ((packet[udpOffset + i] & 0xFF) << 8);
            if (i + 1 < udpLen) {
                word |= (packet[udpOffset + i + 1] & 0xFF);
            }
            sum += word;
        }

        while ((sum >> 16) != 0) sum = (sum & 0xFFFF) + (sum >> 16);
        int checksum = ~sum & 0xFFFF;
        return checksum == 0 ? 0xFFFF : checksum;
    }

    private void writePacket(FileOutputStream out, byte[] data, int len) {
        try {
            synchronized (out) {
                out.write(data, 0, len);
            }
        } catch (IOException e) {
            if (active.get()) Log.w(TAG, "Write error: " + e.getMessage());
        }
    }
}
