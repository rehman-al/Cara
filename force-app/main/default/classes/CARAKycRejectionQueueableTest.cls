@IsTest
private class CARAKycRejectionQueueableTest {

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        Account testAccount = new Account(Name = 'KYC Rejection Test Customer');
        insert testAccount;

        // Test-isolated org default — does not touch the real org's
        // configured secret (which is entered via Setup, never in source).
        insert new SFSC_Order_Ops_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Order_Ops_Secret__c = 'test-secret-value'
        );
    }


    private static Order buildOrder(String orderNo, String paymentStatus) {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Order orderRecord = new Order(
            AccountId = testAccount.Id,
            Status = 'On Hold',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            OrderReferenceNumber = orderNo,
            Storefront_Site_ID__c = 'CARA_AE',
            Payment_Status__c = paymentStatus,
            Product_Total__c = 900,
            Shipping_Total_Cost__c = 50,
            Tax_Total_Amount__c = 50
        );
        insert orderRecord;

        // Salesforce requires an Order to have at least one product before it
        // can be Activated — needed so the KYC_Approved_Activate_Order flow
        // (triggered elsewhere in this suite) can succeed.
        Product2 product = new Product2(Name = 'KYC Test Product ' + orderNo, IsActive = true);
        insert product;
        PricebookEntry standardEntry = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 900,
            IsActive = true
        );
        insert standardEntry;
        insert new OrderItem(
            OrderId = orderRecord.Id,
            PricebookEntryId = standardEntry.Id,
            Quantity = 1,
            UnitPrice = 900
        );

        return orderRecord;
    }


    private static Case buildRejectedCase(Order relatedOrder) {
        Id complianceRecordTypeId;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Compliance' LIMIT 1
        ]) {
            complianceRecordTypeId = rt.Id;
        }

        Case caseRecord = new Case(
            RecordTypeId = complianceRecordTypeId,
            Subject = 'KYC Compliance Review',
            Status = 'Compliance Rejected',
            KYC_Order__c = relatedOrder.Id
        );
        insert caseRecord;
        return caseRecord;
    }


    private static Case queryCase(Id caseId) {
        return [
            SELECT Id, Status, KYC_Rejection_Status__c, KYC_Rejection_Log__c
            FROM Case
            WHERE Id = :caseId
        ];
    }


    private static Order queryOrder(Id orderId) {
        return [SELECT Id, Status FROM Order WHERE Id = :orderId];
    }


    // =========================================================
    // 1. Approved case — no new automation, existing behavior unchanged.
    // =========================================================
    @IsTest
    static void approvedCaseIsNotTouchedByRejectionHandler() {
        Order orderRecord = buildOrder('ORD-APPROVED-001', 'CAPTURED');

        Id complianceRecordTypeId;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Compliance' LIMIT 1
        ]) {
            complianceRecordTypeId = rt.Id;
        }

        Case approvedCase = new Case(
            RecordTypeId = complianceRecordTypeId,
            Subject = 'KYC Compliance Review',
            Status = 'Compliance Approved',
            KYC_Order__c = orderRecord.Id
        );

        Test.startTest();
        insert approvedCase;
        Test.stopTest();

        Case result = queryCase(approvedCase.Id);
        System.assertEquals(null, result.KYC_Rejection_Status__c, 'Approval must not trigger rejection handling.');
        System.assertEquals('Compliance Approved', result.Status);
    }


    // =========================================================
    // 2. Rejected + AUTHORISED -> cancel succeeds, nothing was captured ->
    //    Case closes immediately, no refund-record call fires.
    // =========================================================
    @IsTest
    static void rejectedAuthorisedOrderCancelsAndClosesWithoutRefund() {
        Order orderRecord = buildOrder('ORD-AUTH-001', 'AUTHORISED');
        CARAKycRejectionTestMock mock = new CARAKycRejectionTestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Case caseRecord = buildRejectedCase(orderRecord);
        Test.stopTest();

        Case result = queryCase(caseRecord.Id);
        System.assertEquals('Completed', result.KYC_Rejection_Status__c);
        System.assertEquals('Closed', result.Status);
        System.assert(result.KYC_Rejection_Log__c.contains('no refund is required'), 'Log should note no refund was required.');

        System.assertEquals(1, mock.capturedRequests.size(), 'Only the cancel call should have fired, not refund-record.');
        Map<String, Object> cancelPayload = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedRequests[0].getBody());
        System.assertEquals('ORD-AUTH-001', cancelPayload.get('orderNo'));
        System.assertEquals('CARA_AE', cancelPayload.get('siteId'));
        System.assertEquals('KYC rejected', cancelPayload.get('reason'));
        System.assertEquals('CUSTOMERREQUEST', cancelPayload.get('cancelCode'));
        System.assertEquals('REVERSED', cancelPayload.get('paymentState'));
        System.assertEquals('test-secret-value', mock.capturedRequests[0].getHeader('X-SFSC-Order-Secret'));
        System.assertEquals('Cancelled', queryOrder(orderRecord.Id).Status, 'Order must be Cancelled once the (no-refund-needed) cancellation succeeds.');
    }


    // =========================================================
    // 3. Rejected + CAPTURED -> cancel succeeds, then the refund is
    //    reported to SFCC immediately and the Case closes.
    // =========================================================
    @IsTest
    static void rejectedCapturedOrderCancelsAndRecordsRefund() {
        Order orderRecord = buildOrder('ORD-CAP-001', 'CAPTURED');
        CARAKycRejectionTestMock mock = new CARAKycRejectionTestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Case caseRecord = buildRejectedCase(orderRecord);
        Test.stopTest();

        Case result = queryCase(caseRecord.Id);
        System.assertEquals('Completed', result.KYC_Rejection_Status__c);
        System.assertEquals('Closed', result.Status);
        System.assert(result.KYC_Rejection_Log__c.contains('refund recorded back to SFCC'), 'Log should note the refund was recorded.');

        System.assertEquals(2, mock.capturedRequests.size(), 'Both the cancel call and refund-record call should have fired.');
        Map<String, Object> refundPayload = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedRequests[1].getBody());
        System.assertEquals('ORD-CAP-001', refundPayload.get('orderNo'));
        System.assertEquals('CARA_AE', refundPayload.get('siteId'));
        System.assertEquals('ORD-CAP-001', refundPayload.get('refundReference'));
        System.assertEquals(1000, (Decimal) refundPayload.get('refundAmount'));
        System.assertEquals('Refund Successful', refundPayload.get('refundStatus'));
        System.assertEquals('KYC rejected', refundPayload.get('refundReason'));
        System.assertEquals('SFSC-KYC-Automation', refundPayload.get('refundInitiatedBy'));
        System.assertEquals('CAPTURED', refundPayload.get('paymentStatus'));
        System.assertEquals('REFUNDED', refundPayload.get('paymentState'));
        System.assertNotEquals(null, refundPayload.get('refundRequestedAt'));
        System.assertNotEquals(null, refundPayload.get('refundCompletedAt'));
        System.assertEquals('Cancelled', queryOrder(orderRecord.Id).Status, 'Order must be Cancelled once cancellation + refund both succeed.');
    }


    @IsTest
    static void rejectedPurchasedOrderTreatedSameAsCaptured() {
        Order orderRecord = buildOrder('ORD-PUR-001', 'PURCHASED');
        CARAKycRejectionTestMock mock = new CARAKycRejectionTestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Case caseRecord = buildRejectedCase(orderRecord);
        Test.stopTest();

        Case result = queryCase(caseRecord.Id);
        System.assertEquals('Completed', result.KYC_Rejection_Status__c);
        System.assertEquals('Closed', result.Status);
        System.assertEquals('Cancelled', queryOrder(orderRecord.Id).Status);
    }


    // =========================================================
    // 4. Cancel API failure -> Case = Failed, never closed, Order untouched.
    // =========================================================
    @IsTest
    static void cancelApiFailureLeavesCaseFailedNotClosed() {
        Order orderRecord = buildOrder('ORD-CANCELFAIL-001', 'CAPTURED');
        CARAKycRejectionTestMock mock = new CARAKycRejectionTestMock();
        mock.cancelStatusCode = 500;
        mock.cancelBody = '{"error":"downstream unavailable"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Case caseRecord = buildRejectedCase(orderRecord);
        Test.stopTest();

        Case result = queryCase(caseRecord.Id);
        System.assertEquals('Failed', result.KYC_Rejection_Status__c);
        System.assertNotEquals('Closed', result.Status);
        System.assert(result.KYC_Rejection_Log__c.contains('500'), 'Log should capture the failing status code.');
        System.assertNotEquals('Cancelled', queryOrder(orderRecord.Id).Status, 'A failed cancel call must never mark the Order Cancelled.');
    }


    // =========================================================
    // 5. Refund-record callout failure -> Order still moves to Cancelled
    //    (cancellation itself succeeded at SFCC); Case is left at
    //    'Order Cancelled' (not 'Completed', not 'Failed') so the refund
    //    failure is separately identifiable and a retry never re-cancels
    //    an already-cancelled order.
    // =========================================================
    @IsTest
    static void refundRecordFailureDoesNotBlockOrderCancellation() {
        Order orderRecord = buildOrder('ORD-REFUNDFAIL-001', 'CAPTURED');
        CARAKycRejectionTestMock mock = new CARAKycRejectionTestMock();
        mock.refundRecordStatusCode = 500;
        mock.refundRecordBody = '{"error":"refund record failed"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Case caseRecord = buildRejectedCase(orderRecord);
        Test.stopTest();

        Case result = queryCase(caseRecord.Id);
        System.assertEquals('Order Cancelled', result.KYC_Rejection_Status__c, 'Refund failure must be separately identifiable from a full completion.');
        System.assertNotEquals('Closed', result.Status, 'Case stays open so the refund failure gets manual follow-up.');
        System.assert(result.KYC_Rejection_Log__c.contains('recording the refund back to SFCC failed'), 'Log should note the refund-record failure.');
        System.assertEquals('Cancelled', queryOrder(orderRecord.Id).Status, 'A failed refund record must never roll back a successful cancellation.');
    }


    // =========================================================
    // 5b. Payment state not applicable (e.g. blank / unrecognised) ->
    //     no refund rule applies, so cancellation completes cleanly just
    //     like the AUTHORISED (no-refund-needed) case.
    // =========================================================
    @IsTest
    static void paymentStateNotApplicableCancelsWithoutRefund() {
        Order orderRecord = buildOrder('ORD-NOSTATE-001', 'INITIATED');
        CARAKycRejectionTestMock mock = new CARAKycRejectionTestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Case caseRecord = buildRejectedCase(orderRecord);
        Test.stopTest();

        Case result = queryCase(caseRecord.Id);
        System.assertEquals('Completed', result.KYC_Rejection_Status__c);
        System.assertEquals('Closed', result.Status);
        System.assert(result.KYC_Rejection_Log__c.contains('no refund is applicable'), 'Log should note no refund rule applied.');
        System.assertEquals(1, mock.capturedRequests.size(), 'Only the cancel call should fire when payment state is not applicable.');
        System.assertEquals('Cancelled', queryOrder(orderRecord.Id).Status, 'A non-CAPTURED payment status must never block cancellation.');
    }


    // =========================================================
    // 6. Idempotency — a Case already processed is never re-run.
    // =========================================================
    @IsTest
    static void alreadyProcessedCaseIsNotReprocessed() {
        Order orderRecord = buildOrder('ORD-IDEMPOTENT-001', 'AUTHORISED');
        CARAKycRejectionTestMock mock = new CARAKycRejectionTestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Case caseRecord = buildRejectedCase(orderRecord);

        Test.startTest();
        // Re-trigger the same transition path directly (simulates a second
        // Flow interview for the same Case, e.g. a duplicate save event).
        CARAKycRejectionHandler.handleRejection(new List<Id>{ caseRecord.Id });
        Test.stopTest();

        // First run (from insert, above) already made 1 call; the manual
        // re-invocation above must be a no-op because status is now
        // 'Completed', which is in the already-handled set.
        System.assertEquals(1, mock.capturedRequests.size(), 'A Case already in flight must not be reprocessed.');
    }


    // =========================================================
    // 8. Verify Case status/log fields exist and are populated on the
    //    happy path up to the safe halt (covered above); explicitly
    //    check the Order-less case is handled safely too.
    // =========================================================
    @IsTest
    static void caseWithNoRelatedOrderFailsSafely() {
        Id complianceRecordTypeId;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Compliance' LIMIT 1
        ]) {
            complianceRecordTypeId = rt.Id;
        }

        Case caseRecord = new Case(
            RecordTypeId = complianceRecordTypeId,
            Subject = 'KYC Compliance Review - No Order',
            Status = 'Compliance Rejected'
        );

        Test.startTest();
        insert caseRecord;
        Test.stopTest();

        Case result = queryCase(caseRecord.Id);
        System.assertEquals('Failed', result.KYC_Rejection_Status__c);
        System.assert(result.KYC_Rejection_Log__c.contains('No related Order'));
    }


    // =========================================================
    // Shared mock — captures every request and lets each test override
    // the response per endpoint.
    // =========================================================
    private class CARAKycRejectionTestMock implements HttpCalloutMock {
        public Integer cancelStatusCode = 200;
        public String cancelBody = '{"success":true,"status":"cancelled"}';
        public Integer refundRecordStatusCode = 200;
        public String refundRecordBody = '{"success":true}';
        public List<HttpRequest> capturedRequests = new List<HttpRequest>();

        public HttpResponse respond(HttpRequest request) {
            capturedRequests.add(request);

            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (request.getEndpoint().contains('sfsc-order-cancel')) {
                response.setStatusCode(cancelStatusCode);
                response.setBody(cancelBody);
            } else {
                response.setStatusCode(refundRecordStatusCode);
                response.setBody(refundRecordBody);
            }
            return response;
        }
    }
}