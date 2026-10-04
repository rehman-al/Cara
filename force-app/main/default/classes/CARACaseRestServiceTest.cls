@IsTest
private class CARACaseRestServiceTest {
    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Storefront Customer');
        insert account;

        insert new Contact(
            FirstName = 'Storefront',
            LastName = 'Customer',
            Email = 'storefront.customer@example.com',
            AccountId = account.Id
        );

        Id generalEnquiryRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .get('General_Enquiry')
            .getRecordTypeId();
        Id complianceRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .get('Compliance')
            .getRecordTypeId();

        insert new List<Case>{
            new Case(
                AccountId = account.Id,
                RecordTypeId = generalEnquiryRecordTypeId,
                Subject = 'Where is my order?',
                Status = 'New',
                Origin = 'Web'
            ),
            new Case(
                AccountId = account.Id,
                RecordTypeId = generalEnquiryRecordTypeId,
                Subject = 'Refund request',
                Status = 'Closed',
                Origin = 'Email'
            ),
            new Case(
                AccountId = account.Id,
                RecordTypeId = complianceRecordTypeId,
                Subject = 'KYC document review',
                Status = 'New',
                Origin = 'Email'
            )
        };
    }

    @IsTest
    static void returnsOnlyGeneralEnquiryCasesForAccount() {
        setCaseRequest('storefront.customer@example.com');

        Test.startTest();
        CARACaseRestService.getCasesByAccount();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(true, responseBody.get('success'));
        Assert.areEqual(2, (Integer) responseBody.get('count'));
        Assert.areEqual(2, ((List<Object>) responseBody.get('cases')).size());
    }

    @IsTest
    static void returnsOnlyGeneralEnquiryCasesForAccountCaseInsensitiveEmail() {
        setCaseRequest('STOREFRONT.CUSTOMER@EXAMPLE.COM');

        Test.startTest();
        CARACaseRestService.getCasesByAccount();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(2, (Integer) responseBody.get('count'));
    }

    @IsTest
    static void returnsEmptyListWhenAccountHasNoCases() {
        Account account = new Account(Name = 'No Cases Customer');
        insert account;
        insert new Contact(
            FirstName = 'No Cases',
            LastName = 'Customer',
            Email = 'no.cases.customer@example.com',
            AccountId = account.Id
        );
        setCaseRequest('no.cases.customer@example.com');

        Test.startTest();
        CARACaseRestService.getCasesByAccount();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Assert.areEqual(0, (Integer) responseBody.get('count'));
    }

    @IsTest
    static void rejectsMissingEmail() {
        setCaseRequest(null);
        CARACaseRestService.getCasesByAccount();
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void rejectsEmailWithMultipleMatchingContacts() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        insert new Contact(
            FirstName = 'Duplicate',
            LastName = 'Customer',
            Email = 'storefront.customer@example.com',
            AccountId = account.Id
        );
        setCaseRequest('storefront.customer@example.com');

        CARACaseRestService.getCasesByAccount();
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void returnsNotFoundForUnknownEmail() {
        setCaseRequest('unknown.customer@example.com');
        CARACaseRestService.getCasesByAccount();
        Assert.areEqual(404, RestContext.response.statusCode);
    }

    @IsTest
    static void returnsNotFoundForContactWithoutAccount() {
        insert new Contact(
            FirstName = 'Orphan',
            LastName = 'Contact',
            Email = 'orphan.contact@example.com'
        );
        setCaseRequest('orphan.contact@example.com');

        CARACaseRestService.getCasesByAccount();
        Assert.areEqual(404, RestContext.response.statusCode);
    }

    private static void setCaseRequest(String emailValue) {
        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/cases';
        requestRecord.httpMethod = 'GET';
        if (emailValue != null) {
            requestRecord.params.put('email', emailValue);
        }
        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
    }
}