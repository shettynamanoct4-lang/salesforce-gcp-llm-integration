/**
 * @description LWC-facing service that asks the Cloud Run AI service for a grounded case summary.
 *              Apex stays a thin, secure client: it gathers context the user can see, authenticates,
 *              and returns structured JSON. Prompting, PII masking and model calls live in Cloud Run.
 * @author      Naman G Shetty
 */
public with sharing class LlmInsightService {

    private static final Integer MAX_EMAILS = 50;
    private static final Integer CALLOUT_TIMEOUT_MS = 60000;

    /**
     * @description Returns AI summary bullets for a Case.
     * @param  caseId Case record Id.
     * @return List of summary bullet strings.
     */
    @AuraEnabled
    public static List<String> getCaseSummary(Id caseId) {
        try {
            AI_Service_Settings__c settings = AI_Service_Settings__c.getOrgDefaults();
            String endpoint = settings.Base_Url__c + '/api/v1/summarize';

            Map<String, Object> payload = new Map<String, Object>{
                'recordId' => caseId,
                'redact' => settings.Redact_PII__c,
                'context' => collectContext(caseId)
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setTimeout(CALLOUT_TIMEOUT_MS);
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + GcpAuthService.getIdentityToken(settings.Base_Url__c));
            req.setBody(JSON.serialize(payload));

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                throw new AuraHandledException('AI service unavailable (HTTP ' + res.getStatusCode() + ').');
            }

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<String> bullets = new List<String>();
            for (Object item : (List<Object>) body.get('summary')) {
                bullets.add(String.valueOf(item));
            }
            return bullets;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Case summary failed: ' + e.getMessage());
            throw new AuraHandledException('Unable to generate summary right now.');
        }
    }

    /**
     * @description Collects only records the running user can access (USER_MODE enforces CRUD/FLS/sharing).
     */
    private static Map<String, Object> collectContext(Id caseId) {
        Case c = [
            SELECT Subject, Description, Status, Priority
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        List<String> emails = new List<String>();
        for (EmailMessage em : [
            SELECT TextBody
            FROM EmailMessage
            WHERE ParentId = :caseId
            WITH USER_MODE
            ORDER BY MessageDate DESC
            LIMIT :MAX_EMAILS
        ]) {
            emails.add(em.TextBody);
        }
        return new Map<String, Object>{
            'subject' => c.Subject,
            'description' => c.Description,
            'status' => c.Status,
            'priority' => c.Priority,
            'emails' => emails
        };
    }
}
