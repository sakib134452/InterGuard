package com.interguard.app;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedList;
import java.util.List;
import java.util.Queue;

/**
 * Thread-safe DNS query logger.
 * Stores up to MAX_LOGS recent queries in memory.
 * Singleton accessed by VPN service and method channel.
 */
public class QueryLogger {

    private static final int MAX_LOGS = 500;

    private static volatile QueryLogger INSTANCE;

    public static QueryLogger getInstance() {
        if (INSTANCE == null) {
            synchronized (QueryLogger.class) {
                if (INSTANCE == null) {
                    INSTANCE = new QueryLogger();
                }
            }
        }
        return INSTANCE;
    }

    public static class Entry {
        public final String domain;
        public final long timestamp;
        public final boolean blocked;
        public final String type;

        Entry(String domain, long timestamp, boolean blocked, String type) {
            this.domain = domain;
            this.timestamp = timestamp;
            this.blocked = blocked;
            this.type = type;
        }
    }

    private final LinkedList<Entry> entries = new LinkedList<>();
    private long totalQueries = 0;
    private long blockedQueries = 0;

    private QueryLogger() {}

    public synchronized void log(String domain, long timestamp,
                                  boolean blocked, String type) {
        totalQueries++;
        if (blocked) blockedQueries++;

        entries.addLast(new Entry(domain, timestamp, blocked, type));
        if (entries.size() > MAX_LOGS) {
            entries.removeFirst();
        }
    }

    public synchronized long getTotalQueries() {
        return totalQueries;
    }

    public synchronized long getBlockedQueries() {
        return blockedQueries;
    }

    public synchronized List<Entry> getEntries() {
        return new ArrayList<>(entries);
    }

    public synchronized void clear() {
        entries.clear();
        // Note: we keep totalQueries/blockedQueries as lifetime counters
    }

    public synchronized void resetCounters() {
        totalQueries = 0;
        blockedQueries = 0;
        entries.clear();
    }
}
