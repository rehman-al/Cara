@IsTest
private class CARABalancePaymentRestServiceTest {
    private static final String ORDER_REF = 'ORD-BAL-REST-001';

    @TestSetup
    static void createOrderData() {
        Account accountRecord = new Account(Name = 'Balance Payment REST Test Customer');
        insert accountRecord;

        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        Order orderRecord = new Order(
            AccountId = accountRecord.Id,
            OrderReferenceNumber = ORDER_REF,
            Status = 'On Hold',
            EffectiveDate = Date.today(),
            Pricebook2Id = standardPricebookId,
            Balance_Remaining__c = 750,
            Balance_Already_Paid__c = false,
            Balance_Link_Status__c = 'Sent'
        );
        insert orderRecord;
    }

    @IsTest
    static void successfulConfirmationReturns200AndOrderReference() {
        Test.startTest();
        invokeService(ORDER_REF, 'NGENIUS-TXN-REST-1', 'SUCCESS', 750, 'AED');
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(true, responseBody.get('success'));
        Assert.areEqual(true, responseBody.get('paymentProcessed'));
        Assert.areEqual(ORDER_REF, responseBody.get('orderReferenceNumber'));
        Assert.isNotNull(responseBody.get('salesforceOrderId'));

        Order updated = [SELECT Balance_Already_Paid__c FROM Order WHERE OrderReferenceNumber = :ORDER_REF];
        Assert.isTrue(updated.Balance_Already_Paid__c);
    }

    @IsTest
    static void duplicateCallbackReturns200Idempotent() {
        invokeService(ORDER_REF, 'NGENIUS-TXN-REST-1', 'SUCCESS', 750, 'AED');

        Test.startTest();
        invokeService(ORDER_REF, 'NGENIUS-TXN-REST-1', 'SUCCESS', 750, 'AED');
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(true, responseBody.get('alreadyProcessed'));
    }

    @IsTest
    static void failedPaymentReturns200ButDoesNotMarkPaid() {
        Test.startTest();
        invokeService(ORDER_REF, 'NGENIUS-TXN-REST-2', 'FAILED', 750, 'AED');
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(false, responseBody.get('paymentProcessed'));

        Order updated = [SELECT Balance_Already_Paid__c FROM Order WHERE OrderReferenceNumber = :ORDER_REF];
        Assert.isFalse(updated.Balance_Already_Paid__c);
    }

    @IsTest
    static void unknownOrderReturns404() {
        Test.startTest();
        invokeService('DOES-NOT-EXIST', 'NGENIUS-TXN-REST-3', 'SUCCESS', 750, 'AED');
        Test.stopTest();

        Assert.areEqual(404, RestContext.response.statusCode);
    }

    @IsTest
    static void amountMismatchReturns409() {
        Test.startTest();
        invokeService(ORDER_REF, 'NGENIUS-TXN-REST-4', 'SUCCESS', 1, 'AED');
        Test.stopTest();

        Assert.areEqual(409, RestContext.response.statusCode);
    }

    // 13 — a malformed/empty request body is rejected with a controlled error,
    // not an uncaught exception or a 200. Authentication/authorization itself
    // is enforced by the SFCC_Ingestion_App External Client App's OAuth policy
    // ahead of this Apex, matching the existing CARAOrderRestService /
    // CARAOrderStatusRestService endpoints — there is no in-Apex secret check
    // to unit test here, consistent with those sibling services.
    @IsTest
    static void emptyRequestBodyIsRejected() {
        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/orders/balancePaymentConfirmation';
        requestRecord.httpMethod = 'POST';
        requestRecord.requestBody = Blob.valueOf('');
        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();

        Test.startTest();
        CARABalancePaymentRestService.confirmBalancePayment();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void missingFieldsReturnValidationError() {
        Test.startTest();
        invokeService(null, null, null, null, null);
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        String responseBody = RestContext.response.responseBody.toString();
        Assert.isTrue(responseBody.contains('orderReferenceNumber'));
    }

    private static void invokeService(String orderReferenceNumber, String paymentReference, String paymentStatus, Decimal amount, String currencyCode) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('orderReferenceNumber', orderReferenceNumber);
        payload.put('paymentReference', paymentReference);
        payload.put('paymentStatus', paymentStatus);
        payload.put('amount', amount);
        payload.put('currencyCode', currencyCode);
        payload.put('paymentTimestamp', '2026-10-04T10:15:00Z');
        payload.put('siteId', 'bmqp-ae');

        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/orders/balancePaymentConfirmation';
        requestRecord.httpMethod = 'POST';
        requestRecord.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
        CARABalancePaymentRestService.confirmBalancePayment();
    }
}