@IsTest
private class CARAAccountTierRestServiceTest {
    private static final String CUSTOMER_ID = 'SFCC-00012345';
    private static final String CONTACT_EMAIL = 'tier.customer@example.com';

    @TestSetup
    static void setupData() {
        Account accountRecord = new Account(
            Name = 'Test Tier Account',
            External_ID__c = CUSTOMER_ID,
            Customer_Tier__c = 'Gold',
            Tier_1_Customer__c = true,
            VIP_Status__c = true,
            Customer_Segment__c = 'Retail',
            Loyalty_Tier_Benefits__c = 'Free shipping; birthday gift',
            Customer_Lifetime_Spend__c = 125000
        );
        insert accountRecord;

        insert new Contact(
            LastName = 'Tier Customer',
            AccountId = accountRecord.Id,
            Email = CONTACT_EMAIL
        );
    }

    private static void buildRequest(String customerId, String emailAddress) {
        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/accounts/tier';
        requestRecord.httpMethod = 'GET';
        if (customerId != null) {
            requestRecord.addParameter('customerId', customerId);
        }
        if (emailAddress != null) {
            requestRecord.addParameter('email', emailAddress);
        }

        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
    }

    @IsTest
    static void returnsTierDataByCustomerId() {
        buildRequest(CUSTOMER_ID, null);

        Test.startTest();
        CARAAccountTierRestService.getAccountTier();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(true, responseBody.get('success'));
        Assert.areEqual('Gold', responseBody.get('customerTier'));
        Assert.areEqual(true, responseBody.get('tier1Customer'));
        Assert.areEqual(true, responseBody.get('vipStatus'));
        Assert.areEqual('Retail', responseBody.get('customerSegment'));
        Assert.areEqual('Free shipping; birthday gift', responseBody.get('loyaltyTierBenefits'));
        Assert.areEqual(125000, (Decimal) responseBody.get('lifetimeSpend'));
    }

    @IsTest
    static void returnsTierDataByEmailFallback() {
        buildRequest(null, CONTACT_EMAIL.toUpperCase());

        Test.startTest();
        CARAAccountTierRestService.getAccountTier();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(true, responseBody.get('success'));
        Assert.areEqual(CUSTOMER_ID, responseBody.get('customerId'));
    }

    @IsTest
    static void returnsBadRequestWhenNoIdentifierSupplied() {
        buildRequest(null, null);

        Test.startTest();
        CARAAccountTierRestService.getAccountTier();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void returnsNotFoundWhenNoAccountMatches() {
        buildRequest('UNKNOWN-CUSTOMER-ID', null);

        Test.startTest();
        CARAAccountTierRestService.getAccountTier();
        Test.stopTest();

        Assert.areEqual(404, RestContext.response.statusCode);
    }

    @IsTest
    static void returnsConflictWhenCustomerIdIsAmbiguous() {
        insert new Account(Name = 'Duplicate Tier Account', External_ID__c = CUSTOMER_ID);

        buildRequest(CUSTOMER_ID, null);

        Test.startTest();
        CARAAccountTierRestService.getAccountTier();
        Test.stopTest();

        Assert.areEqual(409, RestContext.response.statusCode);
    }
}