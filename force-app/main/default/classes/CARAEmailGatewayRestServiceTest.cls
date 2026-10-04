@IsTest
private class CARAEmailGatewayRestServiceTest {

    @TestSetup
    static void setupData() {
        insert new CARA_Marketing_Cloud_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Client_Id__c = 'test-client-id',
            Client_Secret__c = 'test-client-secret'
        );

        // Marketing Cloud requires a resolvable individualId on every send —
        // confirmed against the live actions360 API — so the success-path
        // tests below need a matching Contact for customer@example.com.
        Account account = new Account(Name = 'Email Gateway REST Test Account');
        insert account;
        insert new Contact(
            AccountId = account.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'customer@example.com'
        );
    }


    private static void setRequest(Map<String, Object> payload) {
        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/email/send';
        requestRecord.httpMethod = 'POST';
        requestRecord.requestBody = payload == null ? null : Blob.valueOf(JSON.serialize(payload));

        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
    }


    private static Map<String, Object> responseBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }


    @IsTest
    static void validOrderConfirmationIsAccepted() {
        RestMock mock = new RestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        setRequest(new Map<String, Object>{
            'emailType' => 'ORDER_CONFIRMATION',
            'recipient' => new Map<String, Object>{ 'email' => 'customer@example.com' },
            'data' => new Map<String, Object>{ 'firstName' => 'Jane', 'orderNumber' => 'ORD-1' }
        });

        Test.startTest();
        CARAEmailGatewayRestService.sendEmail();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> body = responseBody();
        Assert.areEqual(true, body.get('success'));
        Assert.areEqual('ORDER_CONFIRMATION', body.get('emailType'));
        Assert.isTrue(String.isNotBlank((String) body.get('requestId')));
    }


    @IsTest
    static void validDepositConfirmationIsAccepted() {
        RestMock mock = new RestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        setRequest(new Map<String, Object>{
            'emailType' => 'DEPOSIT_CONFIRMATION',
            'recipient' => new Map<String, Object>{ 'email' => 'customer@example.com' },
            'data' => new Map<String, Object>{ 'FirstName' => 'Jane', 'orderNumber' => 'MM-1' }
        });

        Test.startTest();
        CARAEmailGatewayRestService.sendEmail();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Assert.areEqual(true, responseBody().get('success'));
    }


    @IsTest
    static void passwordResetIsRejectedWhileUnconfigured() {
        RestMock mock = new RestMock();
        Test.setMock(HttpCalloutMock.class, mock);

        setRequest(new Map<String, Object>{
            'emailType' => 'PASSWORD_RESET',
            'recipient' => new Map<String, Object>{ 'email' => 'customer@example.com' },
            'data' => new Map<String, Object>{ 'resetUrl' => 'https://example.com/reset' }
        });

        Test.startTest();
        CARAEmailGatewayRestService.sendEmail();
        Test.stopTest();

        // Request shape is valid and accepted by this endpoint; the gateway
        // itself reports the unconfigured Send Definition as a 400.
        Assert.areEqual(400, RestContext.response.statusCode);
        Map<String, Object> body = responseBody();
        Assert.areEqual(false, body.get('success'));
        Assert.areEqual('EMAIL_TYPE_NOT_CONFIGURED', body.get('errorCode'));
    }


    @IsTest
    static void serviceCloudOnlyEmailTypeIsRejectedByThisEndpoint() {
        setRequest(new Map<String, Object>{
            'emailType' => 'ORDER_CANCEL',
            'recipient' => new Map<String, Object>{ 'email' => 'customer@example.com' },
            'data' => new Map<String, Object>{ 'FirstName' => 'Jane' }
        });

        Test.startTest();
        CARAEmailGatewayRestService.sendEmail();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual('INVALID_REQUEST', responseBody().get('errorCode'));
    }


    @IsTest
    static void missingEmailTypeIsRejected() {
        setRequest(new Map<String, Object>{
            'recipient' => new Map<String, Object>{ 'email' => 'customer@example.com' },
            'data' => new Map<String, Object>{ 'firstName' => 'Jane' }
        });

        Test.startTest();
        CARAEmailGatewayRestService.sendEmail();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual('INVALID_REQUEST', responseBody().get('errorCode'));
    }


    @IsTest
    static void missingRecipientEmailIsRejected() {
        setRequest(new Map<String, Object>{
            'emailType' => 'ORDER_CONFIRMATION',
            'recipient' => new Map<String, Object>{ 'externalId' => 'SFCC-123' },
            'data' => new Map<String, Object>{ 'firstName' => 'Jane' }
        });

        Test.startTest();
        CARAEmailGatewayRestService.sendEmail();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual('INVALID_REQUEST', responseBody().get('errorCode'));
    }


    @IsTest
    static void missingDataIsRejected() {
        setRequest(new Map<String, Object>{
            'emailType' => 'ORDER_CONFIRMATION',
            'recipient' => new Map<String, Object>{ 'email' => 'customer@example.com' }
        });

        Test.startTest();
        CARAEmailGatewayRestService.sendEmail();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual('INVALID_REQUEST', responseBody().get('errorCode'));
    }


    @IsTest
    static void blankBodyIsRejected() {
        setRequest(null);

        Test.startTest();
        CARAEmailGatewayRestService.sendEmail();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.areEqual('INVALID_REQUEST', responseBody().get('errorCode'));
    }


    @IsTest
    static void marketingCloudFailureSurfacesAsControlledFailureResponse() {
        RestMock mock = new RestMock();
        mock.emailStatusCode = 500;
        Test.setMock(HttpCalloutMock.class, mock);

        setRequest(new Map<String, Object>{
            'emailType' => 'ORDER_CONFIRMATION',
            'recipient' => new Map<String, Object>{ 'email' => 'customer@example.com' },
            'data' => new Map<String, Object>{ 'firstName' => 'Jane' }
        });

        Test.startTest();
        CARAEmailGatewayRestService.sendEmail();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Map<String, Object> body = responseBody();
        Assert.areEqual(false, body.get('success'));
        Assert.areEqual('MC_HTTP_500', body.get('errorCode'));
        Assert.isFalse(body.containsKey('emailType'), 'Failure responses omit emailType per the Phase-11 contract.');
    }


    private class RestMock implements HttpCalloutMock {
        public Integer emailStatusCode = 200;

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (request.getEndpoint().contains('/services/oauth2/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"test-access-token"}');
            } else {
                response.setStatusCode(emailStatusCode);
                response.setBody('{}');
            }
            return response;
        }
    }
}