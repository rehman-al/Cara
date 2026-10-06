@IsTest
private class CARASfscSplitPaymentServiceTest {

    @TestSetup
    static void setupData() {
        insert new SFSC_Order_Ops_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Order_Ops_Secret__c = 'test-secret-value'
        );
    }


    private static CARASfscSplitPaymentService.DepositBasketRequest buildDepositRequest() {
        CARASfscSplitPaymentService.ShippingAddress address = new CARASfscSplitPaymentService.ShippingAddress();
        address.firstName = 'Jane';
        address.lastName = 'Doe';
        address.address1 = '123 Main St';
        address.city = 'Dubai';
        address.postalCode = '00000';
        address.countryCode = 'AE';
        address.phone = '+971500000000';

        CARASfscSplitPaymentService.DepositBasketRequest requestData = new CARASfscSplitPaymentService.DepositBasketRequest();
        requestData.customerLogin = 'shopper@example.com';
        requestData.sku = 'SKU_ID';
        requestData.price = 1000;
        requestData.deposit = 250;
        requestData.shippingAddress = address;
        requestData.cprNumber = 'CPR-00042';
        return requestData;
    }


    // =========================================================
    // Create Deposit Basket
    // =========================================================
    @IsTest
    static void createDepositBasketSuccessParsesResponse() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 200;
        mock.body = '{"basketId":"BASKET-1","link":"/pay/deposit?basketId=BASKET-1","deposit":250,"orderTotal":1000}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DepositBasketResult result =
            CARASfscSplitPaymentService.createDepositBasket(buildDepositRequest());
        Test.stopTest();

        System.assert(result.success);
        System.assertEquals('BASKET-1', result.basketId);
        System.assertEquals('/pay/deposit?basketId=BASKET-1', result.link);
        System.assertEquals(250, result.deposit);
        System.assertEquals(1000, result.orderTotal);
        System.assertEquals(1, mock.capturedRequests.size());

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedRequests[0].getBody());
        System.assertEquals('shopper@example.com', payload.get('customerLogin'));
        System.assertEquals('SKU_ID', payload.get('sku'));
        System.assertEquals('CPR-00042', payload.get('cprNumber'));
        Map<String, Object> shippingAddress = (Map<String, Object>) payload.get('shippingAddress');
        System.assertEquals('AE', shippingAddress.get('countryCode'));
        System.assertEquals('test-secret-value', mock.capturedRequests[0].getHeader('X-SFSC-Order-Secret'));
        System.assertEquals('POST', mock.capturedRequests[0].getMethod());
    }


    @IsTest
    static void createDepositBasket400IsPayloadErrorAndNeverRetried() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 400;
        mock.body = '{"error":"missing sku"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DepositBasketResult result =
            CARASfscSplitPaymentService.createDepositBasket(buildDepositRequest());
        Test.stopTest();

        System.assert(!result.success);
        System.assertEquals(CARASfscSplitPaymentService.ERROR_PAYLOAD, result.errorCategory);
        System.assertEquals(1, mock.capturedRequests.size(), '400 must never be retried.');
    }


    @IsTest
    static void createDepositBasket401IsAuthErrorAndNeverRetried() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 401;
        mock.body = '{"error":"secret mismatch"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DepositBasketResult result =
            CARASfscSplitPaymentService.createDepositBasket(buildDepositRequest());
        Test.stopTest();

        System.assert(!result.success);
        System.assertEquals(CARASfscSplitPaymentService.ERROR_AUTH, result.errorCategory);
        System.assertEquals(1, mock.capturedRequests.size(), '401 must never be retried.');
    }


    @IsTest
    static void createDepositBasket502RetriesOnceThenSucceeds() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 502;
        mock.body = '{"error":"gateway timeout"}';
        mock.succeedOnAttempt = 2;
        mock.successBody = '{"basketId":"BASKET-RETRY","link":"/pay/deposit?basketId=BASKET-RETRY","deposit":250,"orderTotal":1000}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DepositBasketResult result =
            CARASfscSplitPaymentService.createDepositBasket(buildDepositRequest());
        Test.stopTest();

        System.assert(result.success, 'Second attempt should succeed after one retry.');
        System.assertEquals('BASKET-RETRY', result.basketId);
        System.assertEquals(2, mock.capturedRequests.size(), 'Exactly one retry (two total attempts) is expected.');
    }


    @IsTest
    static void createDepositBasket502StillFailingAfterRetryIsSurfacedAsGatewayError() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 502;
        mock.body = '{"error":"gateway timeout"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DepositBasketResult result =
            CARASfscSplitPaymentService.createDepositBasket(buildDepositRequest());
        Test.stopTest();

        System.assert(!result.success);
        System.assertEquals(CARASfscSplitPaymentService.ERROR_GATEWAY, result.errorCategory);
        System.assertEquals(2, mock.capturedRequests.size(), 'Two total attempts (one retry) before surfacing.');
    }


    @IsTest
    static void createDepositBasketNetworkExceptionIsRetriedThenSurfaced() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.throwException = true;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DepositBasketResult result =
            CARASfscSplitPaymentService.createDepositBasket(buildDepositRequest());
        Test.stopTest();

        System.assert(!result.success);
        System.assertEquals(CARASfscSplitPaymentService.ERROR_GATEWAY, result.errorCategory);
        System.assertEquals(2, mock.attemptCount, 'A network exception must be retried once before surfacing.');
    }


    @IsTest
    static void createDepositBasketUnparseableSuccessBodyIsPayloadError() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 200;
        mock.body = 'not-json';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DepositBasketResult result =
            CARASfscSplitPaymentService.createDepositBasket(buildDepositRequest());
        Test.stopTest();

        System.assert(!result.success);
        System.assertEquals(CARASfscSplitPaymentService.ERROR_PAYLOAD, result.errorCategory);
    }


    // =========================================================
    // Delete Basket
    // =========================================================
    @IsTest
    static void deleteBasketSuccess() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 200;
        mock.body = '{"success":true}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DeleteBasketResult result =
            CARASfscSplitPaymentService.deleteBasket('BASKET-1', 'shopper@example.com');
        Test.stopTest();

        System.assert(result.success);
        System.assert(!result.alreadyGone);
    }


    @IsTest
    static void deleteBasketAlreadyGoneIsTreatedAsSuccess() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 200;
        mock.body = '{"alreadyGone":true}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DeleteBasketResult result =
            CARASfscSplitPaymentService.deleteBasket('BASKET-1', 'shopper@example.com');
        Test.stopTest();

        System.assert(result.success);
        System.assert(result.alreadyGone);
    }


    @IsTest
    static void deleteBasket404IsTreatedAsIdempotentSuccess() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 404;
        mock.body = '{"error":"not found"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DeleteBasketResult result =
            CARASfscSplitPaymentService.deleteBasket('BASKET-1', 'shopper@example.com');
        Test.stopTest();

        System.assert(result.success);
    }


    @IsTest
    static void deleteBasket401IsAuthError() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 401;
        mock.body = '{"error":"secret mismatch"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.DeleteBasketResult result =
            CARASfscSplitPaymentService.deleteBasket('BASKET-1', 'shopper@example.com');
        Test.stopTest();

        System.assert(!result.success);
        System.assertEquals(CARASfscSplitPaymentService.ERROR_AUTH, result.errorCategory);
    }


    // =========================================================
    // Balance Link
    // =========================================================
    @IsTest
    static void getBalanceLinkSuccessNotAlreadyPaid() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 200;
        mock.body = '{"link":"/pay/balance?orderNo=ORD-1","remaining":500,"paid":500,"alreadyPaid":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.BalanceLinkResult result =
            CARASfscSplitPaymentService.getBalanceLink('ORD-1', 'shopper@example.com');
        Test.stopTest();

        System.assert(result.success);
        System.assertEquals('/pay/balance?orderNo=ORD-1', result.link);
        System.assertEquals(500, result.remaining);
        System.assertEquals(500, result.paid);
        System.assert(!result.alreadyPaid);

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedRequests[0].getBody());
        System.assertEquals('ORD-1', payload.get('orderNo'));
        System.assertEquals('shopper@example.com', payload.get('customerLogin'));
    }


    @IsTest
    static void getBalanceLinkAlreadyPaid() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 200;
        mock.body = '{"link":"/pay/balance?orderNo=ORD-1","remaining":0,"paid":1000,"alreadyPaid":true}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.BalanceLinkResult result =
            CARASfscSplitPaymentService.getBalanceLink('ORD-1', 'shopper@example.com');
        Test.stopTest();

        System.assert(result.success);
        System.assert(result.alreadyPaid);
    }


    @IsTest
    static void getBalanceLink400IsPayloadError() {
        SplitPaymentMock mock = new SplitPaymentMock();
        mock.statusCode = 400;
        mock.body = '{"error":"missing orderNo"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARASfscSplitPaymentService.BalanceLinkResult result =
            CARASfscSplitPaymentService.getBalanceLink('ORD-1', 'shopper@example.com');
        Test.stopTest();

        System.assert(!result.success);
        System.assertEquals(CARASfscSplitPaymentService.ERROR_PAYLOAD, result.errorCategory);
    }


    // =========================================================
    // Shared mock — captures every request; can force a status code,
    // a thrown exception, or a delayed success after N attempts.
    // =========================================================
    private class SplitPaymentMock implements HttpCalloutMock {
        public Integer statusCode = 200;
        public String body = '{}';
        public Boolean throwException = false;
        public Integer succeedOnAttempt = 0;
        public String successBody = '{}';
        public Integer attemptCount = 0;
        public List<HttpRequest> capturedRequests = new List<HttpRequest>();

        public HttpResponse respond(HttpRequest request) {
            attemptCount++;
            capturedRequests.add(request);

            if (throwException && (succeedOnAttempt == 0 || attemptCount < succeedOnAttempt)) {
                throw new CalloutException('Simulated network failure');
            }

            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (succeedOnAttempt > 0 && attemptCount >= succeedOnAttempt) {
                response.setStatusCode(200);
                response.setBody(successBody);
            } else {
                response.setStatusCode(statusCode);
                response.setBody(body);
            }

            return response;
        }
    }
}