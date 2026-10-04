/*
 * Cancel Quote (before the customer pays the deposit) — deletes the
 * SFCC/MRT basket for a Custom Product Request. Idempotent by design: a
 * request with no basket yet, or whose basket the gateway already
 * considers gone, is treated as a successful cancel rather than an error.
 */
public with sharing class CARADeleteBasketQueueable implements Queueable, Database.AllowsCallouts {

    public class CancelRequest {
        public Id customProductRequestId;
        public String reason;
    }

    private List<CancelRequest> cancelRequests;

    public CARADeleteBasketQueueable(List<CancelRequest> cancelRequests) {
        this.cancelRequests = cancelRequests;
    }

    public void execute(QueueableContext context) {
        for (CancelRequest cancelRequest : cancelRequests) {
            try {
                process(cancelRequest);
            } catch (Exception unexpectedError) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Deposit basket cancellation failed for ' + cancelRequest.customProductRequestId +
                    ': ' + unexpectedError.getMessage()
                );
                failSafely(cancelRequest.customProductRequestId, 'Unexpected error: ' + unexpectedError.getMessage());
            }
        }
    }


    private static void process(CancelRequest cancelRequest) {
        List<Custom_Product_Request__c> records = [
            SELECT Id, Basket_Id__c, Basket_Status__c, Basket_Log__c, Case__r.Contact.Email
            FROM Custom_Product_Request__c
            WHERE Id = :cancelRequest.customProductRequestId
            LIMIT 1
        ];

        if (records.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Custom Product Request ' + cancelRequest.customProductRequestId + ' could not be found.');
            return;
        }

        Custom_Product_Request__c requestRecord = records[0];

        // Nothing was ever created, or it was already deleted — idempotent no-op.
        if (String.isBlank(requestRecord.Basket_Id__c) || requestRecord.Basket_Status__c == 'Deleted') {
            requestRecord.Basket_Status__c = 'Deleted';
            appendLog(requestRecord, 'Cancel requested (' + cancelRequest.reason + ') — no live basket to delete.');
            update requestRecord;
            return;
        }

        String customerLogin = requestRecord.Case__r != null && requestRecord.Case__r.Contact != null
            ? requestRecord.Case__r.Contact.Email
            : null;

        CARASfscSplitPaymentService.DeleteBasketResult result =
            CARASfscSplitPaymentService.deleteBasket(requestRecord.Basket_Id__c, customerLogin);

        if (!result.success) {
            appendLog(requestRecord, '[' + result.errorCategory + '] Delete basket failed: ' + result.errorMessage);
            update requestRecord;
            return;
        }

        requestRecord.Basket_Status__c = 'Deleted';
        appendLog(
            requestRecord,
            result.alreadyGone
                ? 'Basket already gone at SFCC/MRT — treated as deleted.'
                : 'Basket deleted. Reason: ' + cancelRequest.reason
        );
        update requestRecord;
    }


    private static void appendLog(Custom_Product_Request__c requestRecord, String logLine) {
        String stamped = Datetime.now().format('yyyy-MM-dd HH:mm:ss') + ' — ' + logLine;
        requestRecord.Basket_Log__c = String.isBlank(requestRecord.Basket_Log__c)
            ? stamped
            : requestRecord.Basket_Log__c + '\n' + stamped;
    }


    private static void failSafely(Id requestId, String message) {
        try {
            Custom_Product_Request__c requestRecord = [
                SELECT Id, Basket_Log__c FROM Custom_Product_Request__c WHERE Id = :requestId LIMIT 1
            ];
            appendLog(requestRecord, '[' + CARASfscSplitPaymentService.ERROR_UNKNOWN + '] ' + message);
            update requestRecord;
        } catch (Exception ignoredError) {
            System.debug(LoggingLevel.ERROR, 'Could not record failure for ' + requestId + ': ' + ignoredError.getMessage());
        }
    }
}