public with sharing class CARAChatHistoryCacheService {

    private static final String PARTITION = 'local.CARAChat';
    private static final Integer MAX_CACHE_MESSAGES = 50;
    private static final Integer TTL_SECONDS = 300; // 5 minutes

    public static List<Chat_Message__c> getCachedMessages(
        Id caseId,
        Integer currentCount,
        Datetime latestModified
    ) {
        // If chat history exceeds 50 messages,
        // bypass cache and always fetch complete history from DB.
        if (currentCount > MAX_CACHE_MESSAGES) {
            clearCache(caseId);
            System.debug('CHAT CACHE BYPASS: More than 50 messages.');
            return null;
        }

        Cache.OrgPartition partition =
            Cache.Org.getPartition(PARTITION);

        String cacheKey = buildCacheKey(caseId);

        String cachedJson = (String) partition.get(cacheKey);

        if (String.isBlank(cachedJson)) {
            System.debug('CHAT CACHE MISS: No cached data.');
            return null;
        }

        CachePayload payload;

        try {
            payload = (CachePayload) JSON.deserialize(
                cachedJson,
                CachePayload.class
            );
        } catch (Exception error) {
            partition.remove(cacheKey);
            System.debug('CHAT CACHE MISS: Invalid cached payload.');
            return null;
        }

        Long currentModifiedMillis =
            getTimestampMillis(latestModified);

        if (
            payload == null ||
            payload.messageCount != currentCount ||
            payload.latestModifiedMillis != currentModifiedMillis
        ) {
            partition.remove(cacheKey);
            System.debug('CHAT CACHE STALE: Message data changed.');
            return null;
        }

        System.debug('CHAT CACHE HIT');

        return payload.messages;
    }


    public static void putMessages(
        Id caseId,
        Integer messageCount,
        Datetime latestModified,
        List<Chat_Message__c> messages
    ) {
        if (
            caseId == null ||
            messages == null ||
            messageCount > MAX_CACHE_MESSAGES
        ) {
            return;
        }

        CachePayload payload = new CachePayload();

        payload.messageCount = messageCount;
        payload.latestModifiedMillis =
            getTimestampMillis(latestModified);
        payload.messages = messages;

        Cache.OrgPartition partition =
            Cache.Org.getPartition(PARTITION);

        partition.put(
            buildCacheKey(caseId),
            JSON.serialize(payload),
            TTL_SECONDS
        );

        System.debug(
            'CHAT CACHE STORED: ' +
            messageCount +
            ' messages.'
        );
    }


    public static void clearCache(Id caseId) {
        if (caseId == null) {
            return;
        }

        Cache.OrgPartition partition =
            Cache.Org.getPartition(PARTITION);

        partition.remove(buildCacheKey(caseId));
    }


    private static String buildCacheKey(Id caseId) {
        return 'chatHistory' + String.valueOf(caseId);
    }


    private static Long getTimestampMillis(
        Datetime timestampValue
    ) {
        return timestampValue == null
            ? 0
            : timestampValue.getTime();
    }


    private class CachePayload {
        public Integer messageCount;
        public Long latestModifiedMillis;
        public List<Chat_Message__c> messages;
    }
}