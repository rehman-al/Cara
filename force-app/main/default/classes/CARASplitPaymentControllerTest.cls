@IsTest
private class CARASplitPaymentControllerTest {

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        insert new SFSC_Order_Ops_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Order_Ops_Secret__c = 'test-secret-value'
        );
    }


    private class ControllerMock implements HttpCalloutMock {
        public List<HttpRequest> capturedRequests = new List<HttpRequest>();

        public HttpResponse respond(HttpRequest request) {
            capturedRequests.add(request);
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(200);

            if (request.getEndpoint().contains('sfsc-deposit-basket')) {
                response.setBody('{"basketId":"BASKET-1","link":"/pay/deposit?basketId=BASKET-1","deposit":250,"orderTotal":1000}');
            } else if (request.getEndpoint().contains('sfsc-delete-basket')) {
                response.setBody('{"success":true}');
            } else {
                response.setBody('{"link":"/pay/balance?orderNo=ORD-1","remaining":500,"paid":500,"alreadyPaid":false}');
            }

            return response;
        }
    }


    @IsTest
    static void requestDepositBasketDelegatesToHandler() {
        Account acc = new Account(Name = 'Controller Test Customer');
        insert acc;
        Contact contactRecord = new Contact(AccountId = acc.Id, LastName = 'Doe', Email = 'shopper@example.com');
        insert contactRecord;
        Case caseRecord = new Case(ContactId = contactRecord.Id, Subject = 'Custom Piece Request');
        insert caseRecord;
        Custom_Product_Request__c requestRecord = new Custom_Product_Request__c(
            Case__c = caseRecord.Id,
            Product_Name__c = 'Custom Ring',
            Quantity__c = 1,
            Selling_Price__c = 1000,
            Status__c = 'Approved'
        );
        insert requestRecord;

        ControllerMock mock = new ControllerMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASplitPaymentController.requestDepositBasket(requestRecord.Id);
        Test.stopTest();

        Custom_Product_Request__c result = [SELECT Basket_Status__c FROM Custom_Product_Request__c WHERE Id = :requestRecord.Id];
        System.assertEquals('Error', result.Basket_Status__c, 'No Product__c is set, so SKU is missing and this must fail safely, not throw.');
    }


    @IsTest
    static void requestDepositBasketWithNullIdThrows() {
        Boolean threw = false;

        Test.startTest();
        try {
            CARASplitPaymentController.requestDepositBasket(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'A null Id must throw an AuraHandledException.');
    }


    /*
     * Covers the shared handled() wrapper directly rather than trying to
     * force a real unexpected exception through the public API (e.g. by
     * exhausting the queueable-job governor limit) — that approach makes
     * System.LimitException itself, which the try/catch in the caller
     * cannot always intercept cleanly in a test context.
     */
    @IsTest
    static void handledWrapsExceptionWithContextMessage() {
        AuraHandledException result = CARASplitPaymentController.handled(
            'Unable to do the thing.', new System.CalloutException('boom')
        );

        System.assertNotEquals(null, result);
        System.assert(result.getMessage().contains('Unable to do the thing.'));
        System.assert(result.getMessage().contains('CalloutException'));
    }


    @IsTest
    static void cancelDepositBasketDelegatesToHandler() {
        Account acc = new Account(Name = 'Controller Cancel Test Customer');
        insert acc;
        Contact contactRecord = new Contact(AccountId = acc.Id, LastName = 'Doe', Email = 'shopper@example.com');
        insert contactRecord;
        Case caseRecord = new Case(ContactId = contactRecord.Id, Subject = 'Custom Piece Request');
        insert caseRecord;
        Custom_Product_Request__c requestRecord = new Custom_Product_Request__c(
            Case__c = caseRecord.Id,
            Product_Name__c = 'Custom Ring',
            Quantity__c = 1,
            Selling_Price__c = 1000,
            Basket_Id__c = 'BASKET-1',
            Basket_Status__c = 'Created'
        );
        insert requestRecord;

        ControllerMock mock = new ControllerMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASplitPaymentController.cancelDepositBasket(requestRecord.Id, 'Customer changed mind');
        Test.stopTest();

        Custom_Product_Request__c result = [SELECT Basket_Status__c FROM Custom_Product_Request__c WHERE Id = :requestRecord.Id];
        System.assertEquals('Deleted', result.Basket_Status__c);
    }


    @IsTest
    static void cancelDepositBasketWithNullIdThrows() {
        Boolean threw = false;

        Test.startTest();
        try {
            CARASplitPaymentController.cancelDepositBasket(null, 'reason');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw);
    }


    @IsTest
    static void requestBalanceLinkDelegatesToHandler() {
        Account acc = new Account(Name = 'Controller Balance Test Customer');
        insert acc;
        Contact contactRecord = new Contact(AccountId = acc.Id, FirstName = 'Jane', LastName = 'Doe', Email = 'shopper@example.com');
        insert contactRecord;
        Order orderRecord = new Order(
            AccountId = acc.Id,
            Status = 'On Hold',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            OrderReferenceNumber = 'ORD-1',
            Contact__c = contactRecord.Id
        );
        insert orderRecord;

        ControllerMock mock = new ControllerMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASplitPaymentController.requestBalanceLink(orderRecord.Id);
        Test.stopTest();

        Order result = [SELECT Balance_Link_Status__c FROM Order WHERE Id = :orderRecord.Id];
        System.assertEquals('Sent', result.Balance_Link_Status__c);
    }


    @IsTest
    static void requestBalanceLinkWithNullIdThrows() {
        Boolean threw = false;

        Test.startTest();
        try {
            CARASplitPaymentController.requestBalanceLink(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw);
    }


}