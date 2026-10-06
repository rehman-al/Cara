@IsTest
private class CARADepositBasketPreflightTest {

    private static Custom_Product_Request__c buildRequest(Boolean withProduct, String country) {
        Account acc = new Account(Name = 'Preflight Test Customer');
        insert acc;
        Contact contactRecord = new Contact(
            AccountId = acc.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'shopper@example.com',
            MailingStreet = '123 Main St',
            MailingCity = 'Dubai',
            MailingPostalCode = '00000',
            MailingCountry = country
        );
        insert contactRecord;
        Case caseRecord = new Case(ContactId = contactRecord.Id, Subject = 'Custom Piece Request');
        insert caseRecord;

        Id productId = null;
        if (withProduct) {
            Product2 productRecord = new Product2(Name = 'Custom Ring', IsActive = true, StockKeepingUnit = 'SKU_ID');
            insert productRecord;
            productId = productRecord.Id;
        }

        Custom_Product_Request__c requestRecord = new Custom_Product_Request__c(
            Case__c = caseRecord.Id,
            Product_Name__c = 'Custom Ring',
            Product__c = productId,
            Quantity__c = 1,
            Selling_Price__c = 1000,
            Status__c = 'Under Review'
        );
        insert requestRecord;
        return requestRecord;
    }


    private static List<CARADepositBasketPreflight.Result> run(Id requestId) {
        CARADepositBasketPreflight.Request input = new CARADepositBasketPreflight.Request();
        input.requestId = requestId;
        return CARADepositBasketPreflight.validate(new List<CARADepositBasketPreflight.Request>{ input });
    }


    @IsTest
    static void validRequestPassesAndIsUntouched() {
        Custom_Product_Request__c requestRecord = buildRequest(true, 'United Arab Emirates');

        List<CARADepositBasketPreflight.Result> results = run(requestRecord.Id);

        System.assertEquals(true, results[0].isValid);
        System.assertEquals('', results[0].missingFields);
        System.assertEquals('Under Review', [SELECT Status__c FROM Custom_Product_Request__c WHERE Id = :requestRecord.Id].Status__c);
    }


    @IsTest
    static void missingProductAndCountryMarksFailed() {
        Custom_Product_Request__c requestRecord = buildRequest(false, 'Atlantis');

        List<CARADepositBasketPreflight.Result> results = run(requestRecord.Id);

        System.assertEquals(false, results[0].isValid);
        System.assert(results[0].missingFields.contains('Product SKU'));
        System.assert(results[0].missingFields.contains('Mailing Address Country Code'));
        Custom_Product_Request__c result = [
            SELECT Status__c, Basket_Log__c FROM Custom_Product_Request__c WHERE Id = :requestRecord.Id
        ];
        System.assertEquals('Failed', result.Status__c);
        System.assert(result.Basket_Log__c.contains('Approval blocked'));
    }
}