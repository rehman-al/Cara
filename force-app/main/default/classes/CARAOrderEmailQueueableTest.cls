@IsTest
private class CARAOrderEmailQueueableTest {

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        insert new CARA_Marketing_Cloud_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Client_Id__c = 'test-client-id',
            Client_Secret__c = 'test-client-secret'
        );

        Account account = new Account(Name = 'Order Email Queueable Test Account');
        insert account;
        Contact contactRecord = new Contact(
            AccountId = account.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'queueable@example.com'
        );
        insert contactRecord;

        Order orderRecord = new Order(
            AccountId = account.Id,
            Contact__c = contactRecord.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = standardPricebookId,
            OrderReferenceNumber = 'ORD-QUEUE-1',
            Customer_Name_Plain__c = 'Jane Doe'
        );
        insert orderRecord;

        // Transitioning into any Activated-category status (Invoiced/
        // Delivered included) requires at least one OrderItem — standard
        // platform order-activation validation, not specific to this code.
        Product2 productRecord = new Product2(Name = 'Queueable Test Product', IsActive = true);
        insert productRecord;
        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert entry;
        insert new OrderItem(
            OrderId = orderRecord.Id,
            Product2Id = productRecord.Id,
            PricebookEntryId = entry.Id,
            Quantity = 1,
            UnitPrice = 100
        );
    }


    @IsTest
    static void resolveEmailTypeMapsInvoicedAndDelivered() {
        Assert.areEqual('ORDER_INVOICE', CARAOrderEmailQueueable.resolveEmailType('Invoiced'));
        Assert.areEqual('ORDER_DELIVERY', CARAOrderEmailQueueable.resolveEmailType('Delivered'));
        Assert.areEqual(null, CARAOrderEmailQueueable.resolveEmailType('Draft'));
        Assert.areEqual(null, CARAOrderEmailQueueable.resolveEmailType(null));
    }


    @IsTest
    static void invoicedOrderSendsOrderInvoiceEmail() {
        Order orderRecord = [SELECT Id FROM Order LIMIT 1];
        update new Order(Id = orderRecord.Id, Status = 'Invoiced');

        TokenAndEmailMock mock = new TokenAndEmailMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new CARAOrderEmailQueueable(new List<Id>{ orderRecord.Id }).execute(null);
        Test.stopTest();

        Email_Gateway_Log__c logRecord = [SELECT Email_Type__c, Success__c FROM Email_Gateway_Log__c WITH SYSTEM_MODE LIMIT 1];
        Assert.areEqual('ORDER_INVOICE', logRecord.Email_Type__c);
        Assert.areEqual(true, logRecord.Success__c);
    }


    @IsTest
    static void deliveredOrderSendsOrderDeliveryEmail() {
        Order orderRecord = [SELECT Id FROM Order LIMIT 1];
        update new Order(Id = orderRecord.Id, Status = 'Delivered');

        TokenAndEmailMock mock = new TokenAndEmailMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new CARAOrderEmailQueueable(new List<Id>{ orderRecord.Id }).execute(null);
        Test.stopTest();

        Email_Gateway_Log__c logRecord = [SELECT Email_Type__c FROM Email_Gateway_Log__c WITH SYSTEM_MODE LIMIT 1];
        Assert.areEqual('ORDER_DELIVERY', logRecord.Email_Type__c);
    }


    @IsTest
    static void unrelatedStatusDoesNotSendAnyEmail() {
        Order orderRecord = [SELECT Id FROM Order LIMIT 1];

        TokenAndEmailMock mock = new TokenAndEmailMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new CARAOrderEmailQueueable(new List<Id>{ orderRecord.Id }).execute(null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Email_Gateway_Log__c WITH SYSTEM_MODE]);
    }


    @IsTest
    static void unknownOrderIdIsIgnoredSafely() {
        TokenAndEmailMock mock = new TokenAndEmailMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Order orderRecord = [SELECT Id FROM Order LIMIT 1];
        delete orderRecord;

        Test.startTest();
        new CARAOrderEmailQueueable(new List<Id>{ orderRecord.Id }).execute(null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Email_Gateway_Log__c WITH SYSTEM_MODE]);
    }


    @IsTest
    static void invocableHandlerEnqueuesJobThatSendsEmail() {
        Order orderRecord = [SELECT Id FROM Order LIMIT 1];
        update new Order(Id = orderRecord.Id, Status = 'Invoiced');

        TokenAndEmailMock mock = new TokenAndEmailMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAOrderEmailStatusHandler.sendOrderStatusEmail(new List<Id>{ orderRecord.Id });
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Email_Gateway_Log__c WITH SYSTEM_MODE]);
    }


    private class TokenAndEmailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            if (request.getEndpoint().contains('/services/oauth2/token')) {
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