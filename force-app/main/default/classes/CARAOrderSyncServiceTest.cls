@IsTest
private class CARAOrderSyncServiceTest {
    private static final String PRODUCT_CODE = 'cara-sync-test-product-1';

    @TestSetup
    static void createCatalogData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        insert new Product2(
            Name = 'CARA Sync Test Product',
            ProductCode = PRODUCT_CODE,
            IsActive = true
        );
    }

    @IsTest
    static void capturePayloadCreatesStagingRecordWithOriginalPayload() {
        String rawPayload = JSON.serialize(buildPayload('00000501', true, 'guest-capture@20three.digital', null));

        Test.startTest();
        Id stagingId = CARAOrderSyncService.capturePayload('00000501', rawPayload);
        Test.stopTest();

        SFCC_Order_Staging__c stagingRecord = [
            SELECT Sync_Status__c, Order_Payload__c, SFCC_Order_Number__c, Retry_Count__c
            FROM SFCC_Order_Staging__c
            WHERE Id = :stagingId
        ];
        Assert.areEqual('Received', stagingRecord.Sync_Status__c);
        Assert.areEqual('00000501', stagingRecord.SFCC_Order_Number__c);
        Assert.areEqual(0, stagingRecord.Retry_Count__c);
        Assert.isTrue(stagingRecord.Order_Payload__c.contains('guest-capture@20three.digital'));
    }

    @IsTest
    static void orderCreationFailureRetainsStagingDataAndRecordsError() {
        Map<String, Object> payload = buildPayload('00000502', false, 'logged-in-fail@20three.digital', 'cust-502');
        payload.remove('status');
        String rawPayload = JSON.serialize(payload);
        Id stagingId = CARAOrderSyncService.capturePayload('00000502', rawPayload);

        Test.startTest();
        CARAOrderSyncService.SyncOutcome outcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Test.stopTest();

        Assert.isFalse(outcome.success);
        SFCC_Order_Staging__c stagingRecord = [
            SELECT Sync_Status__c, Sync_Error__c, Order_Payload__c, Retry_Count__c, Last_Sync_Attempt__c
            FROM SFCC_Order_Staging__c
            WHERE Id = :stagingId
        ];
        Assert.areEqual('Failed', stagingRecord.Sync_Status__c);
        Assert.isTrue(stagingRecord.Sync_Error__c.contains('status'));
        Assert.isNotNull(stagingRecord.Last_Sync_Attempt__c);
        Assert.areEqual(0, stagingRecord.Retry_Count__c, 'The first attempt is not itself a retry.');
        Assert.isTrue(stagingRecord.Order_Payload__c.contains('logged-in-fail@20three.digital'));
        Assert.areEqual(0, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = '00000502']);
    }

    @IsTest
    static void retryIncrementsRetryCountAndSucceedsOnceDataIsFixed() {
        Map<String, Object> badPayload = buildPayload('00000503', false, 'retry-fix@20three.digital', 'cust-503');
        badPayload.remove('status');
        Id stagingId = CARAOrderSyncService.capturePayload('00000503', JSON.serialize(badPayload));
        CARAOrderSyncService.SyncOutcome firstOutcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Assert.isFalse(firstOutcome.success);

        // Simulate the underlying issue being fixed (e.g. an ops user or a
        // resent API payload corrects the staged data) before retrying.
        Map<String, Object> fixedPayload = buildPayload('00000503', false, 'retry-fix@20three.digital', 'cust-503');
        update new SFCC_Order_Staging__c(Id = stagingId, Order_Payload__c = JSON.serialize(fixedPayload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome retryOutcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Test.stopTest();

        Assert.isTrue(retryOutcome.success, retryOutcome.message);
        SFCC_Order_Staging__c stagingRecord = [
            SELECT Sync_Status__c, Retry_Count__c, Sync_Error__c, Salesforce_Order__c, Last_Successful_Sync__c
            FROM SFCC_Order_Staging__c
            WHERE Id = :stagingId
        ];
        Assert.areEqual('Synced', stagingRecord.Sync_Status__c);
        Assert.areEqual(1, stagingRecord.Retry_Count__c, 'Retry Sync must increment the retry count.');
        Assert.isNull(stagingRecord.Sync_Error__c);
        Assert.isNotNull(stagingRecord.Salesforce_Order__c);
        Assert.isNotNull(stagingRecord.Last_Successful_Sync__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = '00000503']);
    }

    @IsTest
    static void repeatedRetryFailureUpdatesErrorAndKeepsRetryAvailable() {
        Map<String, Object> badPayload = buildPayload('00000504', false, 'retry-still-bad@20three.digital', 'cust-504');
        badPayload.remove('status');
        Id stagingId = CARAOrderSyncService.capturePayload('00000504', JSON.serialize(badPayload));

        CARAOrderSyncService.syncFromStaging(stagingId);

        Test.startTest();
        CARAOrderSyncService.SyncOutcome secondOutcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Test.stopTest();

        Assert.isFalse(secondOutcome.success);
        SFCC_Order_Staging__c stagingRecord = [
            SELECT Sync_Status__c, Retry_Count__c, Sync_Error__c
            FROM SFCC_Order_Staging__c
            WHERE Id = :stagingId
        ];
        Assert.areEqual('Failed', stagingRecord.Sync_Status__c, 'Retry must remain available after repeated failures.');
        Assert.areEqual(1, stagingRecord.Retry_Count__c);
        Assert.isTrue(stagingRecord.Sync_Error__c.contains('status'));
    }

    @IsTest
    static void retryingAlreadySyncedOrderDoesNotCreateDuplicate() {
        Map<String, Object> payload = buildPayload('00000505', false, 'already-synced@20three.digital', 'cust-505');
        Id stagingId = CARAOrderSyncService.capturePayload('00000505', JSON.serialize(payload));
        CARAOrderSyncService.SyncOutcome firstOutcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Assert.isTrue(firstOutcome.success, firstOutcome.message);

        Test.startTest();
        CARAOrderSyncService.SyncOutcome retryOutcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Test.stopTest();

        Assert.isTrue(retryOutcome.success);
        Assert.areEqual(firstOutcome.orderId, retryOutcome.orderId);
        Assert.areEqual(1, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = '00000505']);

        SFCC_Order_Staging__c stagingRecord = [SELECT Retry_Count__c FROM SFCC_Order_Staging__c WHERE Id = :stagingId];
        Assert.areEqual(0, stagingRecord.Retry_Count__c, 'Retrying an already-Synced order is a no-op, not a counted retry.');
    }

    @IsTest
    static void duplicateStagingRowForSameOrderNumberIsRejectedByTheExternalIdConstraint() {
        CARAOrderSyncService.capturePayload('00000506', JSON.serialize(buildPayload('00000506', false, 'dup-key@20three.digital', 'cust-506')));

        try {
            insert new SFCC_Order_Staging__c(SFCC_Order_Number__c = '00000506', Order_Payload__c = '{}');
            Assert.fail('A second staging row with the same SFCC Order Number must be rejected.');
        } catch (DmlException dmlError) {
            Assert.isTrue(dmlError.getMessage().contains('DUPLICATE'));
        }
    }

    // =========================================================
    // Guest checkout: capture -> fail -> retry -> succeed, using the same
    // centralized service and the same Sync Status/retry mechanics as a
    // logged-in order. No separate guest sync path exists.
    // =========================================================
    @IsTest
    static void guestOrderFailureIsRetryableAndSucceedsOnceFixed() {
        Map<String, Object> badGuestPayload = buildPayload('00000507', true, 'guest-retry@20three.digital', null);
        badGuestPayload.remove('status');
        Id stagingId = CARAOrderSyncService.capturePayload('00000507', JSON.serialize(badGuestPayload));

        CARAOrderSyncService.SyncOutcome firstOutcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Assert.isFalse(firstOutcome.success);
        Assert.areEqual(0, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = '00000507']);

        Map<String, Object> fixedGuestPayload = buildPayload('00000507', true, 'guest-retry@20three.digital', null);
        update new SFCC_Order_Staging__c(Id = stagingId, Order_Payload__c = JSON.serialize(fixedGuestPayload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome retryOutcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Test.stopTest();

        Assert.isTrue(retryOutcome.success, retryOutcome.message);
        SFCC_Order_Staging__c stagingRecord = [
            SELECT Sync_Status__c, Retry_Count__c, Salesforce_Order__c
            FROM SFCC_Order_Staging__c
            WHERE Id = :stagingId
        ];
        Assert.areEqual('Synced', stagingRecord.Sync_Status__c);
        Assert.areEqual(1, stagingRecord.Retry_Count__c);

        Order guestOrder = [SELECT Id, AccountId FROM Order WHERE OrderReferenceNumber = '00000507' LIMIT 1];
        Assert.areEqual(1, [SELECT COUNT() FROM OrderItem WHERE OrderId = :guestOrder.Id]);
        Assert.isTrue([SELECT Is_Guest__c FROM Account WHERE Id = :guestOrder.AccountId].Is_Guest__c);
    }

    @IsTest
    static void repeatedGuestRetryDoesNotCreateDuplicateOrders() {
        Map<String, Object> payload = buildPayload('00000508', true, 'guest-no-dup@20three.digital', null);
        Id stagingId = CARAOrderSyncService.capturePayload('00000508', JSON.serialize(payload));
        CARAOrderSyncService.syncFromStaging(stagingId);

        Test.startTest();
        CARAOrderSyncService.syncFromStaging(stagingId);
        CARAOrderSyncService.syncFromStaging(stagingId);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = '00000508']);
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Id IN (SELECT AccountId FROM Order WHERE OrderReferenceNumber = '00000508')]
        );
    }

    private static Map<String, Object> buildPayload(String orderNo, Boolean guest, String email, String customerId) {
        Map<String, Object> billingAddress = new Map<String, Object>{
            'address1' => '1 Test Street',
            'city' => 'Dubai',
            'countryCode' => 'AE',
            'firstName' => 'Test',
            'fullName' => 'Test Customer',
            'id' => 'addr-' + orderNo,
            'lastName' => 'Customer',
            'phone' => '+1 5555555555',
            'postalCode' => '00000',
            'stateCode' => 'DU'
        };

        Map<String, Object> productItem = new Map<String, Object>{
            'basePrice' => 100,
            'bonusProductLineItem' => false,
            'gift' => false,
            'itemId' => 'item-' + orderNo,
            'itemText' => 'CARA Sync Test Product',
            'price' => 100,
            'productId' => PRODUCT_CODE,
            'productName' => 'CARA Sync Test Product',
            'quantity' => 1,
            'shipmentId' => 'ship-' + orderNo,
            'tax' => 0,
            'taxBasis' => 100,
            'taxClassId' => 'default',
            'taxRate' => 0
        };

        Map<String, Object> customerInfo = new Map<String, Object>{
            'customerId' => customerId,
            'customerName' => 'Test Customer',
            'email' => email
        };

        return new Map<String, Object>{
            'billingAddress' => billingAddress,
            'channelType' => 'storefront',
            'creationDate' => '2026-08-20T12:41:03.553Z',
            'currency' => 'AED',
            'customerInfo' => customerInfo,
            'customerName' => 'Test Customer',
            'guest' => guest,
            'orderNo' => orderNo,
            'orderTotal' => 100,
            'productItems' => new List<Object>{ productItem },
            'productSubTotal' => 100,
            'productTotal' => 100,
            'status' => 'created'
        };
    }
}