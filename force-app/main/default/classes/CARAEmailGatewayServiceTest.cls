@IsTest
private class CARAEmailGatewayServiceTest {

    @TestSetup
    static void setupData() {
        insert new CARA_Marketing_Cloud_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Client_Id__c = 'test-client-id',
            Client_Secret__c = 'test-client-secret'
        );

        Account account = new Account(Name = 'Email Gateway Test Account');
        insert account;
        insert new Contact(
            AccountId = account.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'jane.doe@example.com'
        );
    }


    private static CARAEmailGatewayService.EmailGatewayRequest buildRequest(String email, Map<String, Object> data) {
        CARAEmailGatewayService.EmailGatewayRequest request = new CARAEmailGatewayService.EmailGatewayRequest();
        request.source = 'ServiceCloud';
        request.recipientEmail = email;
        request.data = data;
        return request;
    }


    @IsTest
    static void successfulSendResolvesContactAndUsesWrapperAttributeName() {
        EmailGatewayMock mock = new EmailGatewayMock();
        mock.statusCode = 200;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(
            'ORDER_CONFIRMATION',
            buildRequest('jane.doe@example.com', new Map<String, Object>{ 'firstName' => 'Jane', 'orderNumber' => 'ORD-1' })
        );
        Test.stopTest();

        Assert.areEqual(true, result.success);
        Assert.areEqual(1, mock.tokenRequests.size());
        Assert.areEqual(1, mock.emailRequests.size());

        Contact contactRecord = [SELECT Id FROM Contact WHERE Email = 'jane.doe@example.com' LIMIT 1];
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.emailRequests[0].getBody());
        Assert.areEqual('jane.doe@example.com', payload.get('to'));
        Assert.areEqual(contactRecord.Id, payload.get('individualId'));
        Map<String, Object> attributes = (Map<String, Object>) payload.get('attributes');
        Assert.isTrue(attributes.containsKey('OrderConfirmationInput'));
        Assert.isTrue(mock.emailRequests[0].getEndpoint().contains('sendDefinitionId=0XBa30001ztHgVcGAK'));
        Assert.areEqual('Bearer test-access-token', mock.emailRequests[0].getHeader('Authorization'));

        Email_Gateway_Log__c logRecord = [SELECT Success__c, Individual_Id__c FROM Email_Gateway_Log__c WITH SYSTEM_MODE LIMIT 1];
        Assert.areEqual(true, logRecord.Success__c);
        Assert.areEqual(contactRecord.Id, logRecord.Individual_Id__c);
    }


    @IsTest
    static void contentWrapperUsedForServiceCloudTemplates() {
        EmailGatewayMock mock = new EmailGatewayMock();
        mock.statusCode = 200;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAEmailGatewayService.sendEmail(
            'ORDER_CANCEL',
            buildRequest('jane.doe@example.com', new Map<String, Object>{ 'FirstName' => 'Jane', 'OrderNumber' => 'ORD-1' })
        );
        Test.stopTest();

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.emailRequests[0].getBody());
        Map<String, Object> attributes = (Map<String, Object>) payload.get('attributes');
        Assert.isTrue(attributes.containsKey('$content'));
    }


    /*
     * Confirmed against the live actions360 API: a request with no
     * resolvable individualId is rejected by Marketing Cloud itself
     * (HTTP 400, "'individualId' field is required") — so an unmatched
     * recipient must fail locally rather than attempt the callout.
     */
    @IsTest
    static void unknownRecipientIsRejectedAsRecipientNotFound() {
        EmailGatewayMock mock = new EmailGatewayMock();
        mock.statusCode = 200;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(
            'ORDER_CONFIRMATION',
            buildRequest('no-such-contact@example.com', new Map<String, Object>{ 'firstName' => 'Guest' })
        );
        Test.stopTest();

        Assert.areEqual(false, result.success);
        Assert.areEqual('RECIPIENT_NOT_FOUND', result.errorCode);
        Assert.areEqual(0, mock.tokenRequests.size() + mock.emailRequests.size(), 'No callout should fire without a resolvable individualId.');
    }


    @IsTest
    static void unsupportedEmailTypeNeverCallsOut() {
        EmailGatewayMock mock = new EmailGatewayMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(
            'NOT_A_REAL_TYPE',
            buildRequest('jane.doe@example.com', new Map<String, Object>{ 'x' => 'y' })
        );
        Test.stopTest();

        Assert.areEqual(false, result.success);
        Assert.areEqual('UNSUPPORTED_EMAIL_TYPE', result.errorCode);
        Assert.areEqual(0, mock.tokenRequests.size() + mock.emailRequests.size());
    }


    @IsTest
    static void missingRecipientNeverCallsOut() {
        EmailGatewayMock mock = new EmailGatewayMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(
            'ORDER_CONFIRMATION',
            buildRequest(null, new Map<String, Object>{ 'x' => 'y' })
        );
        Test.stopTest();

        Assert.areEqual(false, result.success);
        Assert.areEqual('RECIPIENT_REQUIRED', result.errorCode);
        Assert.areEqual(0, mock.tokenRequests.size() + mock.emailRequests.size());
    }


    @IsTest
    static void missingTemplateDataNeverCallsOut() {
        EmailGatewayMock mock = new EmailGatewayMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(
            'ORDER_CONFIRMATION',
            buildRequest('jane.doe@example.com', null)
        );
        Test.stopTest();

        Assert.areEqual(false, result.success);
        Assert.areEqual('DATA_REQUIRED', result.errorCode);
        Assert.areEqual(0, mock.tokenRequests.size() + mock.emailRequests.size());
    }


    @IsTest
    static void unconfiguredEmailTypeNeverCallsOut() {
        EmailGatewayMock mock = new EmailGatewayMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        // PASSWORD_RESET ships with Active__c = false (no confirmed Send Definition yet).
        CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(
            'PASSWORD_RESET',
            buildRequest('jane.doe@example.com', new Map<String, Object>{ 'resetUrl' => 'https://example.com/reset' })
        );
        Test.stopTest();

        Assert.areEqual(false, result.success);
        Assert.areEqual('EMAIL_TYPE_NOT_CONFIGURED', result.errorCode);
        Assert.areEqual(0, mock.tokenRequests.size() + mock.emailRequests.size());
    }


    @IsTest
    static void marketingCloudHttpFailureIsReportedAndLogged() {
        EmailGatewayMock mock = new EmailGatewayMock();
        mock.statusCode = 500;
        mock.body = '{"error":"internal"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(
            'ORDER_CONFIRMATION',
            buildRequest('jane.doe@example.com', new Map<String, Object>{ 'firstName' => 'Jane' })
        );
        Test.stopTest();

        Assert.areEqual(false, result.success);
        Assert.areEqual('MC_HTTP_500', result.errorCode);

        Email_Gateway_Log__c logRecord = [SELECT Success__c, HTTP_Status__c FROM Email_Gateway_Log__c WITH SYSTEM_MODE LIMIT 1];
        Assert.areEqual(false, logRecord.Success__c);
        Assert.areEqual(500, logRecord.HTTP_Status__c);
    }


    @IsTest
    static void calloutExceptionIsReportedAndLogged() {
        EmailGatewayMock mock = new EmailGatewayMock();
        mock.throwExceptionOnEmailCall = true;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(
            'ORDER_CONFIRMATION',
            buildRequest('jane.doe@example.com', new Map<String, Object>{ 'firstName' => 'Jane' })
        );
        Test.stopTest();

        Assert.areEqual(false, result.success);
        Assert.areEqual('MC_CALLOUT_FAILED', result.errorCode);

        Email_Gateway_Log__c logRecord = [SELECT Success__c FROM Email_Gateway_Log__c WITH SYSTEM_MODE LIMIT 1];
        Assert.areEqual(false, logRecord.Success__c);
    }


    @IsTest
    static void authFailureIsReportedWithoutLoggingSecrets() {
        delete [SELECT Id FROM CARA_Marketing_Cloud_Setting__c];

        EmailGatewayMock mock = new EmailGatewayMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(
            'ORDER_CONFIRMATION',
            buildRequest('jane.doe@example.com', new Map<String, Object>{ 'firstName' => 'Jane' })
        );
        Test.stopTest();

        Assert.areEqual(false, result.success);
        Assert.areEqual('MC_CALLOUT_FAILED', result.errorCode);
        Assert.areEqual(0, mock.emailRequests.size(), 'Without credentials, the email endpoint must never be called.');

        Email_Gateway_Log__c logRecord = [SELECT Error_Message__c FROM Email_Gateway_Log__c WITH SYSTEM_MODE LIMIT 1];
        Assert.isFalse(logRecord.Error_Message__c.contains('test-client-secret'));
    }


    @IsTest
    static void duplicateRequestIdIsNotResentOnceSuccessful() {
        EmailGatewayMock mock = new EmailGatewayMock();
        mock.statusCode = 200;
        Test.setMock(HttpCalloutMock.class, mock);

        CARAEmailGatewayService.EmailGatewayRequest request = buildRequest(
            'jane.doe@example.com', new Map<String, Object>{ 'firstName' => 'Jane' }
        );
        request.requestId = 'FIXED-REQUEST-ID';

        Test.startTest();
        CARAEmailGatewayService.EmailGatewayResult first = CARAEmailGatewayService.sendEmail('ORDER_CONFIRMATION', request);
        CARAEmailGatewayService.EmailGatewayResult second = CARAEmailGatewayService.sendEmail('ORDER_CONFIRMATION', request);
        Test.stopTest();

        Assert.areEqual(true, first.success);
        Assert.areEqual(true, second.success);
        Assert.areEqual(1, mock.emailRequests.size(), 'A repeat of the same business event must not call Marketing Cloud twice.');
        Assert.areEqual(1, [SELECT COUNT() FROM Email_Gateway_Log__c WITH SYSTEM_MODE]);
    }


    /*
     * Branches on endpoint so a single mock can stand in for both the
     * token endpoint (carajewellers.my.salesforce.com) and the Marketing
     * Cloud email endpoint (api.salesforce.com) — exactly the two calls
     * the Postman collection itself makes.
     */
    private class EmailGatewayMock implements HttpCalloutMock {
        public Integer statusCode = 200;
        public String body = '{}';
        public Boolean throwExceptionOnEmailCall = false;
        public List<HttpRequest> tokenRequests = new List<HttpRequest>();
        public List<HttpRequest> emailRequests = new List<HttpRequest>();

        public HttpResponse respond(HttpRequest request) {
            if (request.getEndpoint().contains('/services/oauth2/token')) {
                tokenRequests.add(request);
                HttpResponse tokenHttpResponse = new HttpResponse();
                tokenHttpResponse.setHeader('Content-Type', 'application/json');
                tokenHttpResponse.setStatusCode(200);
                tokenHttpResponse.setBody('{"access_token":"test-access-token"}');
                return tokenHttpResponse;
            }

            emailRequests.add(request);

            if (throwExceptionOnEmailCall) {
                throw new CalloutException('Simulated network failure');
            }

            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }
}