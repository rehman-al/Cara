@IsTest
private class CARAChatRestServiceTest {
    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Storefront Customer');
        insert account;
        insert new Case(AccountId = account.Id, Subject = 'API chat test');
    }

    @IsTest
    static void createsInboundMessage() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        setInboundRequest(
            JSON.serialize(
                new Map<String, Object>{
                    'caseId' => testCase.Id,
                    'messageBody' => 'Hello from storefront'
                }
            )
        );

        Test.startTest();
        CARAChatInboundRestService.createInboundMessage();
        Test.stopTest();

        Assert.areEqual(201, RestContext.response.statusCode);
        Chat_Message__c savedMessage = [
            SELECT
                Case__c,
                Message_Body__c,
                Direction__c,
                Sender_Type__c
            FROM Chat_Message__c
            LIMIT 1
        ];
        Assert.areEqual(testCase.Id, savedMessage.Case__c);
        Assert.areEqual('Hello from storefront', savedMessage.Message_Body__c);
        Assert.areEqual('Inbound', savedMessage.Direction__c);
        Assert.areEqual('Storefront Customer', savedMessage.Sender_Type__c);
    }

    @IsTest
    static void rejectsInvalidInboundRequests() {
        setInboundRequest('{invalid');
        CARAChatInboundRestService.createInboundMessage();
        Assert.areEqual(400, RestContext.response.statusCode);

        setInboundRequest('{}');
        CARAChatInboundRestService.createInboundMessage();
        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual(0, [SELECT COUNT() FROM Chat_Message__c]);
    }

    @IsTest
    static void handlesMissingBodyAndUnknownCase() {
        RestRequest emptyRequest = new RestRequest();
        emptyRequest.requestUri = '/services/apexrest/cara/chat/inbound';
        emptyRequest.httpMethod = 'POST';
        RestContext.request = emptyRequest;
        RestContext.response = new RestResponse();

        CARAChatInboundRestService.createInboundMessage();
        Assert.areEqual(400, RestContext.response.statusCode);

        setInboundRequest(
            JSON.serialize(
                new Map<String, Object>{
                    'caseId' => '500000000000000AAA',
                    'messageBody' => 'Message for missing Case'
                }
            )
        );
        CARAChatInboundRestService.createInboundMessage();
        Assert.areEqual(404, RestContext.response.statusCode);
    }

    private static void setInboundRequest(String requestBody) {
        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/chat/inbound';
        requestRecord.httpMethod = 'POST';
        requestRecord.requestBody = Blob.valueOf(requestBody);
        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
    }

}
