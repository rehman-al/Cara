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
        Account acct = [
            SELECT
                Id,
                Name,
                Phone,
                Type,
                Website,
                External_ID__c,
                Is_Guest__c,
                CreatedDate,
                KYC_Completed__c,
                VIP_Status__c,
                Customer_Tier__c,
                Customer_Tags__c,
                Loyalty_Tier_Benefits__c,
                Customer_Lifetime_Spend__c,
                Number_of_Orders__c,
                Average_Order_Value__c,
                First_Order_Date__c,
                Preferred_Currency__c,
                PersonEmail,
                PersonMobilePhone,
                PersonHomePhone,
                PersonMailingStreet,
                PersonMailingCity,
                PersonMailingState,
                PersonMailingPostalCode,
                PersonMailingCountry
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        result.account = acct;


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


        // ORDER METRICS come from the Account roll-up fields maintained by
        // OrderCustomerMetricsTrigger, not recalculated here.
        result.totalOrders = acct.Number_of_Orders__c == null
            ? 0
            : acct.Number_of_Orders__c.intValue();

        result.lifetimeValue = acct.Customer_Lifetime_Spend__c == null
            ? 0
            : acct.Customer_Lifetime_Spend__c;

        result.averageOrderValue = acct.Average_Order_Value__c == null
            ? 0
            : acct.Average_Order_Value__c;


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
        public Integer totalCases {
            get;
            set;
        }


        @AuraEnabled
        public Decimal lifetimeValue {
            get;
            set;
        }


        @AuraEnabled
        public Decimal averageOrderValue {
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
            totalCases = 0;
            lifetimeValue = 0;
            averageOrderValue = 0;
        }
    }
}