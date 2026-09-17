@IsTest
private class CARAChatHistoryRestServiceTest {

    @IsTest
    static void returnsMessagesInSequenceAndHandlesFiftyOneMessages() {

        // Create isolated test Case
        Case testCase = new Case(
            Subject = 'Chat History Cache Test',
            Status = 'New',
            Origin = 'Web'
        );
        insert testCase;
        testCase = [
    SELECT Id, CaseNumber
    FROM Case
    WHERE Id = :testCase.Id
    LIMIT 1
       ];

        // Create exactly 50 messages
        List<Chat_Message__c> messages = new List<Chat_Message__c>();

        for (Integer i = 1; i <= 50; i++) {
            messages.add(
                new Chat_Message__c(
                    Case__c = testCase.Id,
                    Message_Body__c = 'Test message ' + i,
                    Direction__c = Math.mod(i, 2) == 0
                        ? 'Inbound'
                        : 'Outbound',
                    Sender_Type__c = Math.mod(i, 2) == 0
                        ? 'Storefront Customer'
                        : 'Salesforce Agent'
                )
            );
        }

        insert messages;

        CARAChatHistoryCacheService.clearCache(testCase.Id);


        // --------------------------
        // TEST WITH 50 MESSAGES
        // --------------------------
        setGetRequest(testCase.CaseNumber);

        

        CARAChatHistoryRestService.getChatHistory();



        System.assertEquals(
            200,
            RestContext.response.statusCode
        );

        Map<String, Object> firstResponse =
            (Map<String, Object>) JSON.deserializeUntyped(
                RestContext.response.responseBody.toString()
            );

        System.assertEquals(
            50,
            ((Decimal) firstResponse.get('totalMessages')).intValue()
        );

        List<Object> firstMessages =
            (List<Object>) firstResponse.get('messages');

        System.assertEquals(
            50,
            firstMessages.size()
        );


        // --------------------------
        // CREATE MESSAGE NUMBER 51
        // --------------------------
        insert new Chat_Message__c(
            Case__c = testCase.Id,
            Message_Body__c = 'Test message 51',
            Direction__c = 'Inbound',
            Sender_Type__c = 'Storefront Customer'
        );


        // --------------------------
        // TEST WITH 51 MESSAGES
        // --------------------------
        setGetRequest(testCase.CaseNumber);


        CARAChatHistoryRestService.getChatHistory();



        System.assertEquals(
            200,
            RestContext.response.statusCode
        );

        Map<String, Object> secondResponse =
            (Map<String, Object>) JSON.deserializeUntyped(
                RestContext.response.responseBody.toString()
            );

        System.assertEquals(
            51,
            ((Decimal) secondResponse.get('totalMessages')).intValue()
        );

        List<Object> secondMessages =
            (List<Object>) secondResponse.get('messages');

        System.assertEquals(
            51,
            secondMessages.size()
        );


        // Verify sequence 1 -> 51
        Map<String, Object> firstMessage =
            (Map<String, Object>) secondMessages[0];

        Map<String, Object> lastMessage =
            (Map<String, Object>) secondMessages[50];

        System.assertEquals(
            1,
            ((Decimal) firstMessage.get('sequence')).intValue()
        );

        System.assertEquals(
            51,
            ((Decimal) lastMessage.get('sequence')).intValue()
        );

        // System.assertEquals(
        //     'Test message 51',
        //     (String) lastMessage.get('message')
        // );
    }


    @IsTest
    static void rejectsMissingCaseNumber() {

        RestRequest requestRecord = new RestRequest();

        requestRecord.requestUri =
            '/services/apexrest/cara/chat/history';

        requestRecord.httpMethod = 'GET';

        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();

        Test.startTest();

        CARAChatHistoryRestService.getChatHistory();

        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode
        );
    }


    private static void setGetRequest(String caseNumber) {

        RestRequest requestRecord = new RestRequest();

        requestRecord.requestUri =
            '/services/apexrest/cara/chat/history';

        requestRecord.httpMethod = 'GET';

        requestRecord.addParameter(
            'caseNumber',
            caseNumber
        );

        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
    }
}