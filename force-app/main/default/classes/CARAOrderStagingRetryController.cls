/**
 * "Retry Sync" action on the SFCC Order Staging record page. Reuses the
 * exact same CARAOrderSyncService the inbound SFCC API uses — SFCC never
 * needs to resend the request. Access is gated on object-level Edit access
 * to SFCC_Order_Staging__c, which is only granted to the Operations Access
 * and Finance Operations Access permission sets (plus System Administrator,
 * which has implicit access to every object in this org).
 */
public with sharing class CARAOrderStagingRetryController {

    public class RetryResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id orderId;
    }

    @AuraEnabled
    public static RetryResult retrySync(Id stagingId) {
        if (!Schema.sObjectType.SFCC_Order_Staging__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to retry Order Sync.');
        }

        RetryResult result = new RetryResult();
        try {
            CARAOrderSyncService.SyncOutcome outcome = CARAOrderSyncService.syncFromStaging(stagingId);
            result.success = outcome.success;
            result.message = outcome.message;
            result.orderId = outcome.orderId;
            return result;
        } catch (CARAOrderSyncService.SyncInProgressException concurrencyError) {
            result.success = false;
            result.message = concurrencyError.getMessage();
            return result;
        } catch (CARAOrderSyncService.IntegrationException expectedError) {
            result.success = false;
            result.message = expectedError.getMessage();
            return result;
        } catch (Exception unexpectedError) {
            throw new AuraHandledException(unexpectedError.getMessage());
        }
    }
}