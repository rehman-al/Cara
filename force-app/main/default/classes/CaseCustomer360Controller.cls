public with sharing class CaseCustomer360Controller {

    @AuraEnabled(cacheable=true)
    public static CustomerContext getCustomerContext(
        Id caseId
    ) {

        if (caseId == null) {

            throw new AuraHandledException(
                'Case Id is required.'
            );
        }


        CustomerContext result =
            new CustomerContext();


        // CURRENT CASE
        Case currentCase = [
            SELECT
                Id,
                CaseNumber,
                AccountId,
                ContactId,
                Subject,
                Status,
                Priority
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];


        result.currentCase =
            currentCase;


        if (currentCase.AccountId == null) {

            result.message =
                'No Account is linked to this Case.';

            return result;
        }


        Id accountId =
            currentCase.AccountId;


        // ACCOUNT
        result.account = [
            SELECT
                Id,
                Name,
                Phone,
                Type,
                Website,
                External_ID__c,
                Is_Guest__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];


        // CONTACT
        if (currentCase.ContactId != null) {

            List<Contact> contacts = [
                SELECT
                    Id,
                    Name,
                    Email,
                    Phone,
                    MobilePhone,
                    AccountId
                FROM Contact
                WHERE Id =
                    :currentCase.ContactId
                LIMIT 1
            ];


            if (!contacts.isEmpty()) {

                result.contact =
                    contacts[0];
            }
        }


        // ORDER HISTORY
        result.orders = [
            SELECT
                Id,
                OrderNumber,
                Status,
                Shipping_Status__c,
                Payment_Status__c,
                Confirmation_Status__c,
                TotalAmount,
                CurrencyIsoCode__c,
                CreatedDate
            FROM Order
            WHERE AccountId = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];


        // TOTAL ORDERS
        result.totalOrders = [
            SELECT COUNT()
            FROM Order
            WHERE AccountId = :accountId
        ];


        // COMPLETED = DELIVERED
        result.completedOrders = [
            SELECT COUNT()
            FROM Order
            WHERE AccountId = :accountId
            AND Shipping_Status__c =
                'Delivered'
        ];


        // AED LTV
        List<AggregateResult> ltvResults = [
            SELECT
                SUM(TotalAmount) totalLtv
            FROM Order
            WHERE AccountId = :accountId
            AND Shipping_Status__c =
                'Delivered'
            AND CurrencyIsoCode__c =
                'AED'
        ];


        if (
            !ltvResults.isEmpty() &&
            ltvResults[0].get('totalLtv')
                != null
        ) {

            result.lifetimeValue =
                (Decimal)
                ltvResults[0]
                    .get('totalLtv');

        } else {

            result.lifetimeValue = 0;
        }


        // PREVIOUS CASES
        result.previousCases = [
            SELECT
                Id,
                CaseNumber,
                Subject,
                Status,
                Priority,
                CreatedDate
            FROM Case
            WHERE AccountId = :accountId
            AND Id != :caseId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];


        result.totalCases = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :accountId
        ];


        // ALL CUSTOMER CASE IDS
        Set<Id> customerCaseIds =
            new Set<Id>();


        customerCaseIds.add(
            currentCase.Id
        );


        for (
            Case previousCase :
            result.previousCases
        ) {

            customerCaseIds.add(
                previousCase.Id
            );
        }


        // EMAIL CONVERSATIONS
        if (!customerCaseIds.isEmpty()) {

            result.conversations = [
                SELECT
                    Id,
                    ParentId,
                    Subject,
                    FromAddress,
                    ToAddress,
                    Incoming,
                    MessageDate
                FROM EmailMessage
                WHERE ParentId
                    IN :customerCaseIds
                ORDER BY MessageDate DESC
                LIMIT 30
            ];
        }


        result.message =
            'Customer context loaded successfully.';


        return result;
    }


    public class CustomerContext {

        @AuraEnabled
        public String message {
            get;
            set;
        }


        @AuraEnabled
        public Case currentCase {
            get;
            set;
        }


        @AuraEnabled
        public Account account {
            get;
            set;
        }


        @AuraEnabled
        public Contact contact {
            get;
            set;
        }


        @AuraEnabled
        public List<Order> orders {
            get;
            set;
        }


        @AuraEnabled
        public List<Case> previousCases {
            get;
            set;
        }


        @AuraEnabled
        public List<EmailMessage> conversations {
            get;
            set;
        }


        @AuraEnabled
        public Integer totalOrders {
            get;
            set;
        }


        @AuraEnabled
        public Integer completedOrders {
            get;
            set;
        }


        @AuraEnabled
        public Integer totalCases {
            get;
            set;
        }


        @AuraEnabled
        public Decimal lifetimeValue {
            get;
            set;
        }


        public CustomerContext() {

            orders =
                new List<Order>();

            previousCases =
                new List<Case>();

            conversations =
                new List<EmailMessage>();

            totalOrders = 0;
            completedOrders = 0;
            totalCases = 0;
            lifetimeValue = 0;
        }
    }
}