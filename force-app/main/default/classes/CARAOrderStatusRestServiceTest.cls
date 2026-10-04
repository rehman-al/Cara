@IsTest
private class CARAOrderStatusRestServiceTest {
    private static final String ORDER_REF = '00000429';

    @TestSetup
    static void createOrderData() {
        Account accountRecord = new Account(Name = 'Test Account');
        insert accountRecord;

        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        Product2 productRecord = new Product2(Name = 'Test Product', IsActive = true);
        insert productRecord;
        insert new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true
        );

        Order orderRecord = new Order(
            AccountId = accountRecord.Id,
            OrderReferenceNumber = ORDER_REF,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert orderRecord;

        insert new OrderItem(
            OrderId = orderRecord.Id,
            Product2Id = productRecord.Id,
            PricebookEntryId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :productRecord.Id LIMIT 1].Id,
            Quantity = 1,
            UnitPrice = 100
        );
    }

    /*
     * OrderHistory's Before/After Status + timestamp capture is verified
     * against live data in Sandbox/STG (see deployment report) rather than in
     * this unit test — Apex test transactions do not reliably surface
     * platform-generated OrderHistory rows for the same DML they were
     * produced from. This test verifies the service's own responsibility:
     * updating Order.Status and reporting the before/after values correctly.
     */
    @IsTest
    static void updatesStatusOnActualChange() {
        Order orderBefore = [SELECT Id FROM Order WHERE OrderReferenceNumber = :ORDER_REF LIMIT 1];

        Test.startTest();
        invokeService(ORDER_REF, 'On Hold');
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual('Draft', responseBody.get('statusBefore'));
        Assert.areEqual('On Hold', responseBody.get('statusAfter'));
        Assert.areEqual(true, responseBody.get('statusChanged'));

        Order orderAfter = [SELECT Status FROM Order WHERE Id = :orderBefore.Id];
        Assert.areEqual('On Hold', orderAfter.Status);
    }

    @IsTest
    static void surroundingWhitespaceOnInputsIsTrimmedAndStillMatches() {
        Order orderBefore = [SELECT Id FROM Order WHERE OrderReferenceNumber = :ORDER_REF LIMIT 1];

        Test.startTest();
        invokeService('  ' + ORDER_REF + '  ', '  On Hold  ');
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        Order orderAfter = [SELECT Status FROM Order WHERE Id = :orderBefore.Id];
        Assert.areEqual('On Hold', orderAfter.Status);
    }

    @IsTest
    static void sameStatusIsIdempotentAndSkipsUpdate() {
        Order orderRecord = [SELECT Id, LastModifiedDate FROM Order WHERE OrderReferenceNumber = :ORDER_REF LIMIT 1];

        Test.startTest();
        invokeService(ORDER_REF, 'Draft');
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(false, responseBody.get('statusChanged'));

        Order orderAfter = [SELECT Status, LastModifiedDate FROM Order WHERE Id = :orderRecord.Id];
        Assert.areEqual('Draft', orderAfter.Status);
        Assert.areEqual(orderRecord.LastModifiedDate, orderAfter.LastModifiedDate);
    }

    @IsTest
    static void unknownOrderReturnsErrorAndMakesNoChange() {
        Test.startTest();
        invokeService('DOES-NOT-EXIST', 'On Hold');
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual(0, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = 'DOES-NOT-EXIST']);
    }

    @IsTest
    static void invalidStatusReturnsErrorAndMakesNoChange() {
        Order orderRecord = [SELECT Id, Status FROM Order WHERE OrderReferenceNumber = :ORDER_REF LIMIT 1];

        Test.startTest();
        invokeService(ORDER_REF, 'NotARealStatus');
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Order orderAfter = [SELECT Status FROM Order WHERE Id = :orderRecord.Id];
        Assert.areEqual(orderRecord.Status, orderAfter.Status);
    }

    @IsTest
    static void activatedOrderCannotBeMovedOutOfActivated() {
        Order orderRecord = [SELECT Id FROM Order WHERE OrderReferenceNumber = :ORDER_REF LIMIT 1];
        update new Order(Id = orderRecord.Id, Status = 'Activated');

        Test.startTest();
        invokeService(ORDER_REF, 'Draft');
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Order orderAfter = [SELECT Status FROM Order WHERE Id = :orderRecord.Id];
        Assert.areEqual('Activated', orderAfter.Status);
    }

    @IsTest
    static void missingFieldsReturnValidationError() {
        Test.startTest();
        invokeService(null, null);
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        String responseBody = RestContext.response.responseBody.toString();
        Assert.isTrue(responseBody.contains('orderReferenceNumber'));
        Assert.isTrue(responseBody.contains('status'));
    }

    private static void invokeService(String orderReferenceNumber, String status) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('orderReferenceNumber', orderReferenceNumber);
        payload.put('status', status);

        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/orders/status';
        requestRecord.httpMethod = 'POST';
        requestRecord.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
        CARAOrderStatusRestService.updateOrderStatus();
    }
}