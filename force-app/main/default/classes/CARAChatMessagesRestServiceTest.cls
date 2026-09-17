@IsTest
private class CARAChatMessagesRestServiceTest {
    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Storefront Customer');
        insert account;
        Case caseRecord = new Case(AccountId = account.Id, Subject = 'API chat list test');
        insert caseRecord;
        insert new List<Chat_Message__c>{
            new Chat_Message__c(
                Case__c = caseRecord.Id,
                Message_Body__c = 'Hello from storefront',
                Direction__c = 'Inbound',
                Sender_Type__c = 'Storefront Customer'
            ),
            new Chat_Message__c(
                Case__c = caseRecord.Id,
                Message_Body__c = 'Hi, how can I help?',
                Direction__c = 'Outbound',
                Sender_Type__c = 'Salesforce Agent'
            )
        };
    }

    @IsTest
    static void returnsMessagesForCase() {
        Case caseRecord = [SELECT Id FROM Case LIMIT 1];
        setChatMessagesRequest(caseRecord.Id);

        Test.startTest();
        CARAChatMessagesRestService.getMessagesByCase();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(true, responseBody.get('success'));
        Assert.areEqual(2, (Integer) responseBody.get('count'));
        Assert.areEqual(2, ((List<Object>) responseBody.get('messages')).size());
    }

    @IsTest
    static void returnsEmptyListWhenCaseHasNoMessages() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Case emptyCase = new Case(AccountId = account.Id, Subject = 'No messages yet');
        insert emptyCase;
        setChatMessagesRequest(emptyCase.Id);

        Test.startTest();
        CARAChatMessagesRestService.getMessagesByCase();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(0, (Integer) responseBody.get('count'));
    }

    @IsTest
    static void rejectsMissingOrInvalidCaseId() {
        setChatMessagesRequest(null);
        CARAChatMessagesRestService.getMessagesByCase();
        Assert.areEqual(400, RestContext.response.statusCode);

        setChatMessagesRequest('not-a-valid-id');
        CARAChatMessagesRestService.getMessagesByCase();
        Assert.areEqual(400, RestContext.response.statusCode);

        Account account = [SELECT Id FROM Account LIMIT 1];
        setChatMessagesRequest(account.Id);
        CARAChatMessagesRestService.getMessagesByCase();
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void returnsNotFoundForUnknownCase() {
        setChatMessagesRequest('500000000000000AAA');
        CARAChatMessagesRestService.getMessagesByCase();
        Assert.areEqual(404, RestContext.response.statusCode);
    }

    private static void setChatMessagesRequest(String caseIdValue) {
        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/chat/messages';
        requestRecord.httpMethod = 'GET';
        if (caseIdValue != null) {
            requestRecord.params.put('caseId', caseIdValue);
        }
        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
    }
}