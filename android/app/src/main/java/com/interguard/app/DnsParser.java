package com.interguard.app;

/**
 * Parses minimal DNS wire-format fields needed for logging.
 * DNS wire format:
 *   Header: 12 bytes
 *   Questions: QDCOUNT records
 *     QNAME (labels), QTYPE (2 bytes), QCLASS (2 bytes)
 */
public class DnsParser {

    private DnsParser() {}

    /**
     * Extracts the queried domain name from raw DNS query bytes.
     * Returns empty string on any parse error.
     */
    public static String extractDomain(byte[] dns) {
        if (dns == null || dns.length < 13) return "";
        try {
            StringBuilder sb = new StringBuilder();
            int pos = 12; // Skip DNS header (12 bytes)
            while (pos < dns.length) {
                int labelLen = dns[pos] & 0xFF;
                if (labelLen == 0) break;          // Root label = end
                if ((labelLen & 0xC0) == 0xC0) break; // Compression pointer (shouldn't appear in query)
                pos++;
                if (pos + labelLen > dns.length) break;
                if (sb.length() > 0) sb.append('.');
                sb.append(new String(dns, pos, labelLen));
                pos += labelLen;
            }
            return sb.toString();
        } catch (Exception e) {
            return "";
        }
    }

    /**
     * Extracts the QTYPE from the first DNS question.
     * Returns type name string, e.g. "A", "AAAA", "MX", etc.
     */
    public static String extractQueryType(byte[] dns) {
        if (dns == null || dns.length < 13) return "?";
        try {
            int pos = 12;
            // Skip QNAME
            while (pos < dns.length) {
                int len = dns[pos] & 0xFF;
                if (len == 0) { pos++; break; }
                if ((len & 0xC0) == 0xC0) { pos += 2; break; }
                pos += 1 + len;
            }
            if (pos + 2 > dns.length) return "?";
            int qtype = ((dns[pos] & 0xFF) << 8) | (dns[pos + 1] & 0xFF);
            return qtypeName(qtype);
        } catch (Exception e) {
            return "?";
        }
    }

    private static String qtypeName(int qtype) {
        switch (qtype) {
            case 1:   return "A";
            case 2:   return "NS";
            case 5:   return "CNAME";
            case 6:   return "SOA";
            case 12:  return "PTR";
            case 15:  return "MX";
            case 16:  return "TXT";
            case 28:  return "AAAA";
            case 33:  return "SRV";
            case 255: return "ANY";
            default:  return "TYPE" + qtype;
        }
    }
}
