@IsTest
private class CARACaseRestServiceTest {
    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Storefront Customer');
        insert account;
        insert new List<Case>{
            new Case(AccountId = account.Id, Subject = 'Where is my order?', Status = 'New', Origin = 'Web'),
            new Case(AccountId = account.Id, Subject = 'Refund request', Status = 'Closed', Origin = 'Email')
        };
    }

    @IsTest
    static void returnsCasesForAccount() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        setCaseRequest(account.Id);

        Test.startTest();
        CARACaseRestService.getCasesByAccount();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(true, responseBody.get('success'));
        Assert.areEqual(2, (Integer) responseBody.get('count'));
        Assert.areEqual(2, ((List<Object>) responseBody.get('cases')).size());
    }

    @IsTest
    static void returnsEmptyListWhenAccountHasNoCases() {
        Account account = new Account(Name = 'No Cases Customer');
        insert account;
        setCaseRequest(account.Id);

        Test.startTest();
        CARACaseRestService.getCasesByAccount();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(0, (Integer) responseBody.get('count'));
    }

    @IsTest
    static void rejectsMissingOrInvalidAccountId() {
        setCaseRequest(null);
        CARACaseRestService.getCasesByAccount();
        Assert.areEqual(400, RestContext.response.statusCode);

        setCaseRequest('not-a-valid-id');
        CARACaseRestService.getCasesByAccount();
        Assert.areEqual(400, RestContext.response.statusCode);

        Case caseRecord = [SELECT Id FROM Case LIMIT 1];
        setCaseRequest(caseRecord.Id);
        CARACaseRestService.getCasesByAccount();
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void returnsNotFoundForUnknownAccount() {
        setCaseRequest('001000000000000AAA');
        CARACaseRestService.getCasesByAccount();
        Assert.areEqual(404, RestContext.response.statusCode);
    }

    private static void setCaseRequest(String accountIdValue) {
        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/cases';
        requestRecord.httpMethod = 'GET';
        if (accountIdValue != null) {
            requestRecord.params.put('accountId', accountIdValue);
        }
        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
    }
}
