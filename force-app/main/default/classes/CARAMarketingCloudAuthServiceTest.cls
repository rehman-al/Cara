@IsTest
private class CARAMarketingCloudAuthServiceTest {

    @IsTest
    static void missingCredentialsThrowsWithoutAnyCallout() {
        TokenMock mock = new TokenMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            CARAMarketingCloudAuthService.getAccessToken();
            Assert.fail('Expected an AuthException when no credentials are configured.');
        } catch (CARAMarketingCloudAuthService.AuthException expectedError) {
            Assert.isTrue(expectedError.getMessage().contains('not configured'));
        }
        Test.stopTest();

        Assert.areEqual(0, mock.capturedRequests.size(), 'No callout should fire when credentials are missing.');
    }


    @IsTest
    static void successfulTokenRequestReturnsAccessToken() {
        insert new CARA_Marketing_Cloud_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Client_Id__c = 'test-client-id',
            Client_Secret__c = 'test-client-secret'
        );

        TokenMock mock = new TokenMock();
        mock.body = '{"access_token":"abc123","token_type":"Bearer"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String accessToken = CARAMarketingCloudAuthService.getAccessToken();
        Test.stopTest();

        Assert.areEqual('abc123', accessToken);
        Assert.areEqual(1, mock.capturedRequests.size());
        Assert.isTrue(mock.capturedRequests[0].getBody().contains('client_id=test-client-id'));
        Assert.isTrue(mock.capturedRequests[0].getBody().contains('client_secret=test-client-secret'));
    }


    @IsTest
    static void nonSuccessTokenResponseThrowsAuthException() {
        insert new CARA_Marketing_Cloud_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Client_Id__c = 'test-client-id',
            Client_Secret__c = 'test-client-secret'
        );

        TokenMock mock = new TokenMock();
        mock.statusCode = 401;
        mock.body = '{"error":"invalid_client"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            CARAMarketingCloudAuthService.getAccessToken();
            Assert.fail('Expected an AuthException on a non-200 token response.');
        } catch (CARAMarketingCloudAuthService.AuthException expectedError) {
            Assert.isTrue(expectedError.getMessage().contains('401'));
        }
        Test.stopTest();
    }


    @IsTest
    static void missingAccessTokenFieldThrowsAuthException() {
        insert new CARA_Marketing_Cloud_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Client_Id__c = 'test-client-id',
            Client_Secret__c = 'test-client-secret'
        );

        TokenMock mock = new TokenMock();
        mock.body = '{"token_type":"Bearer"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            CARAMarketingCloudAuthService.getAccessToken();
            Assert.fail('Expected an AuthException when access_token is missing.');
        } catch (CARAMarketingCloudAuthService.AuthException expectedError) {
            Assert.isTrue(expectedError.getMessage().contains('access_token'));
        }
        Test.stopTest();
    }


    private class TokenMock implements HttpCalloutMock {
        public Integer statusCode = 200;
        public String body = '{"access_token":"abc123"}';
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