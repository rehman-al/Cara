@IsTest
private class CARABalanceLinkQueueableTest {

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        insert new SFSC_Order_Ops_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Order_Ops_Secret__c = 'test-secret-value'
        );
    }


    private static Order buildOrder(String orderNo, String customerEmail) {
        Account acc = new Account(Name = 'Balance Link Test Customer');
        insert acc;

        // Customer_Email__c / Customer_Name__c are formulas off Contact__c
        // (Contact__r.Email / FirstName & LastName) — not directly writeable.
        Id contactId;
        if (customerEmail != null) {
            Contact contactRecord = new Contact(AccountId = acc.Id, FirstName = 'Jane', LastName = 'Doe', Email = customerEmail);
            insert contactRecord;
            contactId = contactRecord.Id;
        }

        Order orderRecord = new Order(
            AccountId = acc.Id,
            Status = 'On Hold',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            OrderReferenceNumber = orderNo,
            Storefront_Site_ID__c = 'CARA_AE',
            Contact__c = contactId
        );
        insert orderRecord;
        return orderRecord;
    }


    private static Order queryOrder(Id orderId) {
        return [
            SELECT Balance_Link__c, Balance_Remaining__c, Balance_Already_Paid__c, Balance_Link_Status__c, Balance_Link_Log__c
            FROM Order
            WHERE Id = :orderId
        ];
    }


    @IsTest
    static void happyPathSavesLinkAndNotifiesWhenNotAlreadyPaid() {
        Order orderRecord = buildOrder('ORD-1', 'shopper@example.com');

        BalanceMock mock = new BalanceMock();
        mock.statusCode = 200;
        mock.body = '{"link":"/pay/balance?orderNo=ORD-1","remaining":500,"paid":500,"alreadyPaid":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARABalanceLinkHandler.sendBalanceLinks(new List<Id>{ orderRecord.Id });
        Test.stopTest();

        Order result = queryOrder(orderRecord.Id);
        System.assertEquals('/pay/balance?orderNo=ORD-1', result.Balance_Link__c);
        System.assertEquals(500, result.Balance_Remaining__c);
        System.assert(!result.Balance_Already_Paid__c);
        System.assertEquals('Sent', result.Balance_Link_Status__c);
        System.assert(result.Balance_Link_Log__c.contains('notification: Sent to shopper@example.com'));

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedRequests[0].getBody());
        System.assertEquals('ORD-1', payload.get('orderNo'));
        System.assertEquals('shopper@example.com', payload.get('customerLogin'));
    }


    @IsTest
    static void alreadyPaidSkipsNotification() {
        Order orderRecord = buildOrder('ORD-2', 'shopper@example.com');

        BalanceMock mock = new BalanceMock();
        mock.statusCode = 200;
        mock.body = '{"link":"/pay/balance?orderNo=ORD-2","remaining":0,"paid":1000,"alreadyPaid":true}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARABalanceLinkHandler.sendBalanceLinks(new List<Id>{ orderRecord.Id });
        Test.stopTest();

        Order result = queryOrder(orderRecord.Id);
        System.assert(result.Balance_Already_Paid__c);
        System.assertEquals('Already Paid', result.Balance_Link_Status__c);
        System.assert(!result.Balance_Link_Log__c.contains('notification'), 'No notification should be sent when alreadyPaid is true.');
    }


    @IsTest
    static void missingCustomerEmailBlocksCalloutAndMarksError() {
        Order orderRecord = buildOrder('ORD-3', null);

        BalanceMock mock = new BalanceMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARABalanceLinkHandler.sendBalanceLinks(new List<Id>{ orderRecord.Id });
        Test.stopTest();

        System.assertEquals(0, mock.capturedRequests.size());
        Order result = queryOrder(orderRecord.Id);
        System.assertEquals('Error', result.Balance_Link_Status__c);
        System.assert(result.Balance_Link_Log__c.contains(CARASfscSplitPaymentService.ERROR_PAYLOAD));
    }


    @IsTest
    static void gatewayErrorAfterRetryMarksErrorStatus() {
        Order orderRecord = buildOrder('ORD-4', 'shopper@example.com');

        BalanceMock mock = new BalanceMock();
        mock.statusCode = 502;
        mock.body = '{"error":"timeout"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARABalanceLinkHandler.sendBalanceLinks(new List<Id>{ orderRecord.Id });
        Test.stopTest();

        Order result = queryOrder(orderRecord.Id);
        System.assertEquals('Error', result.Balance_Link_Status__c);
        System.assert(result.Balance_Link_Log__c.contains(CARASfscSplitPaymentService.ERROR_GATEWAY));
        System.assertEquals(2, mock.capturedRequests.size(), 'A 502 gets exactly one retry.');
    }


    @IsTest
    static void handlerIsNoOpOnNullOrEmptyList() {
        Test.startTest();
        CARABalanceLinkHandler.sendBalanceLinks(null);
        CARABalanceLinkHandler.sendBalanceLinks(new List<Id>());
        Test.stopTest();
    }


    private class BalanceMock implements HttpCalloutMock {
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