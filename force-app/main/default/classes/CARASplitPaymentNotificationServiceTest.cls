@IsTest
private class CARASplitPaymentNotificationServiceTest {

    private static Contact buildContact(String email) {
        Account acc = new Account(Name = 'Notification Test Customer');
        insert acc;

        Contact contactRecord = new Contact(
            AccountId = acc.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = email
        );
        insert contactRecord;
        return contactRecord;
    }


    @IsTest
    static void sendDepositLinkSendsEmailWhenContactHasAddress() {
        Contact contactRecord = buildContact('shopper@example.com');

        Test.startTest();
        CARASplitPaymentNotificationService.NotificationOutcome outcome =
            CARASplitPaymentNotificationService.sendDepositLink(
                contactRecord, 'Custom Ring Request', 250, '/pay/deposit?basketId=BASKET-1'
            );
        Test.stopTest();

        System.assert(outcome.sent);
        System.assertEquals('Sent to shopper@example.com', outcome.detail);
    }


    @IsTest
    static void sendDepositLinkSkipsWhenContactHasNoEmail() {
        Contact contactRecord = buildContact(null);

        Test.startTest();
        CARASplitPaymentNotificationService.NotificationOutcome outcome =
            CARASplitPaymentNotificationService.sendDepositLink(
                contactRecord, 'Custom Ring Request', 250, '/pay/deposit?basketId=BASKET-1'
            );
        Test.stopTest();

        System.assert(!outcome.sent);
        System.assertEquals('Skipped - No Email', outcome.detail);
        System.assertEquals(0, Limits.getEmailInvocations());
    }


    @IsTest
    static void sendDepositLinkSkipsWhenContactIsNull() {
        Test.startTest();
        CARASplitPaymentNotificationService.NotificationOutcome outcome =
            CARASplitPaymentNotificationService.sendDepositLink(
                null, 'Custom Ring Request', 250, '/pay/deposit?basketId=BASKET-1'
            );
        Test.stopTest();

        System.assert(!outcome.sent);
        System.assertEquals('Skipped - No Email', outcome.detail);
    }


    @IsTest
    static void sendBalanceLinkSendsEmailByRawAddress() {
        Test.startTest();
        CARASplitPaymentNotificationService.NotificationOutcome outcome =
            CARASplitPaymentNotificationService.sendBalanceLink(
                'shopper@example.com', 'Jane', 'ORD-1', 500, '/pay/balance?orderNo=ORD-1'
            );
        Test.stopTest();

        System.assert(outcome.sent);
        System.assertEquals('Sent to shopper@example.com', outcome.detail);
    }


    @IsTest
    static void sendBalanceLinkSkipsWhenEmailIsBlank() {
        Test.startTest();
        CARASplitPaymentNotificationService.NotificationOutcome outcome =
            CARASplitPaymentNotificationService.sendBalanceLink(
                null, 'Jane', 'ORD-1', 500, '/pay/balance?orderNo=ORD-1'
            );
        Test.stopTest();

        System.assert(!outcome.sent);
        System.assertEquals('Skipped - No Email', outcome.detail);
        System.assertEquals(0, Limits.getEmailInvocations());
    }
}