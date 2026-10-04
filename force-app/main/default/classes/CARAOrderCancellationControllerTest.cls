@IsTest
private class CARAOrderCancellationControllerTest {

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        Account testAccount = new Account(Name = 'Order Cancellation Test Customer');
        insert testAccount;

        insert new SFSC_Order_Ops_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Order_Ops_Secret__c = 'test-secret-value'
        );
    }


    private static Order buildOrder(String orderNo, String paymentStatus, String status) {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Order orderRecord = new Order(
            AccountId = testAccount.Id,
            Status = status,
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
        return orderRecord;
    }


    private static Order queryOrder(Id orderId) {
        return [SELECT Id, Status FROM Order WHERE Id = :orderId];
    }


    @IsTest
    static void authorisedOrderVoidsAndCancels() {
        Order orderRecord = buildOrder('ORD-MAN-AUTH-001', 'AUTHORISED', 'On Hold');
        CARAOrderCancellationTestMock mock = new CARAOrderCancellationTestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderCancellationController.CancelOrderResult result = CARAOrderCancellationController.cancelOrder(orderRecord.Id);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Cancelled', queryOrder(orderRecord.Id).Status);
        System.assertEquals(1, mock.capturedRequests.size(), 'Only the cancel call should fire when no refund is required.');
    }


    @IsTest
    static void capturedOrderRefundsAndCancels() {
        Order orderRecord = buildOrder('ORD-MAN-CAP-001', 'CAPTURED', 'On Hold');
        CARAOrderCancellationTestMock mock = new CARAOrderCancellationTestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderCancellationController.CancelOrderResult result = CARAOrderCancellationController.cancelOrder(orderRecord.Id);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Cancelled', queryOrder(orderRecord.Id).Status);
        System.assertEquals(2, mock.capturedRequests.size(), 'Both the cancel call and refund-record call should fire.');
    }


    @IsTest
    static void alreadyCancelledOrderIsNotReprocessed() {
        Order orderRecord = buildOrder('ORD-MAN-DUP-001', 'CAPTURED', 'Cancelled');
        CARAOrderCancellationTestMock mock = new CARAOrderCancellationTestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderCancellationController.CancelOrderResult result = CARAOrderCancellationController.cancelOrder(orderRecord.Id);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('already Cancelled'));
        System.assertEquals(0, mock.capturedRequests.size(), 'An already-Cancelled Order must never trigger a callout.');
    }


    @IsTest
    static void cancelApiFailureLeavesOrderUnchanged() {
        Order orderRecord = buildOrder('ORD-MAN-CANCELFAIL-001', 'CAPTURED', 'On Hold');
        CARAOrderCancellationTestMock mock = new CARAOrderCancellationTestMock();
        mock.cancelStatusCode = 500;
        mock.cancelBody = '{"error":"downstream unavailable"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderCancellationController.CancelOrderResult result = CARAOrderCancellationController.cancelOrder(orderRecord.Id);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertNotEquals('Cancelled', queryOrder(orderRecord.Id).Status);
    }


    @IsTest
    static void refundRecordFailureDoesNotBlockCancellation() {
        Order orderRecord = buildOrder('ORD-MAN-REFUNDFAIL-001', 'CAPTURED', 'On Hold');
        CARAOrderCancellationTestMock mock = new CARAOrderCancellationTestMock();
        mock.refundRecordStatusCode = 500;
        mock.refundRecordBody = '{"error":"refund record failed"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderCancellationController.CancelOrderResult result = CARAOrderCancellationController.cancelOrder(orderRecord.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'A refund failure must not roll back a successful cancellation.');
        System.assertEquals(true, result.refundFailed, 'The refund failure must be separately identifiable.');
        System.assert(result.message.contains('refund could not be completed'), 'CSR must see the refund failure.');
        System.assertEquals('Cancelled', queryOrder(orderRecord.Id).Status, 'Order must remain Cancelled even though the refund failed.');
    }


    @IsTest
    static void nonCapturedUnrecognisedPaymentStatusCancelsWithoutRefund() {
        Order orderRecord = buildOrder('ORD-MAN-NOSTATE-001', 'INITIATED', 'On Hold');
        CARAOrderCancellationTestMock mock = new CARAOrderCancellationTestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderCancellationController.CancelOrderResult result = CARAOrderCancellationController.cancelOrder(orderRecord.Id);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(false, result.refundFailed, 'No refund is applicable for a non-captured payment state, so there is nothing to fail.');
        System.assertEquals('Cancelled', queryOrder(orderRecord.Id).Status, 'A non-CAPTURED payment status must never block cancellation.');
        System.assertEquals(1, mock.capturedRequests.size(), 'Only the cancel call should fire when no refund is applicable.');
    }


    private class CARAOrderCancellationTestMock implements HttpCalloutMock {
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