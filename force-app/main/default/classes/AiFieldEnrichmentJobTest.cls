@IsTest
private class AiFieldEnrichmentJobTest {

    @TestSetup
    static void setup() {
        insert new AI_Service_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Base_Url__c = 'https://ai-insights.example.run.app',
            Service_Account_Email__c = 'sa@example.iam.gserviceaccount.com',
            Certificate_Name__c = 'gcp_sa_cert'
        );
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Acme ' + i, Risk_Notes__c = 'Customer moving to competitor on price'));
        }
        insert accounts;
    }

    @IsTest
    static void fillsOnlyBlankFieldsWithValidValues() {
        GcpAuthService.mockSignature = 'sig';
        Map<String, Set<String>> pairs = TaxonomyProvider.reasonToSubReasons();
        Assert.isFalse(pairs.isEmpty(), 'Org must define Risk_Reason__c values');
        String reason = new List<String>(pairs.keySet())[0];

        AiServiceMock mock = new AiServiceMock();
        for (Account acc : [SELECT Id FROM Account]) {
            mock.predictionsById.put(acc.Id, '"reason":"' + reason + '","subReason":"Not a real value","confidence":"HIGH"');
        }
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        AiFieldEnrichmentJob.start();
        Test.stopTest();

        for (Account acc : [SELECT Risk_Reason__c, Risk_Sub_Reason__c FROM Account]) {
            Assert.areEqual(reason, acc.Risk_Reason__c, 'Valid reason should be written');
            Assert.isNull(acc.Risk_Sub_Reason__c, 'Invalid (hallucinated) sub-reason must be rejected');
        }
    }

    @IsTest
    static void abortsWhenTaxonomySyncFails() {
        GcpAuthService.mockSignature = 'sig';
        AiServiceMock mock = new AiServiceMock();
        mock.statusCode = 500;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        AiFieldEnrichmentJob.start();
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'AiFieldEnrichmentJob'],
            'No job should be enqueued when the gate fails');
    }
}
