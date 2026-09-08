@IsTest
private class CaseChatControllerTest {
    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Ada Customer');
        insert account;
        insert new Case(AccountId = account.Id, Subject = 'Chat test');
    }

    @IsTest
    static void getsMessagesInChronologicalOrder() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        insert new List<Chat_Message__c>{
            new Chat_Message__c(
                Case__c = testCase.Id,
                Message_Body__c = 'First'
            ),
            new Chat_Message__c(
                Case__c = testCase.Id,
                Message_Body__c = 'Second'
            )
        };

        Test.startTest();
        CaseChatController.ChatData result = CaseChatController.getChatData(
            testCase.Id
        );
        Test.stopTest();

        System.assertEquals('Ada Customer', result.accountName);
        System.assertEquals(2, result.messages.size());
        System.assertEquals('First', result.messages[0].body);
        System.assertEquals('Second', result.messages[1].body);
        System.assertEquals('Outbound', result.messages[0].direction);
    }

    @IsTest
    static void sendsTrimmedMessage() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        CaseChatController.ChatMessage result = CaseChatController.sendMessage(
            testCase.Id,
            '  Hello from the Case  '
        );
        Test.stopTest();

        Chat_Message__c savedMessage = [
            SELECT Case__c, Message_Body__c
            FROM Chat_Message__c
            WHERE Id = :result.id
        ];
        System.assertEquals(testCase.Id, savedMessage.Case__c);
        System.assertEquals('Hello from the Case', savedMessage.Message_Body__c);
        System.assertNotEquals(null, result.createdDate);
        System.assertEquals('Outbound', result.direction);
        System.assertEquals(UserInfo.getName(), result.senderName);
    }

    @IsTest
    static void rejectsBlankMessage() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Boolean exceptionThrown = false;

        try {
            CaseChatController.sendMessage(testCase.Id, '   ');
        } catch (AuraHandledException error) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown, 'Expected blank messages to be rejected.');
        System.assertEquals(0, [SELECT COUNT() FROM Chat_Message__c]);
    }

    @IsTest
    static void rejectsMissingCaseAndLongMessage() {
        Boolean missingCaseRejected = false;
        Boolean longMessageRejected = false;

        try {
            CaseChatController.sendMessage(null, 'Hello');
        } catch (AuraHandledException error) {
            missingCaseRejected = true;
        }

        Case testCase = [SELECT Id FROM Case LIMIT 1];
        try {
            CaseChatController.sendMessage(testCase.Id, 'x'.repeat(4001));
        } catch (AuraHandledException error) {
            longMessageRejected = true;
        }

        System.assert(missingCaseRejected, 'A Case should be required.');
        System.assert(longMessageRejected, 'Long messages should be rejected.');
    }

    @IsTest
    static void returnsEmptyDataWithoutCaseId() {
        CaseChatController.ChatData result = CaseChatController.getChatData(null);

        System.assertEquals(null, result.accountName);
        System.assertEquals(0, result.messages.size());
    }

    @IsTest
    static void supportsCaseWithoutAccount() {
        Case caseWithoutAccount = new Case(Subject = 'No account');
        insert caseWithoutAccount;

        CaseChatController.ChatData result = CaseChatController.getChatData(
            caseWithoutAccount.Id
        );

        System.assertEquals('Case Customer', result.accountName);
        System.assertEquals(0, result.messages.size());
    }

    @IsTest
    static void identifiesInboundCustomerMessage() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        insert new Chat_Message__c(
            Case__c = testCase.Id,
            Message_Body__c = 'Message from storefront',
            Direction__c = 'Inbound',
            Sender_Type__c = 'Storefront Customer'
        );

        CaseChatController.ChatData result = CaseChatController.getChatData(
            testCase.Id
        );

        System.assertEquals(1, result.messages.size());
        System.assertEquals('Inbound', result.messages[0].direction);
        System.assertEquals('Ada Customer', result.messages[0].senderName);
    }
}
