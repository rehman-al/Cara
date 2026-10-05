@IsTest
private class CARADepositBasketQueueableTest {

    @TestSetup
    static void setupData() {
        insert new SFSC_Order_Ops_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Order_Ops_Secret__c = 'test-secret-value'
        );
    }


    private static Contact buildContact() {
        Account acc = new Account(Name = 'Split Payment Test Customer');
        insert acc;

        Contact contactRecord = new Contact(
            AccountId = acc.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'shopper@example.com',
            MailingStreet = '123 Main St',
            MailingCity = 'Dubai',
            MailingPostalCode = '00000',
            MailingCountry = 'AE',
            Phone = '+971500000000'
        );
        insert contactRecord;
        return contactRecord;
    }


    private static Case buildCase(Id contactId) {
        Case caseRecord = new Case(
            ContactId = contactId,
            Subject = 'Custom Piece Request'
        );
        insert caseRecord;
        return caseRecord;
    }


    private static Product2 buildProduct() {
        Product2 productRecord = new Product2(
            Name = 'Custom Ring',
            IsActive = true,
            StockKeepingUnit = 'SKU_ID'
        );
        insert productRecord;
        return productRecord;
    }


    private static Custom_Product_Request__c buildRequest(Id caseId, Id productId, Decimal price) {
        Custom_Product_Request__c requestRecord = new Custom_Product_Request__c(
            Case__c = caseId,
            Product_Name__c = 'Custom Ring',
            Product__c = productId,
            Quantity__c = 1,
            Selling_Price__c = price,
            Status__c = 'Approved'
        );
        insert requestRecord;
        return requestRecord;
    }


    private static Custom_Product_Request__c queryRequest(Id requestId) {
        return [
            SELECT Status__c, Basket_Id__c, Deposit_Link__c, Deposit_Amount__c,
                Order_Total__c, Basket_Status__c, Basket_Log__c
            FROM Custom_Product_Request__c
            WHERE Id = :requestId
        ];
    }


    @IsTest
    static void happyPathCreatesBasketAndNotifiesCustomer() {
        Contact contactRecord = buildContact();
        Case caseRecord = buildCase(contactRecord.Id);
        Product2 productRecord = buildProduct();
        Custom_Product_Request__c requestRecord = buildRequest(caseRecord.Id, productRecord.Id, 1000);

        DepositMock mock = new DepositMock();
        mock.statusCode = 200;
        mock.body = '{"basketId":"BASKET-1","link":"/pay/deposit?basketId=BASKET-1","deposit":250,"orderTotal":1000}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARADepositBasketHandler.createDepositBaskets(new List<Id>{ requestRecord.Id });
        Test.stopTest();

        Custom_Product_Request__c result = queryRequest(requestRecord.Id);
        System.assertEquals('BASKET-1', result.Basket_Id__c);
        System.assertEquals('/pay/deposit?basketId=BASKET-1', result.Deposit_Link__c);
        System.assertEquals(250, result.Deposit_Amount__c);
        System.assertEquals(1000, result.Order_Total__c);
        System.assertEquals('Approved', result.Status__c, 'A successful basket request must remain Approved.');
        System.assertEquals('Created', result.Basket_Status__c);
        System.assert(result.Basket_Log__c.contains('Deposit basket created'));
        System.assert(result.Basket_Log__c.contains('notification: Sent to shopper@example.com'));
        System.assertEquals(1, mock.capturedRequests.size());

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedRequests[0].getBody());
        System.assertEquals('shopper@example.com', payload.get('customerLogin'));
        System.assertEquals('SKU_ID', payload.get('sku'));
        System.assertEquals(1000, (Decimal) payload.get('price'));
        System.assertEquals(250, (Decimal) payload.get('deposit'));
    }


    @IsTest
    static void missingSkuBlocksCalloutAndMarksError() {
        Contact contactRecord = buildContact();
        Case caseRecord = buildCase(contactRecord.Id);
        Custom_Product_Request__c requestRecord = buildRequest(caseRecord.Id, null, 1000);

        DepositMock mock = new DepositMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARADepositBasketHandler.createDepositBaskets(new List<Id>{ requestRecord.Id });
        Test.stopTest();

        System.assertEquals(0, mock.capturedRequests.size(), 'Missing SKU must block the callout entirely.');
        Custom_Product_Request__c result = queryRequest(requestRecord.Id);
        System.assertEquals('Under Review', result.Status__c, 'A validation failure must undo the premature approval.');
        System.assertEquals('Error', result.Basket_Status__c);
        System.assert(result.Basket_Log__c.contains('Product SKU'));
    }


    @IsTest
    static void idempotentWhenBasketAlreadyCreated() {
        Contact contactRecord = buildContact();
        Case caseRecord = buildCase(contactRecord.Id);
        Product2 productRecord = buildProduct();
        Custom_Product_Request__c requestRecord = buildRequest(caseRecord.Id, productRecord.Id, 1000);
        requestRecord.Basket_Id__c = 'EXISTING-BASKET';
        requestRecord.Basket_Status__c = 'Created';
        update requestRecord;

        DepositMock mock = new DepositMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARADepositBasketHandler.createDepositBaskets(new List<Id>{ requestRecord.Id });
        Test.stopTest();

        System.assertEquals(0, mock.capturedRequests.size(), 'An existing, created basket must never be re-created.');
    }


    @IsTest
    static void gatewayErrorAfterRetryMarksErrorStatus() {
        Contact contactRecord = buildContact();
        Case caseRecord = buildCase(contactRecord.Id);
        Product2 productRecord = buildProduct();
        Custom_Product_Request__c requestRecord = buildRequest(caseRecord.Id, productRecord.Id, 1000);

        DepositMock mock = new DepositMock();
        mock.statusCode = 502;
        mock.body = '{"error":"gateway timeout"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARADepositBasketHandler.createDepositBaskets(new List<Id>{ requestRecord.Id });
        Test.stopTest();

        Custom_Product_Request__c result = queryRequest(requestRecord.Id);
        System.assertEquals('Under Review', result.Status__c, 'A gateway failure must return the CPR to review.');
        System.assertEquals('Error', result.Basket_Status__c);
        System.assert(result.Basket_Log__c.contains(CARASfscSplitPaymentService.ERROR_GATEWAY));
        System.assertEquals(2, mock.capturedRequests.size(), 'A 502 gets exactly one retry.');
    }


    @IsTest
    static void authErrorNeverRetriedAndMarksError() {
        Contact contactRecord = buildContact();
        Case caseRecord = buildCase(contactRecord.Id);
        Product2 productRecord = buildProduct();
        Custom_Product_Request__c requestRecord = buildRequest(caseRecord.Id, productRecord.Id, 1000);

        DepositMock mock = new DepositMock();
        mock.statusCode = 401;
        mock.body = '{"error":"secret mismatch"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARADepositBasketHandler.createDepositBaskets(new List<Id>{ requestRecord.Id });
        Test.stopTest();

        Custom_Product_Request__c result = queryRequest(requestRecord.Id);
        System.assertEquals('Under Review', result.Status__c, 'An authentication failure must return the CPR to review.');
        System.assertEquals('Error', result.Basket_Status__c);
        System.assert(result.Basket_Log__c.contains(CARASfscSplitPaymentService.ERROR_AUTH));
        System.assertEquals(1, mock.capturedRequests.size(), '401 must never be retried.');
    }


    @IsTest
    static void deletedRecordIsHandledSafelyWithoutException() {
        Contact contactRecord = buildContact();
        Case caseRecord = buildCase(contactRecord.Id);
        Custom_Product_Request__c requestRecord = buildRequest(caseRecord.Id, null, 1000);
        Id deletedId = requestRecord.Id;
        delete requestRecord;

        DepositMock mock = new DepositMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARADepositBasketHandler.createDepositBaskets(new List<Id>{ deletedId });
        Test.stopTest();

        System.assertEquals(0, mock.capturedRequests.size());
    }


    @IsTest
    static void handlerIsNoOpOnNullOrEmptyList() {
        Test.startTest();
        CARADepositBasketHandler.createDepositBaskets(null);
        CARADepositBasketHandler.createDepositBaskets(new List<Id>());
        Test.stopTest();
        // No exception thrown, nothing enqueued — nothing further to assert.
    }


    private class DepositMock implements HttpCalloutMock {
        public Integer statusCode = 200;
        public String body = '{}';
        public List<HttpRequest> capturedRequests = new List<HttpRequest>();

        public HttpResponse respond(HttpRequest request) {
            capturedRequests.add(request);
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }
}
