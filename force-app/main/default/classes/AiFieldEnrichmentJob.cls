/**
 * @description Scheduled, self-paced AI field enrichment for Accounts.
 *              1. Fail-closed gate: sync the live picklist taxonomy to the AI service.
 *              2. Process records in small chunks using a keyset cursor (Id > lastId).
 *              3. Write AI predictions ONLY to blank fields and only valid controlling/dependent pairs.
 *              4. Re-enqueue itself with a delay so the external AI service is never flooded.
 * @author      Naman G Shetty
 */
public with sharing class AiFieldEnrichmentJob implements Queueable, Database.AllowsCallouts {

    @TestVisible private static final Integer CHUNK_SIZE = 10;
    @TestVisible private static final Integer PAUSE_MINUTES = 2;
    @TestVisible private static Boolean chainInTests = false;

    private final Id cursor;
    private final Map<String, Set<String>> validPairs;

    public AiFieldEnrichmentJob() {
        this(null, null);
    }

    private AiFieldEnrichmentJob(Id cursor, Map<String, Set<String>> validPairs) {
        this.cursor = cursor;
        this.validPairs = validPairs;
    }

    /**
     * @description Entry point used by the scheduler. Aborts the whole run if the taxonomy sync fails.
     */
    public static void start() {
        Map<String, Set<String>> pairs = TaxonomyProvider.reasonToSubReasons();
        if (!AiServiceClient.syncTaxonomy(pairs)) {
            System.debug(LoggingLevel.WARN, 'Taxonomy sync failed - run aborted (fail closed).');
            return;
        }
        System.enqueueJob(new AiFieldEnrichmentJob(null, pairs));
    }

    public void execute(QueueableContext context) {
        List<Account> chunk = queryChunk();
        if (chunk.isEmpty()) {
            return;
        }

        Map<Id, AiServiceClient.Prediction> predictions = AiServiceClient.predict(chunk);
        List<Account> updates = new List<Account>();

        for (Account acc : chunk) {
            AiServiceClient.Prediction p = predictions.get(acc.Id);
            if (p == null || p.lowConfidence) {
                continue;
            }
            Boolean changed = false;

            if (String.isBlank(acc.Risk_Reason__c) && validPairs.containsKey(p.reason)) {
                acc.Risk_Reason__c = p.reason;
                changed = true;
            }
            String effectiveReason = acc.Risk_Reason__c;
            if (String.isBlank(acc.Risk_Sub_Reason__c)
                    && effectiveReason != null
                    && validPairs.get(effectiveReason)?.contains(p.subReason) == true) {
                acc.Risk_Sub_Reason__c = p.subReason;
                changed = true;
            }
            if (changed) {
                updates.add(acc);
            }
        }

        if (!updates.isEmpty()) {
            for (Database.SaveResult sr : Database.update(updates, false, AccessLevel.USER_MODE)) {
                if (!sr.isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'Enrichment save failed: ' + sr.getErrors()[0].getMessage());
                }
            }
        }

        Id nextCursor = chunk[chunk.size() - 1].Id;
        if (!Test.isRunningTest() || chainInTests) {
            System.enqueueJob(new AiFieldEnrichmentJob(nextCursor, validPairs), PAUSE_MINUTES);
        }
    }

    private List<Account> queryChunk() {
        String soql = 'SELECT Id, Name, Risk_Notes__c, Risk_Reason__c, Risk_Sub_Reason__c FROM Account'
            + ' WHERE (Risk_Reason__c = null OR Risk_Sub_Reason__c = null) AND Risk_Notes__c != null'
            + (cursor == null ? '' : ' AND Id > :lastId')
            + ' ORDER BY Id ASC LIMIT :chunkSize';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'lastId' => cursor, 'chunkSize' => CHUNK_SIZE },
            AccessLevel.USER_MODE
        );
    }
}
