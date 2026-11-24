@IsTest
private class LlmInsightServiceTest {

    @TestSetup
    static void setup() {
        insert new AI_Service_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Base_Url__c = 'https://ai-insights.example.run.app',
            Service_Account_Email__c = 'sa@example.iam.gserviceaccount.com',
            Certificate_Name__c = 'gcp_sa_cert',
            Redact_PII__c = true
        );
        insert new Case(Subject = 'Billing issue', Description = 'Charged twice', Status = 'New');
        GcpAuthService.mockSignature = 'sig';
    }

    @IsTest
    static void returnsSummaryBullets() {
        GcpAuthService.mockSignature = 'sig';
        Case c = [SELECT Id FROM Case LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new AiServiceMock());

        Test.startTest();
        List<String> bullets = LlmInsightService.getCaseSummary(c.Id);
        Test.stopTest();

        Assert.areEqual(2, bullets.size(), 'Expected two summary bullets');
    }

    @IsTest
    static void surfacesFriendlyErrorOnServiceFailure() {
        GcpAuthService.mockSignature = 'sig';
        Case c = [SELECT Id FROM Case LIMIT 1];
        AiServiceMock mock = new AiServiceMock();
        mock.statusCode = 503;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            LlmInsightService.getCaseSummary(c.Id);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }
}
