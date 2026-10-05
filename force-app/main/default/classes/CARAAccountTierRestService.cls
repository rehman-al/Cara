/**
 * Exposes an Account's loyalty/tier data to SFCC. Looked up by the SFCC
 * customerId (Account.External_ID__c, the same identifier CARAOrderSyncService
 * stamps on the Account) or, as a fallback, by the customer's Contact email.
 */
@RestResource(urlMapping='/cara/accounts/tier')
global with sharing class CARAAccountTierRestService {

    @HttpGet
    global static void getAccountTier() {
        try {
            String customerId = RestContext.request.params.get('customerId');
            String emailAddress = RestContext.request.params.get('email');

            Account accountRecord = resolveAccount(customerId, emailAddress);

            CARAAppointmentApiSupport.writeResponse(200, buildResponse(accountRecord));
        } catch (IntegrationException exceptionRecord) {
            CARAAppointmentApiSupport.writeError(exceptionRecord.statusCode, exceptionRecord.getMessage());
        } catch (Exception exceptionRecord) {
            System.debug(LoggingLevel.ERROR, 'Account tier API error: ' + exceptionRecord.getMessage());
            CARAAppointmentApiSupport.writeError(500, 'Unable to retrieve account tier data.');
        }
    }

    private static Account resolveAccount(String customerId, String emailAddress) {
        customerId = String.isBlank(customerId) ? null : customerId.trim();
        emailAddress = String.isBlank(emailAddress) ? null : emailAddress.trim().toLowerCase();

        if (customerId == null && emailAddress == null) {
            throw new IntegrationException(400, 'Either customerId or email is required.');
        }

        List<Account> matchingAccounts = customerId != null
            ? queryByCustomerId(customerId)
            : queryByEmail(emailAddress);

        if (matchingAccounts.isEmpty()) {
            throw new IntegrationException(404, 'No Account found for the supplied identifier.');
        }
        if (matchingAccounts.size() > 1) {
            throw new IntegrationException(409, 'Multiple Accounts match the supplied identifier.');
        }
        return matchingAccounts[0];
    }

    private static List<Account> queryByCustomerId(String customerId) {
        return [
            SELECT Id, External_ID__c, Customer_Tier__c, Tier_1_Customer__c, VIP_Status__c,
                   Customer_Segment__c, Customer_Tags__c, Loyalty_Tier_Benefits__c,
                   Customer_Lifetime_Spend__c
            FROM Account
            WHERE External_ID__c = :customerId
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
    }

    private static List<Account> queryByEmail(String emailAddress) {
        List<Contact> matchingContacts = [
            SELECT AccountId
            FROM Contact
            WHERE Email = :emailAddress AND AccountId != null
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
        if (matchingContacts.isEmpty()) {
            return new List<Account>();
        }
        if (matchingContacts.size() > 1) {
            throw new IntegrationException(409, 'Multiple Contacts match the supplied email.');
        }

        return [
            SELECT Id, External_ID__c, Customer_Tier__c, Tier_1_Customer__c, VIP_Status__c,
                   Customer_Segment__c, Customer_Tags__c, Loyalty_Tier_Benefits__c,
                   Customer_Lifetime_Spend__c
            FROM Account
            WHERE Id = :matchingContacts[0].AccountId
            LIMIT 1
        ];
    }

    private static AccountTierResponse buildResponse(Account accountRecord) {
        AccountTierResponse responseBody = new AccountTierResponse();
        responseBody.success = true;
        responseBody.accountId = accountRecord.Id;
        responseBody.customerId = accountRecord.External_ID__c;
        responseBody.customerTier = accountRecord.Customer_Tier__c;
        responseBody.tier1Customer = accountRecord.Tier_1_Customer__c;
        responseBody.vipStatus = accountRecord.VIP_Status__c;
        responseBody.customerSegment = accountRecord.Customer_Segment__c;
        responseBody.customerTag = accountRecord.Customer_Tags__c;
        responseBody.loyaltyTierBenefits = accountRecord.Loyalty_Tier_Benefits__c;
        responseBody.lifetimeSpend = accountRecord.Customer_Lifetime_Spend__c;
        return responseBody;
    }

    public class AccountTierResponse {
        public Boolean success;
        public Id accountId;
        public String customerId;
        public String customerTier;
        public Boolean tier1Customer;
        public Boolean vipStatus;
        public String customerSegment;
        public String customerTag;
        public String loyaltyTierBenefits;
        public Decimal lifetimeSpend;
    }

    private class IntegrationException extends Exception {
        private Integer statusCode;

        private IntegrationException(Integer statusCode, String message) {
            this(message);
            this.statusCode = statusCode;
        }
    }
}