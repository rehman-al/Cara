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

    // =========================================================
    // Registered customer whose email already resolves to an Account tied
    // to a different SFCC customerId: rather than blocking the order (or
    // silently overwriting the existing identity), this creates a separate
    // Account+Contact for the order and links it back via Duplicate_Of__c
    // so Ops can find and reconcile the two.
    // =========================================================
    @IsTest
    static void customerIdMismatchCreatesLinkedDuplicateAccountInsteadOfBlocking() {
        Map<String, Object> originalPayload = buildPayload('00000509', false, 'duplicate-identity@20three.digital', 'cust-509-original');
        Id originalStagingId = CARAOrderSyncService.capturePayload('00000509', JSON.serialize(originalPayload));
        CARAOrderSyncService.SyncOutcome originalOutcome = CARAOrderSyncService.syncFromStaging(originalStagingId);
        Assert.isTrue(originalOutcome.success, originalOutcome.message);
        Id originalAccountId = [SELECT AccountId FROM Order WHERE Id = :originalOutcome.orderId].AccountId;

        Map<String, Object> conflictingPayload = buildPayload('00000510', false, 'duplicate-identity@20three.digital', 'cust-509-conflict');
        Id conflictingStagingId = CARAOrderSyncService.capturePayload('00000510', JSON.serialize(conflictingPayload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome conflictingOutcome = CARAOrderSyncService.syncFromStaging(conflictingStagingId);
        Test.stopTest();

        Assert.isTrue(conflictingOutcome.success, conflictingOutcome.message);
        Id duplicateAccountId = [SELECT AccountId FROM Order WHERE Id = :conflictingOutcome.orderId].AccountId;
        Assert.areNotEqual(originalAccountId, duplicateAccountId, 'A customerId conflict must create a separate Account, not block the order or merge into the original.');

        Account duplicateAccount = [SELECT Duplicate_Of__c FROM Account WHERE Id = :duplicateAccountId];
        Assert.areEqual(originalAccountId, duplicateAccount.Duplicate_Of__c, 'The duplicate Account must be linked back to the original for tracking.');
    }

    // =========================================================
    // Guest and Registered identities are modeled as two separate
    // Accounts. A Guest Account is always reused across repeat guest
    // orders (keyed on email, since SFCC's guest customerId changes every
    // checkout session) and is never merged into, or allowed to overwrite,
    // the Registered Account for the same person.
    // =========================================================
    @IsTest
    static void guestOrderWithExistingRegisteredParentCreatesLinkedGuestAccount() {
        Map<String, Object> registeredPayload = buildPayload('00000511', false, 'guest-with-parent@20three.digital', 'cust-511-registered');
        Id registeredStagingId = CARAOrderSyncService.capturePayload('00000511', JSON.serialize(registeredPayload));
        CARAOrderSyncService.SyncOutcome registeredOutcome = CARAOrderSyncService.syncFromStaging(registeredStagingId);
        Assert.isTrue(registeredOutcome.success, registeredOutcome.message);
        Id registeredAccountId = [SELECT AccountId FROM Order WHERE Id = :registeredOutcome.orderId].AccountId;

        Map<String, Object> guestPayload = buildPayload('00000512', true, 'guest-with-parent@20three.digital', 'cust-512-guest-session');
        Id guestStagingId = CARAOrderSyncService.capturePayload('00000512', JSON.serialize(guestPayload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome guestOutcome = CARAOrderSyncService.syncFromStaging(guestStagingId);
        Test.stopTest();

        Assert.isTrue(guestOutcome.success, guestOutcome.message);
        Id guestAccountId = [SELECT AccountId FROM Order WHERE Id = :guestOutcome.orderId].AccountId;
        Assert.areNotEqual(registeredAccountId, guestAccountId, 'The guest order must use a separate Guest Account, not the Registered Account.');

        Account guestAccount = [SELECT Is_Guest__c, ParentId FROM Account WHERE Id = :guestAccountId];
        Assert.isTrue(guestAccount.Is_Guest__c);
        Assert.areEqual(registeredAccountId, guestAccount.ParentId, 'The Guest Account must be linked under the Registered Account.');

        Account registeredAccount = [SELECT Is_Guest__c, External_ID__c FROM Account WHERE Id = :registeredAccountId];
        Assert.isFalse(registeredAccount.Is_Guest__c);
        Assert.areEqual('cust-511-registered', registeredAccount.External_ID__c, 'A guest order must never overwrite the Registered Account\'s External ID.');
    }

    @IsTest
    static void secondGuestOrderFromSameEmailReusesSameGuestAccountNotANewOne() {
        Map<String, Object> firstGuestPayload = buildPayload('00000513', true, 'repeat-guest@20three.digital', 'cust-513-session-a');
        Id firstStagingId = CARAOrderSyncService.capturePayload('00000513', JSON.serialize(firstGuestPayload));
        CARAOrderSyncService.SyncOutcome firstOutcome = CARAOrderSyncService.syncFromStaging(firstStagingId);
        Assert.isTrue(firstOutcome.success, firstOutcome.message);
        Id firstGuestAccountId = [SELECT AccountId FROM Order WHERE Id = :firstOutcome.orderId].AccountId;

        // A second guest order from the same person carries a brand new,
        // unrelated SFCC session customerId - this must not be treated as a
        // different customer.
        Map<String, Object> secondGuestPayload = buildPayload('00000514', true, 'repeat-guest@20three.digital', 'cust-514-session-b');
        Id secondStagingId = CARAOrderSyncService.capturePayload('00000514', JSON.serialize(secondGuestPayload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome secondOutcome = CARAOrderSyncService.syncFromStaging(secondStagingId);
        Test.stopTest();

        Assert.isTrue(secondOutcome.success, secondOutcome.message);
        Id secondGuestAccountId = [SELECT AccountId FROM Order WHERE Id = :secondOutcome.orderId].AccountId;
        Assert.areEqual(firstGuestAccountId, secondGuestAccountId, 'Repeat guest orders for the same email must reuse the same Guest Account.');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Is_Guest__c = true AND Id IN (SELECT AccountId FROM Contact WHERE Email = 'repeat-guest@20three.digital')]
        );
    }

    @IsTest
    static void guestWithoutRegisteredParentCreatesOneAccountReusedByLaterGuestOrders() {
        Map<String, Object> firstPayload = buildPayload('00000515', true, 'pure-guest@20three.digital', 'cust-515-session-a');
        Id firstStagingId = CARAOrderSyncService.capturePayload('00000515', JSON.serialize(firstPayload));
        CARAOrderSyncService.SyncOutcome firstOutcome = CARAOrderSyncService.syncFromStaging(firstStagingId);
        Assert.isTrue(firstOutcome.success, firstOutcome.message);
        Id firstGuestAccountId = [SELECT AccountId FROM Order WHERE Id = :firstOutcome.orderId].AccountId;
        Account firstGuestAccount = [SELECT Is_Guest__c, ParentId FROM Account WHERE Id = :firstGuestAccountId];
        Assert.isTrue(firstGuestAccount.Is_Guest__c);
        Assert.isNull(firstGuestAccount.ParentId, 'No Registered parent exists yet, so the Guest Account must not be linked to one.');

        Map<String, Object> secondPayload = buildPayload('00000516', true, 'pure-guest@20three.digital', 'cust-516-session-b');
        Id secondStagingId = CARAOrderSyncService.capturePayload('00000516', JSON.serialize(secondPayload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome secondOutcome = CARAOrderSyncService.syncFromStaging(secondStagingId);
        Test.stopTest();

        Assert.isTrue(secondOutcome.success, secondOutcome.message);
        Id secondGuestAccountId = [SELECT AccountId FROM Order WHERE Id = :secondOutcome.orderId].AccountId;
        Assert.areEqual(firstGuestAccountId, secondGuestAccountId, 'The second guest order must reuse the same Guest Account.');
        Assert.areEqual(2, [SELECT COUNT() FROM Order WHERE AccountId = :firstGuestAccountId]);
    }

    // =========================================================
    // Root-cause regression: a guest order followed by a registered order
    // for the same email must not corrupt the Registered Account's identity
    // or spin off a spurious Duplicate_Of__c Account. This reproduces the
    // exact sequence found in Cara Sandbox (a guest order overwriting a
    // shared Account's External ID, which then looked like a customerId
    // conflict to the next registered order).
    // =========================================================
    @IsTest
    static void registeredOrderAfterPriorGuestOrderLinksRatherThanDuplicatesTheRegisteredAccount() {
        Map<String, Object> guestPayload = buildPayload('00000517', true, 'guest-then-registered@20three.digital', 'cust-517-guest-session');
        Id guestStagingId = CARAOrderSyncService.capturePayload('00000517', JSON.serialize(guestPayload));
        CARAOrderSyncService.SyncOutcome guestOutcome = CARAOrderSyncService.syncFromStaging(guestStagingId);
        Assert.isTrue(guestOutcome.success, guestOutcome.message);
        Id guestAccountId = [SELECT AccountId FROM Order WHERE Id = :guestOutcome.orderId].AccountId;

        Map<String, Object> registeredPayload = buildPayload('00000518', false, 'guest-then-registered@20three.digital', 'cust-517-registered');
        Id registeredStagingId = CARAOrderSyncService.capturePayload('00000518', JSON.serialize(registeredPayload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome registeredOutcome = CARAOrderSyncService.syncFromStaging(registeredStagingId);
        Test.stopTest();

        Assert.isTrue(registeredOutcome.success, registeredOutcome.message);
        Id registeredAccountId = [SELECT AccountId FROM Order WHERE Id = :registeredOutcome.orderId].AccountId;
        Assert.areNotEqual(guestAccountId, registeredAccountId, 'The registered order must use its own Registered Account, not the Guest Account.');

        Account registeredAccount = [SELECT Is_Guest__c, External_ID__c, Duplicate_Of__c FROM Account WHERE Id = :registeredAccountId];
        Assert.isFalse(registeredAccount.Is_Guest__c);
        Assert.areEqual('cust-517-registered', registeredAccount.External_ID__c);
        Assert.isNull(registeredAccount.Duplicate_Of__c, 'A first-time registered order must not be flagged as a conflicting duplicate.');

        Account guestAccount = [SELECT Is_Guest__c, External_ID__c, ParentId FROM Account WHERE Id = :guestAccountId];
        Assert.isTrue(guestAccount.Is_Guest__c);
        Assert.areEqual('cust-517-guest-session', guestAccount.External_ID__c, 'The Guest Account\'s own identity must be untouched by the later registered order.');
        Assert.areEqual(registeredAccountId, guestAccount.ParentId, 'The pre-existing Guest Account must be linked under the newly identified Registered Account.');

        // A second, later registered order for the same person (same stable
        // customerId) must reuse the Registered Account, not spin off a new
        // Duplicate_Of__c Account - the exact bug reproduced in Cara Sandbox.
        Map<String, Object> secondRegisteredPayload = buildPayload('00000519', false, 'guest-then-registered@20three.digital', 'cust-517-registered');
        Id secondStagingId = CARAOrderSyncService.capturePayload('00000519', JSON.serialize(secondRegisteredPayload));
        CARAOrderSyncService.SyncOutcome secondRegisteredOutcome = CARAOrderSyncService.syncFromStaging(secondStagingId);
        Assert.isTrue(secondRegisteredOutcome.success, secondRegisteredOutcome.message);
        Id secondRegisteredAccountId = [SELECT AccountId FROM Order WHERE Id = :secondRegisteredOutcome.orderId].AccountId;
        Assert.areEqual(registeredAccountId, secondRegisteredAccountId, 'A repeat registered order for the same customerId must reuse the Registered Account, not create a duplicate.');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Is_Guest__c = false AND Id IN (SELECT AccountId FROM Contact WHERE Email = 'guest-then-registered@20three.digital')],
            'Exactly one Registered Account must exist for this person after the full guest -> registered -> registered lifecycle.'
        );
    }

    // =========================================================
    // Custom Product Request -> Case linking: SFCC never echoes the
    // Basket_Id__c, CPR number, or Case number back on a custom order, so a
    // custom line item is only recognizable by carrying c_depositAmount/
    // c_quotedUnitPrice. These must match exactly one open (Approved, basket
    // Created, not yet linked) Custom Product Request before Case.Related_
    // Order__c is set automatically — zero or multiple matches raise a
    // warning instead of guessing.
    // =========================================================
    @IsTest
    static void customOrderLinksCaseToOrderWhenExactlyOneApprovedRequestMatches() {
        Id productId = [SELECT Id FROM Product2 WHERE ProductCode = :PRODUCT_CODE LIMIT 1].Id;
        Account account = new Account(Name = 'Test Customer', Is_Guest__c = false, External_ID__c = 'cust-cpr-520');
        insert account;
        insert new Contact(AccountId = account.Id, LastName = 'Customer', Email = 'cpr-match@20three.digital', Is_Guest__c = false);
        Case caseRecord = new Case(AccountId = account.Id);
        insert caseRecord;
        insert new Custom_Product_Request__c(
            Case__c = caseRecord.Id,
            Product__c = productId,
            Product_Name__c = 'CARA Sync Test Product',
            Deposit_Amount__c = 100,
            Selling_Price__c = 400,
            Status__c = 'Approved',
            Basket_Status__c = 'Created',
            Quantity__c = 1
        );

        Map<String, Object> payload = addCustomProductFields(
            buildPayload('00000520', false, 'cpr-match@20three.digital', 'cust-cpr-520'),
            100,
            400
        );
        Id stagingId = CARAOrderSyncService.capturePayload('00000520', JSON.serialize(payload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome outcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Test.stopTest();

        Assert.isTrue(outcome.success, outcome.message);
        Case updatedCase = [SELECT Related_Order__c FROM Case WHERE Id = :caseRecord.Id];
        Assert.areEqual(outcome.orderId, updatedCase.Related_Order__c, 'The matching Custom Product Request\'s Case must be linked to the new Order.');
    }

    @IsTest
    static void customOrderWithNoMatchingRequestLeavesCaseUnlinkedAndWarns() {
        Map<String, Object> payload = addCustomProductFields(
            buildPayload('00000521', false, 'cpr-nomatch@20three.digital', 'cust-cpr-521'),
            100,
            400
        );
        Id stagingId = CARAOrderSyncService.capturePayload('00000521', JSON.serialize(payload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome outcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Test.stopTest();

        Assert.isTrue(outcome.success, outcome.message);
        Assert.areEqual(1, outcome.warnings.size());
        Assert.isTrue(
            outcome.warnings[0].contains('No open, Approved Custom Product Request'),
            'A custom line item with no matching Custom Product Request must raise a warning instead of failing the order.'
        );
    }

    @IsTest
    static void customOrderWithAmbiguousMatchesLeavesCaseUnlinkedAndWarns() {
        Id productId = [SELECT Id FROM Product2 WHERE ProductCode = :PRODUCT_CODE LIMIT 1].Id;
        Account account = new Account(Name = 'Test Customer', Is_Guest__c = false, External_ID__c = 'cust-cpr-522');
        insert account;
        insert new Contact(AccountId = account.Id, LastName = 'Customer', Email = 'cpr-ambiguous@20three.digital', Is_Guest__c = false);
        Case firstCase = new Case(AccountId = account.Id);
        Case secondCase = new Case(AccountId = account.Id);
        insert new List<Case>{ firstCase, secondCase };
        insert new List<Custom_Product_Request__c>{
            new Custom_Product_Request__c(
                Case__c = firstCase.Id,
                Product__c = productId,
                Product_Name__c = 'CARA Sync Test Product',
                Deposit_Amount__c = 100,
                Selling_Price__c = 400,
                Status__c = 'Approved',
                Basket_Status__c = 'Created',
                Quantity__c = 1
            ),
            new Custom_Product_Request__c(
                Case__c = secondCase.Id,
                Product__c = productId,
                Product_Name__c = 'CARA Sync Test Product',
                Deposit_Amount__c = 100,
                Selling_Price__c = 400,
                Status__c = 'Approved',
                Basket_Status__c = 'Created',
                Quantity__c = 1
            )
        };

        Map<String, Object> payload = addCustomProductFields(
            buildPayload('00000522', false, 'cpr-ambiguous@20three.digital', 'cust-cpr-522'),
            100,
            400
        );
        Id stagingId = CARAOrderSyncService.capturePayload('00000522', JSON.serialize(payload));

        Test.startTest();
        CARAOrderSyncService.SyncOutcome outcome = CARAOrderSyncService.syncFromStaging(stagingId);
        Test.stopTest();

        Assert.isTrue(outcome.success, outcome.message);
        Assert.areEqual(1, outcome.warnings.size());
        Assert.isTrue(
            outcome.warnings[0].contains('Multiple Custom Product Requests match'),
            'Ambiguous matches must raise a warning instead of guessing which Case to link.'
        );
        Assert.isNull([SELECT Related_Order__c FROM Case WHERE Id = :firstCase.Id].Related_Order__c);
        Assert.isNull([SELECT Related_Order__c FROM Case WHERE Id = :secondCase.Id].Related_Order__c);
    }

    private static Map<String, Object> addCustomProductFields(Map<String, Object> payload, Decimal depositAmount, Decimal quotedUnitPrice) {
        List<Object> items = (List<Object>) payload.get('productItems');
        Map<String, Object> item = (Map<String, Object>) items[0];
        item.put('c_depositAmount', depositAmount);
        item.put('c_quotedUnitPrice', quotedUnitPrice);
        return payload;
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