@IsTest
private class CARADeleteBasketQueueableTest {

    @TestSetup
    static void setupData() {
        insert new SFSC_Order_Ops_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Order_Ops_Secret__c = 'test-secret-value'
        );
    }


    private static Custom_Product_Request__c buildRequest(String basketId, String basketStatus) {
        Account acc = new Account(Name = 'Delete Basket Test Customer');
        insert acc;

        Contact contactRecord = new Contact(
            AccountId = acc.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'shopper@example.com'
        );
        insert contactRecord;

        Case caseRecord = new Case(ContactId = contactRecord.Id, Subject = 'Custom Piece Request');
        insert caseRecord;

        Custom_Product_Request__c requestRecord = new Custom_Product_Request__c(
            Case__c = caseRecord.Id,
            Product_Name__c = 'Custom Ring',
            Quantity__c = 1,
            Selling_Price__c = 1000,
            Status__c = 'Approved',
            Basket_Id__c = basketId,
            Basket_Status__c = basketStatus
        );
        insert requestRecord;
        return requestRecord;
    }


    private static void cancel(Id requestId, String reason) {
        CARADeleteBasketHandler.CancelRequest cancelRequest = new CARADeleteBasketHandler.CancelRequest();
        cancelRequest.customProductRequestId = requestId;
        cancelRequest.reason = reason;
        CARADeleteBasketHandler.cancelDepositBaskets(new List<CARADeleteBasketHandler.CancelRequest>{ cancelRequest });
    }


    private static Custom_Product_Request__c queryRequest(Id requestId) {
        return [SELECT Basket_Id__c, Basket_Status__c, Basket_Log__c FROM Custom_Product_Request__c WHERE Id = :requestId];
    }


    @IsTest
    static void noBasketYetIsIdempotentNoOp() {
        Custom_Product_Request__c requestRecord = buildRequest(null, 'Not Started');

        DeleteMock mock = new DeleteMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        cancel(requestRecord.Id, 'Customer changed mind');
        Test.stopTest();

        System.assertEquals(0, mock.capturedRequests.size(), 'No basket exists — must not call SFCC/MRT.');
        Custom_Product_Request__c result = queryRequest(requestRecord.Id);
        System.assertEquals('Deleted', result.Basket_Status__c);
        System.assert(result.Basket_Log__c.contains('no live basket to delete'));
    }


    @IsTest
    static void existingBasketIsDeletedSuccessfully() {
        Custom_Product_Request__c requestRecord = buildRequest('BASKET-1', 'Created');

        DeleteMock mock = new DeleteMock();
        mock.statusCode = 200;
        mock.body = '{"success":true}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        cancel(requestRecord.Id, 'Customer changed mind');
        Test.stopTest();

        System.assertEquals(1, mock.capturedRequests.size());
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedRequests[0].getBody());
        System.assertEquals('BASKET-1', payload.get('basketId'));
        System.assertEquals('shopper@example.com', payload.get('customerLogin'));

        Custom_Product_Request__c result = queryRequest(requestRecord.Id);
        System.assertEquals('Deleted', result.Basket_Status__c);
        System.assert(result.Basket_Log__c.contains('Basket deleted'));
    }


    @IsTest
    static void alreadyGoneBasketIsTreatedAsDeleted() {
        Custom_Product_Request__c requestRecord = buildRequest('BASKET-1', 'Created');

        DeleteMock mock = new DeleteMock();
        mock.statusCode = 200;
        mock.body = '{"alreadyGone":true}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        cancel(requestRecord.Id, 'Customer changed mind');
        Test.stopTest();

        Custom_Product_Request__c result = queryRequest(requestRecord.Id);
        System.assertEquals('Deleted', result.Basket_Status__c);
        System.assert(result.Basket_Log__c.contains('already gone'));
    }


    @IsTest
    static void alreadyDeletedIsIdempotentNoOp() {
        Custom_Product_Request__c requestRecord = buildRequest('BASKET-1', 'Deleted');

        DeleteMock mock = new DeleteMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        cancel(requestRecord.Id, 'Second cancel attempt');
        Test.stopTest();

        System.assertEquals(0, mock.capturedRequests.size(), 'An already-deleted basket must not be re-deleted.');
    }


    @IsTest
    static void deleteFailureLeavesBasketStatusUnchangedAndLogsError() {
        Custom_Product_Request__c requestRecord = buildRequest('BASKET-1', 'Created');

        DeleteMock mock = new DeleteMock();
        mock.statusCode = 401;
        mock.body = '{"error":"secret mismatch"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        cancel(requestRecord.Id, 'Customer changed mind');
        Test.stopTest();

        Custom_Product_Request__c result = queryRequest(requestRecord.Id);
        System.assertEquals('Created', result.Basket_Status__c, 'A failed delete must not be marked Deleted.');
        System.assert(result.Basket_Log__c.contains(CARASfscSplitPaymentService.ERROR_AUTH));
    }


    @IsTest
    static void missingRecordIsHandledSafelyWithoutException() {
        Custom_Product_Request__c requestRecord = buildRequest('BASKET-1', 'Created');
        Id deletedId = requestRecord.Id;
        delete requestRecord;

        DeleteMock mock = new DeleteMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        cancel(deletedId, 'Customer changed mind');
        Test.stopTest();

        System.assertEquals(0, mock.capturedRequests.size());
    }


    @IsTest
    static void handlerIsNoOpOnNullOrEmptyList() {
        Test.startTest();
        CARADeleteBasketHandler.cancelDepositBaskets(null);
        CARADeleteBasketHandler.cancelDepositBaskets(new List<CARADeleteBasketHandler.CancelRequest>());
        Test.stopTest();
    }


    private class DeleteMock implements HttpCalloutMock {
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