/**
 * @description HTTP client for the Cloud Run AI service used by the enrichment job.
 * @author      Naman G Shetty
 */
public with sharing class AiServiceClient {

    private static final Integer TIMEOUT_MS = 120000;

    /** @description One AI prediction for one record. */
    public class Prediction {
        public String reason;
        public String subReason;
        public Boolean lowConfidence = false;
    }

    /**
     * @description Pushes the current picklist taxonomy to the AI service. The model may only answer
     *              with values from this list, which removes a whole class of hallucinations.
     * @return true when the service acknowledged the taxonomy.
     */
    public static Boolean syncTaxonomy(Map<String, Set<String>> reasonToSubReasons) {
        try {
            HttpResponse res = post('/api/v1/taxonomy', new Map<String, Object>{ 'reasons' => reasonToSubReasons });
            return res.getStatusCode() == 200;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Taxonomy sync error: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Requests predictions for a chunk of records in a single callout.
     */
    public static Map<Id, Prediction> predict(List<Account> records) {
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        for (Account acc : records) {
            items.add(new Map<String, Object>{ 'id' => acc.Id, 'notes' => acc.Risk_Notes__c });
        }

        Map<Id, Prediction> result = new Map<Id, Prediction>();
        try {
            HttpResponse res = post('/api/v1/enrich', new Map<String, Object>{ 'records' => items });
            if (res.getStatusCode() != 200) {
                return result;
            }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            for (Object raw : (List<Object>) body.get('predictions')) {
                Map<String, Object> row = (Map<String, Object>) raw;
                Prediction p = new Prediction();
                p.reason = (String) row.get('reason');
                p.subReason = (String) row.get('subReason');
                p.lowConfidence = 'LOW'.equals(row.get('confidence'));
                result.put((Id) row.get('id'), p);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Prediction callout failed: ' + e.getMessage());
        }
        return result;
    }

    private static HttpResponse post(String path, Object payload) {
        AI_Service_Settings__c settings = AI_Service_Settings__c.getOrgDefaults();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(settings.Base_Url__c + path);
        req.setMethod('POST');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + GcpAuthService.getIdentityToken(settings.Base_Url__c));
        req.setBody(JSON.serialize(payload));
        return new Http().send(req);
    }
}
