@IsTest
private class CARABalancePaymentServiceTest {
    private static final String ORDER_REF = 'ORD-BAL-001';

    @TestSetup
    static void createOrderData() {
        Account accountRecord = new Account(Name = 'Balance Payment Test Customer');
        insert accountRecord;

        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        Order orderRecord = new Order(
            AccountId = accountRecord.Id,
            OrderReferenceNumber = ORDER_REF,
            Status = 'On Hold',
            EffectiveDate = Date.today(),
            Pricebook2Id = standardPricebookId,
            Balance_Link__c = 'https://sfccdev.carajewellers.com/en-AE/pay/balance?orderNo=' + ORDER_REF,
            Balance_Remaining__c = 500,
            Balance_Already_Paid__c = false,
            Balance_Link_Status__c = 'Sent'
        );
        insert orderRecord;
    }

    private static CARABalancePaymentService.ConfirmationRequest buildRequest(
        String orderRef,
        String paymentRef,
        String status,
        Decimal amount,
        String currencyCode
    ) {
        CARABalancePaymentService.ConfirmationRequest requestData =
            new CARABalancePaymentService.ConfirmationRequest();
        requestData.orderReferenceNumber = orderRef;
        requestData.paymentReference = paymentRef;
        requestData.paymentStatus = status;
        requestData.amount = amount;
        requestData.currencyCode = currencyCode;
        requestData.paymentTimestamp = Datetime.now().format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        requestData.siteId = 'bmqp-ae';
        return requestData;
    }

    private static Order queryOrder() {
        return [
            SELECT Balance_Already_Paid__c, Balance_Remaining__c, Balance_Link_Status__c,
                Balance_Link_Log__c, Balance_Payment_Reference__c
            FROM Order
            WHERE OrderReferenceNumber = :ORDER_REF
        ];
    }


    // 1/2/3/4/6 — successful confirmation identifies the correct Order and updates it correctly.
    @IsTest
    static void successfulConfirmationUpdatesOrderAndStoresReference() {
        Test.startTest();
        CARABalancePaymentService.ConfirmationResult result = CARABalancePaymentService.confirmBalancePayment(
            buildRequest(ORDER_REF, 'NGENIUS-TXN-1', 'SUCCESS', 500, 'AED')
        );
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.isTrue(result.paymentProcessed);
        Assert.isFalse(result.alreadyProcessed);
        Assert.areEqual('OK', result.code);
        Assert.areEqual(0, result.balanceRemaining);

        Order updated = queryOrder();
        Assert.isTrue(updated.Balance_Already_Paid__c);
        Assert.areEqual(0, updated.Balance_Remaining__c);
        Assert.areEqual('Paid', updated.Balance_Link_Status__c);
        Assert.areEqual('NGENIUS-TXN-1', updated.Balance_Payment_Reference__c);
        Assert.isTrue(updated.Balance_Link_Log__c.contains('NGENIUS-TXN-1'));
    }


    // 7/8 — a duplicate successful callback is idempotent: no re-processing, no duplicate updates.
    @IsTest
    static void duplicateSuccessfulCallbackIsIdempotent() {
        CARABalancePaymentService.confirmBalancePayment(
            buildRequest(ORDER_REF, 'NGENIUS-TXN-1', 'SUCCESS', 500, 'AED')
        );
        Order afterFirst = queryOrder();

        Test.startTest();
        CARABalancePaymentService.ConfirmationResult result = CARABalancePaymentService.confirmBalancePayment(
            buildRequest(ORDER_REF, 'NGENIUS-TXN-1', 'SUCCESS', 500, 'AED')
        );
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.isTrue(result.alreadyProcessed);
        Assert.isTrue(result.paymentProcessed);
        Assert.areEqual('ALREADY_PROCESSED', result.code);

        Order afterSecond = queryOrder();
        Assert.areEqual(afterFirst.Balance_Link_Log__c, afterSecond.Balance_Link_Log__c, 'No second log line should be appended.');
        Assert.areEqual(afterFirst.Balance_Payment_Reference__c, afterSecond.Balance_Payment_Reference__c);
    }


    // 9 — a failed payment notification never marks the Order as paid.
    @IsTest
    static void failedPaymentDoesNotMarkOrderPaid() {
        Test.startTest();
        CARABalancePaymentService.ConfirmationResult result = CARABalancePaymentService.confirmBalancePayment(
            buildRequest(ORDER_REF, 'NGENIUS-TXN-2', 'FAILED', 500, 'AED')
        );
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.isFalse(result.paymentProcessed);
        Assert.areEqual('PAYMENT_FAILED', result.code);

        Order updated = queryOrder();
        Assert.isFalse(updated.Balance_Already_Paid__c);
        Assert.areEqual(500, updated.Balance_Remaining__c);
        Assert.areEqual('Sent', updated.Balance_Link_Status__c);
        Assert.isTrue(updated.Balance_Link_Log__c.contains('FAILED'));
    }


    // 10 — a pending payment never marks the Order as paid.
    @IsTest
    static void pendingPaymentDoesNotMarkOrderPaid() {
        Test.startTest();
        CARABalancePaymentService.ConfirmationResult result = CARABalancePaymentService.confirmBalancePayment(
            buildRequest(ORDER_REF, 'NGENIUS-TXN-3', 'PENDING', 500, 'AED')
        );
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.isFalse(result.paymentProcessed);
        Assert.areEqual('PAYMENT_PENDING', result.code);

        Order updated = queryOrder();
        Assert.isFalse(updated.Balance_Already_Paid__c);
    }


    // 11 — an unknown Order reference returns a controlled error.
    @IsTest
    static void unknownOrderReferenceReturnsControlledError() {
        Test.startTest();
        CARABalancePaymentService.ConfirmationResult result = CARABalancePaymentService.confirmBalancePayment(
            buildRequest('DOES-NOT-EXIST', 'NGENIUS-TXN-4', 'SUCCESS', 500, 'AED')
        );
        Test.stopTest();

        Assert.isFalse(result.success);
        Assert.areEqual('ORDER_NOT_FOUND', result.code);
    }


    // 12 — missing required fields return a controlled error, no DML.
    @IsTest
    static void missingRequiredFieldsReturnControlledError() {
        Test.startTest();
        CARABalancePaymentService.ConfirmationResult result = CARABalancePaymentService.confirmBalancePayment(
            buildRequest(null, null, null, null, null)
        );
        Test.stopTest();

        Assert.isFalse(result.success);
        Assert.areEqual('MISSING_REQUIRED_FIELD', result.code);

        Order unchanged = queryOrder();
        Assert.isFalse(unchanged.Balance_Already_Paid__c);
    }


    @IsTest
    static void unsupportedPaymentStatusReturnsControlledError() {
        Test.startTest();
        CARABalancePaymentService.ConfirmationResult result = CARABalancePaymentService.confirmBalancePayment(
            buildRequest(ORDER_REF, 'NGENIUS-TXN-5', 'SOMETHING_WEIRD', 500, 'AED')
        );
        Test.stopTest();

        Assert.isFalse(result.success);
        Assert.areEqual('UNSUPPORTED_PAYMENT_STATUS', result.code);

        Order unchanged = queryOrder();
        Assert.isFalse(unchanged.Balance_Already_Paid__c);
    }


    // Amount validated against the Order's existing Balance_Remaining__c.
    @IsTest
    static void amountMismatchIsRejectedAndOrderUnchanged() {
        Test.startTest();
        CARABalancePaymentService.ConfirmationResult result = CARABalancePaymentService.confirmBalancePayment(
            buildRequest(ORDER_REF, 'NGENIUS-TXN-6', 'SUCCESS', 250, 'AED')
        );
        Test.stopTest();

        Assert.isFalse(result.success);
        Assert.areEqual('AMOUNT_MISMATCH', result.code);

        Order unchanged = queryOrder();
        Assert.isFalse(unchanged.Balance_Already_Paid__c);
        Assert.areEqual(500, unchanged.Balance_Remaining__c);
    }


    // 14 — an Order update failure (here: a payment reference exceeding the
    // field's 180-char length) is reported as a controlled failure, not success.
    @IsTest
    static void orderUpdateFailureDoesNotReturnSuccess() {
        String oversizedReference = 'X'.repeat(200);

        Test.startTest();
        CARABalancePaymentService.ConfirmationResult result = CARABalancePaymentService.confirmBalancePayment(
            buildRequest(ORDER_REF, oversizedReference, 'SUCCESS', 500, 'AED')
        );
        Test.stopTest();

        Assert.isFalse(result.success);
        Assert.areEqual('ORDER_UPDATE_FAILED', result.code);

        Order unchanged = queryOrder();
        Assert.isFalse(unchanged.Balance_Already_Paid__c, 'A failed Order update must not be reported or left as paid.');
    }
}