public with sharing class ClaudeE2EInspector {
    @AuraEnabled
    public static String dumpCprByCaseNumber(String caseNumber) {
        Case c = [SELECT Id, CaseNumber, Status, SuppliedEmail, SuppliedName, ContactId,
                         Contact_Method_Preference__c, Description, CreatedDate
                  FROM Case WHERE CaseNumber = :caseNumber WITH SYSTEM_MODE LIMIT 1];
        Custom_Product_Request__c cpr = [
            SELECT Id, Name, Case__c, Product_Name__c, Status__c, Piece_Type__c, Preferred_Metal__c,
                   Stone_Type__c, Budget_Guide__c, Timeline__c, Brief_Source__c, Description__c,
                   Product__c, Selling_Price__c, Basket_Id__c, Basket_Status__c, Basket_Log__c,
                   Deposit_Link__c, Deposit_Amount__c, Order_Total__c
            FROM Custom_Product_Request__c WHERE Case__c = :c.Id WITH SYSTEM_MODE LIMIT 1
        ];
        Map<String, Object> dump = new Map<String, Object>{ 'case' => c, 'cpr' => cpr };
        return JSON.serializePretty(dump);
    }

    public static String dumpCprById(Id cprId) {
        Custom_Product_Request__c cpr = [
            SELECT Id, Name, Case__c, Product_Name__c, Status__c, Piece_Type__c, Preferred_Metal__c,
                   Stone_Type__c, Budget_Guide__c, Timeline__c, Brief_Source__c, Description__c,
                   Product__c, Selling_Price__c, Basket_Id__c, Basket_Status__c, Basket_Log__c,
                   Deposit_Link__c, Deposit_Amount__c, Order_Total__c
            FROM Custom_Product_Request__c WHERE Id = :cprId WITH SYSTEM_MODE LIMIT 1
        ];
        return JSON.serializePretty(cpr);
    }

    public static String approveAndPrice(Id cprId, Id productId, Decimal price) {
        Custom_Product_Request__c cpr = new Custom_Product_Request__c(Id = cprId);
        cpr.Product__c = productId;
        cpr.Selling_Price__c = price;
        cpr.Status__c = 'Approved';
        Database.update(cpr, AccessLevel.SYSTEM_MODE);
        return dumpCprById(cprId);
    }

    public static String dumpOrderById(Id orderId) {
        Order o = [
            SELECT Id, OrderReferenceNumber, Customer_Email__c, Customer_Name_Plain__c,
                   Status, Balance_Link_Status__c, Balance_Link_Log__c, Balance_Link__c,
                   Balance_Remaining__c, Balance_Already_Paid__c
            FROM Order WHERE Id = :orderId WITH SYSTEM_MODE LIMIT 1
        ];
        return JSON.serializePretty(o);
    }

    public static Id createTestOrderForEmail(String email, String fullName, String orderNo, Id pricebookId) {
        Id contactId = linkContactToCaseByEmail(null, email, fullName, null);
        Contact con = [SELECT Id, AccountId FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE LIMIT 1];

        Order o = new Order(
            AccountId = con.AccountId,
            Contact__c = con.Id,
            OrderReferenceNumber = orderNo,
            Customer_Name_Plain__c = fullName,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = pricebookId
        );
        Database.insert(o, AccessLevel.SYSTEM_MODE);
        return o.Id;
    }

    // Simulates what a CSR would do to resolve the "missing Case Contact"
    // gap found in testing: finds/creates a Contact for this email and
    // links it to the given Case (if provided).
    public static Id linkContactToCaseByEmail(Id caseId, String email, String fullName, String phone) {
        List<Contact> existing = [SELECT Id, AccountId FROM Contact WHERE Email = :email WITH SYSTEM_MODE LIMIT 1];
        Id contactId;
        if (!existing.isEmpty()) {
            contactId = existing[0].Id;
        } else {
            Account acc = new Account(Name = fullName);
            Database.insert(acc, AccessLevel.SYSTEM_MODE);

            List<String> parts = fullName.split(' ', 2);
            Contact con = new Contact(
                AccountId = acc.Id,
                FirstName = parts.size() > 1 ? parts[0] : null,
                LastName = parts.size() > 1 ? parts[1] : fullName,
                Email = email,
                Phone = phone,
                MailingStreet = '123 Test Street',
                MailingCity = 'Dubai',
                MailingPostalCode = '00000',
                MailingCountry = 'AE'
            );
            Database.insert(con, AccessLevel.SYSTEM_MODE);
            contactId = con.Id;
        }

        if (caseId != null) {
            Case c = new Case(Id = caseId, ContactId = contactId);
            Database.update(c, AccessLevel.SYSTEM_MODE);
        }

        return contactId;
    }

    public static String setContactAddress(Id contactId, String street, String city, String postalCode, String country) {
        Contact con = new Contact(Id = contactId);
        con.MailingStreet = street;
        con.MailingCity = city;
        con.MailingPostalCode = postalCode;
        con.MailingCountry = country;
        Database.SaveResult sr = Database.update(con, AccessLevel.SYSTEM_MODE);
        Contact after = [SELECT Id, MailingStreet, MailingCity, MailingPostalCode, MailingCountry FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE LIMIT 1];
        return 'saveSuccess=' + sr.isSuccess() + ' errors=' + sr.getErrors() + ' after=' + JSON.serialize(after);
    }
}