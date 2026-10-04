/*
 * Covers the new, purely-additive Marketing Cloud email calls inside
 * CARAOrderCancellationService.cancelAndSettle() — separate from
 * CARAOrderCancellationControllerTest/CARAKycRejectionQueueableTest (which
 * intentionally don't configure CARA_Marketing_Cloud_Setting__c, so their
 * assertions on SFSC callout counts are unaffected: the email send fails
 * fast at the credential check, before any HTTP callout, and is swallowed
 * by the gateway's best-effort contract).
 */
@IsTest
private class CARAOrderCancellationServiceEmailTest {

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        insert new SFSC_Order_Ops_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Order_Ops_Secret__c = 'test-secret-value'
        );
        insert new CARA_Marketing_Cloud_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Client_Id__c = 'test-client-id',
            Client_Secret__c = 'test-client-secret'
        );

        insert new Account(Name = 'Cancel Email Test Account');
    }


    /*
     * Customer_Email__c is a formula off Contact__r.Email (not directly
     * writeable) — same convention as CARABalanceLinkQueueableTest.
     */
    private static Order buildOrder(String orderNo, String paymentStatus) {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contactRecord = new Contact(
            AccountId = account.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'shopper@example.com'
        );
        insert contactRecord;

        Order orderRecord = new Order(
            AccountId = account.Id,
            Contact__c = contactRecord.Id,
            Status = 'On Hold',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            OrderReferenceNumber = orderNo,
            Storefront_Site_ID__c = 'CARA_AE',
            Payment_Status__c = paymentStatus,
            Product_Total__c = 900,
            Shipping_Total_Cost__c = 50,
            Tax_Total_Amount__c = 50,
            Customer_Name_Plain__c = 'Jane Doe'
        );
        insert orderRecord;

        // Customer_Email__c/Customer_Name_Plain__c (read by sendCancelEmail/
        // sendRefundEmail) include a formula field — re-query rather than
        // use the just-inserted in-memory record, matching how the real
        // callers (CARAKycRejectionQueueable, CARAOrderCancellationController)
        // always re-query before calling cancelAndSettle().
        return [
            SELECT Id, OrderReferenceNumber, Storefront_Site_ID__c, Payment_Status__c,
                   CurrencyIsoCode__c, Product_Total__c, Shipping_Total_Cost__c, Tax_Total_Amount__c,
                   Customer_Email__c, Customer_Name_Plain__c
            FROM Order
            WHERE Id = :orderRecord.Id
        ];
    }


    @IsTest
    static void authorisedCancellationSendsOrderCancelEmailOnly() {
        Order orderRecord = buildOrder('ORD-EMAIL-CANCEL-1', 'AUTHORISED');

        AllPurposeMock mock = new AllPurposeMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderCancellationService.cancelAndSettle(orderRecord, 'test reason', 'tester');
        Test.stopTest();

        List<Email_Gateway_Log__c> logs = [SELECT Email_Type__c, Success__c FROM Email_Gateway_Log__c WITH SYSTEM_MODE];
        Assert.areEqual(1, logs.size());
        Assert.areEqual('ORDER_CANCEL', logs[0].Email_Type__c);
        Assert.areEqual(true, logs[0].Success__c);
    }


    @IsTest
    static void capturedPaymentSendsBothCancelAndRefundEmails() {
        Order orderRecord = buildOrder('ORD-EMAIL-REFUND-1', 'CAPTURED');

        AllPurposeMock mock = new AllPurposeMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderCancellationService.cancelAndSettle(orderRecord, 'test reason', 'tester');
        Test.stopTest();

        Set<String> emailTypesSent = new Set<String>();
        for (Email_Gateway_Log__c logRecord : [SELECT Email_Type__c, Success__c FROM Email_Gateway_Log__c WITH SYSTEM_MODE]) {
            Assert.areEqual(true, logRecord.Success__c);
            emailTypesSent.add(logRecord.Email_Type__c);
        }
        Assert.areEqual(new Set<String>{ 'ORDER_CANCEL', 'ORDER_REFUND' }, emailTypesSent);
    }


    @IsTest
    static void refundRecordFailureStillSendsCancelEmailButNotRefundEmail() {
        Order orderRecord = buildOrder('ORD-EMAIL-REFUNDFAIL-1', 'CAPTURED');

        AllPurposeMock mock = new AllPurposeMock();
        mock.refundRecordStatusCode = 500;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderCancellationService.cancelAndSettle(orderRecord, 'test reason', 'tester');
        Test.stopTest();

        List<Email_Gateway_Log__c> logs = [SELECT Email_Type__c FROM Email_Gateway_Log__c WITH SYSTEM_MODE];
        Assert.areEqual(1, logs.size(), 'No refund was recorded at SFCC, so no refund email should be attempted.');
        Assert.areEqual('ORDER_CANCEL', logs[0].Email_Type__c);
    }


    private class AllPurposeMock implements HttpCalloutMock {
        public Integer refundRecordStatusCode = 200;

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            String endpoint = request.getEndpoint();

            if (endpoint.contains('sfsc-order-cancel')) {
                response.setStatusCode(200);
                response.setBody('{"success":true,"status":"cancelled"}');
            } else if (endpoint.contains('sfsc-refund-record')) {
                response.setStatusCode(refundRecordStatusCode);
                response.setBody('{"success":true}');
            } else if (endpoint.contains('/services/oauth2/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"test-access-token"}');
            } else {
                response.setStatusCode(200);
                response.setBody('{}');
            }
            return response;
        }
    }
}