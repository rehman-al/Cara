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
    static void storefrontUrlDoesNotDuplicateLocaleReturnedBySfcc() {
        String origin = new Url(CARASplitPaymentSettings.getStorefrontBaseUri()).getProtocol() + '://'
            + new Url(CARASplitPaymentSettings.getStorefrontBaseUri()).getAuthority();

        System.assertEquals(
            origin + '/en-AE/pay/deposit?basketId=BASKET-1',
            CARASplitPaymentNotificationService.buildStorefrontUrl('/en-AE/pay/deposit?basketId=BASKET-1')
        );
        System.assertEquals(
            origin + '/en-AE/pay/balance?orderNo=ORD-1',
            CARASplitPaymentNotificationService.buildStorefrontUrl('en-AE/pay/balance?orderNo=ORD-1')
        );
    }


    @IsTest
    static void storefrontUrlKeepsBaseLocaleForPathWithoutLocale() {
        String baseUri = CARASplitPaymentSettings.getStorefrontBaseUri().removeEnd('/');

        System.assertEquals(
            baseUri + '/pay/deposit?basketId=BASKET-1',
            CARASplitPaymentNotificationService.buildStorefrontUrl('/pay/deposit?basketId=BASKET-1')
        );
        System.assertEquals(
            'https://example.com/pay?x=1',
            CARASplitPaymentNotificationService.buildStorefrontUrl('https://example.com/pay?x=1')
        );
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