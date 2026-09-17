@IsTest
private class CARAStoreRestServiceTest {

    @TestSetup
    static void setupData() {

        insert new List<Store__c>{
            new Store__c(
                Name = 'Active Store',
                Address__c = 'Dubai, UAE',
                Name_AR__c = 'المتجر النشط',
                Address_AR__c = 'دبي، الإمارات',
                Active__c = true
            ),
            new Store__c(Name = 'Inactive Store', Address__c = 'Sharjah, UAE', Active__c = false)
        };
    }


    private static RestRequest buildRequest(String langValue) {

        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/stores';
        requestRecord.httpMethod = 'GET';
        if (langValue != null) {
            requestRecord.addParameter('lang', langValue);
        }

        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();

        return requestRecord;
    }


    @IsTest
    static void returnsOnlyActiveStoresWithInterestCategories() {

        buildRequest(null);

        Test.startTest();
        CARAStoreRestService.getStores();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );

        System.assertEquals(true, responseMap.get('success'));

        List<Object> stores = (List<Object>) responseMap.get('stores');
        System.assertEquals(1, stores.size());

        Map<String, Object> store = (Map<String, Object>) stores[0];
        System.assertEquals('Active Store', (String) store.get('storeName'));

        List<Object> categories = (List<Object>) responseMap.get('interestCategories');
        System.assertEquals(4, categories.size());

        Map<String, Object> firstCategory = (Map<String, Object>) categories[0];
        System.assertEquals('general', (String) firstCategory.get('id'));
        System.assertEquals('General appointment', (String) firstCategory.get('label'));
    }


    @IsTest
    static void returnsArabicNameAndAddressWhenRequested() {

        buildRequest('ar');

        Test.startTest();
        CARAStoreRestService.getStores();
        Test.stopTest();

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );

        List<Object> stores = (List<Object>) responseMap.get('stores');
        Map<String, Object> store = (Map<String, Object>) stores[0];

        System.assertEquals('المتجر النشط', (String) store.get('storeName'));
        System.assertEquals('دبي، الإمارات', (String) store.get('address'));
    }


    @IsTest
    static void fallsBackToEnglishWhenArabicFieldsAreBlank() {

        Store__c englishOnlyStore = new Store__c(
            Name = 'English Only Store',
            Address__c = 'Abu Dhabi, UAE',
            Active__c = true
        );
        insert englishOnlyStore;

        buildRequest('ar');

        Test.startTest();
        CARAStoreRestService.getStores();
        Test.stopTest();

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );

        List<Object> stores = (List<Object>) responseMap.get('stores');

        Boolean foundEnglishFallback = false;
        for (Object storeObj : stores) {
            Map<String, Object> store = (Map<String, Object>) storeObj;
            if (store.get('storeName') == 'English Only Store') {
                foundEnglishFallback = true;
            }
        }
        System.assertEquals(true, foundEnglishFallback);
    }
}