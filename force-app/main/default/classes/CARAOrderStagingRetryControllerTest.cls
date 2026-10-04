@IsTest
private class CARAOrderStagingRetryControllerTest {
    private static final String PRODUCT_CODE = 'cara-retry-test-product-1';

    @TestSetup
    static void createCatalogData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        insert new Product2(
            Name = 'CARA Retry Test Product',
            ProductCode = PRODUCT_CODE,
            IsActive = true
        );
    }

    @IsTest
    static void retrySyncSucceedsForAFailedStagingRecord() {
        Id stagingId = stageBadPayload('00000601');
        CARAOrderSyncService.syncFromStaging(stagingId);
        fixPayload(stagingId, '00000601');

        Test.startTest();
        CARAOrderStagingRetryController.RetryResult result = CARAOrderStagingRetryController.retrySync(stagingId);
        Test.stopTest();

        Assert.isTrue(result.success, result.message);
        Assert.isNotNull(result.orderId);
        Assert.areEqual('Synced', [SELECT Sync_Status__c FROM SFCC_Order_Staging__c WHERE Id = :stagingId].Sync_Status__c);
    }

    @IsTest
    static void retrySyncOnAnAlreadySyncingRecordIsBlocked() {
        Id stagingId = CARAOrderSyncService.capturePayload('00000602', JSON.serialize(buildPayload('00000602')));
        update new SFCC_Order_Staging__c(Id = stagingId, Sync_Status__c = 'Syncing');

        Test.startTest();
        CARAOrderStagingRetryController.RetryResult result = CARAOrderStagingRetryController.retrySync(stagingId);
        Test.stopTest();

        Assert.isFalse(result.success);
        Assert.isTrue(result.message.contains('currently syncing'));
    }

    @IsTest
    static void retrySyncOnAnAlreadySyncedRecordIsANoOp() {
        Id stagingId = CARAOrderSyncService.capturePayload('00000603', JSON.serialize(buildPayload('00000603')));
        CARAOrderSyncService.SyncOutcome firstOutcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Assert.isTrue(firstOutcome.success, firstOutcome.message);

        Test.startTest();
        CARAOrderStagingRetryController.RetryResult result = CARAOrderStagingRetryController.retrySync(stagingId);
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.areEqual(firstOutcome.orderId, result.orderId);
        Assert.areEqual(1, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = '00000603']);
    }

    // =========================================================
    // Users without Edit access to SFCC_Order_Staging__c (i.e. anyone not
    // granted it via Operations Access / Finance Operations Access) must
    // not be able to run Retry Sync, mirroring how this org already gates
    // access by object/field permission rather than custom checks.
    // =========================================================
    @IsTest
    static void unauthorizedUserCannotRetrySync() {
        Id stagingId = CARAOrderSyncService.capturePayload('00000604', JSON.serialize(buildPayload('00000604')));
        CARAOrderSyncService.syncFromStaging(stagingId);

        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User unauthorizedUser = new User(
            Alias = 'ret604',
            Email = 'cara.retry.unauthorized@20three.digital.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'RetryUnauthorized',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'cara.retry.unauthorized@20three.digital.invalid'
        );
        insert unauthorizedUser;

        Test.startTest();
        System.runAs(unauthorizedUser) {
            try {
                CARAOrderStagingRetryController.retrySync(stagingId);
                Assert.fail('A user without Edit access to SFCC_Order_Staging__c must not be able to retry sync.');
            } catch (AuraHandledException accessError) {
                Assert.isTrue(true);
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void retrySyncOnANonExistentStagingRecordReturnsAHandledFailure() {
        Id stagingId = CARAOrderSyncService.capturePayload('00000605', JSON.serialize(buildPayload('00000605')));
        delete [SELECT Id FROM SFCC_Order_Staging__c WHERE Id = :stagingId];

        Test.startTest();
        CARAOrderStagingRetryController.RetryResult result = CARAOrderStagingRetryController.retrySync(stagingId);
        Test.stopTest();

        Assert.isFalse(result.success);
        Assert.isTrue(result.message.contains('not found'));
    }

    private static Id stageBadPayload(String orderNo) {
        Map<String, Object> badPayload = buildPayload(orderNo);
        badPayload.remove('status');
        return CARAOrderSyncService.capturePayload(orderNo, JSON.serialize(badPayload));
    }

    private static void fixPayload(Id stagingId, String orderNo) {
        update new SFCC_Order_Staging__c(Id = stagingId, Order_Payload__c = JSON.serialize(buildPayload(orderNo)));
    }

    private static Map<String, Object> buildPayload(String orderNo) {
        Map<String, Object> customerInfo = new Map<String, Object>{
            'customerId' => 'cust-' + orderNo,
            'customerName' => 'Retry Test Customer',
            'email' => 'retry-' + orderNo + '@20three.digital'
        };
        Map<String, Object> productItem = new Map<String, Object>{
            'basePrice' => 100,
            'itemId' => 'item-' + orderNo,
            'price' => 100,
            'productId' => PRODUCT_CODE,
            'productName' => 'CARA Retry Test Product',
            'quantity' => 1
        };
        return new Map<String, Object>{
            'channelType' => 'storefront',
            'creationDate' => '2026-08-20T12:41:03.553Z',
            'currency' => 'AED',
            'customerInfo' => customerInfo,
            'guest' => false,
            'orderNo' => orderNo,
            'orderTotal' => 100,
            'productItems' => new List<Object>{ productItem },
            'status' => 'created'
        };
    }
}