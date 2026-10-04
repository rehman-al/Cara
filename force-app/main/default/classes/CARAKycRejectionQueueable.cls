public with sharing class CARAKycRejectionQueueable implements Queueable, Database.AllowsCallouts {

    private static final Set<String> ALREADY_HANDLED_STATUSES = new Set<String>{
        'Processing', 'Order Cancelled', 'Awaiting Gateway', 'Completed'
    };

    private static final String SYSTEM_ACTOR = 'SFSC-KYC-Automation';

    private List<Id> caseIds;

    public CARAKycRejectionQueueable(List<Id> caseIds) {
        this.caseIds = caseIds;
    }

    public void execute(QueueableContext context) {
        for (Id caseId : caseIds) {
            try {
                process(caseId);
            } catch (Exception unexpectedError) {
                // One Case's failure must never block the others in the same batch.
                System.debug(
                    LoggingLevel.ERROR,
                    'KYC rejection handling failed for Case ' + caseId + ': ' + unexpectedError.getMessage()
                );
                failSafely(caseId, 'Unexpected error: ' + unexpectedError.getMessage());
            }
        }
    }


    /*
     * Apex forbids a callout after a DML statement in the same
     * transaction. This method therefore performs every callout FIRST,
     * accumulating the outcome in local variables, and issues exactly
     * one DML statement — the final Case update — at the very end (the
     * only exceptions are the two guard-clause early-exits below, which
     * have no callout before them at all, so DML-only there is safe).
     */
    private static void process(Id caseId) {

        Case caseRecord = [
            SELECT Id, KYC_Rejection_Status__c, KYC_Rejection_Log__c, KYC_Order__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        // Idempotency guard: never re-run for a Case already in flight or done.
        if (String.isNotBlank(caseRecord.KYC_Rejection_Status__c)
            && ALREADY_HANDLED_STATUSES.contains(caseRecord.KYC_Rejection_Status__c)) {
            return;
        }

        if (caseRecord.KYC_Order__c == null) {
            updateCase(caseRecord, 'Failed', 'No related Order found via KYC_Order__c — nothing to cancel.');
            return;
        }

        List<Order> orders = [
            SELECT Id, OrderReferenceNumber, Storefront_Site_ID__c, Payment_Status__c,
                   CurrencyIsoCode__c, Product_Total__c, Shipping_Total_Cost__c, Tax_Total_Amount__c,
                   Customer_Email__c, Customer_Name_Plain__c
            FROM Order
            WHERE Id = :caseRecord.KYC_Order__c
            LIMIT 1
        ];

        if (orders.isEmpty()) {
            updateCase(caseRecord, 'Failed', 'Related Order ' + caseRecord.KYC_Order__c + ' could not be queried.');
            return;
        }

        Order orderRecord = orders[0];

        // Cancel + void/refund is fully delegated to the shared service so the
        // manual Order "Cancel & Refund" action (CARAOrderCancellationController)
        // uses the exact same callout logic — no second integration.
        CARAOrderCancellationService.CancellationResult result =
            CARAOrderCancellationService.cancelAndSettle(orderRecord, 'KYC rejected', SYSTEM_ACTOR);

        // Only an actual SFCC cancellation failure should leave the Case
        // 'Failed' (safe to retry). Refund outcome is independent and must
        // never block the Order from moving to Cancelled.
        if (!result.orderCancelled) {
            finish(caseRecord, 'Failed', result.logLines);
            return;
        }

        Boolean refundFailed = result.refundApplicable && result.refundSuccess != true;
        if (refundFailed) {
            finishOrderCancelledOnly(caseRecord, orderRecord, result.logLines);
            return;
        }

        finishAndClose(caseRecord, orderRecord, result.logLines);
    }


    private static void updateCase(Case caseRecord, String status, String logLine) {
        finish(caseRecord, status, new List<String>{ logLine });
    }


    private static void finish(Case caseRecord, String status, List<String> logLines) {
        appendLog(caseRecord, logLines);
        caseRecord.KYC_Rejection_Status__c = status;
        update caseRecord;
    }


    private static void finishAndClose(Case caseRecord, Order orderRecord, List<String> logLines) {
        appendLog(caseRecord, logLines);
        caseRecord.KYC_Rejection_Status__c = 'Completed';
        caseRecord.Status = 'Closed';
        update caseRecord;

        // Only reached once cancellation succeeded and either no refund was
        // due or the refund was also recorded successfully.
        update new Order(Id = orderRecord.Id, Status = 'Cancelled');
    }


    /*
     * Order cancellation succeeded but a required refund failed to record.
     * The Order must still move to Cancelled — it is not rolled back for a
     * refund problem. The Case is left at 'Order Cancelled' (not 'Completed',
     * not 'Failed') so it reads as "cancelled, refund needs follow-up" and,
     * being in ALREADY_HANDLED_STATUSES, is never re-run against an order
     * that SFCC already considers cancelled.
     */
    private static void finishOrderCancelledOnly(Case caseRecord, Order orderRecord, List<String> logLines) {
        appendLog(caseRecord, logLines);
        caseRecord.KYC_Rejection_Status__c = 'Order Cancelled';
        update caseRecord;

        update new Order(Id = orderRecord.Id, Status = 'Cancelled');
    }


    private static void appendLog(Case caseRecord, List<String> logLines) {
        List<String> stamped = new List<String>();
        for (String logLine : logLines) {
            stamped.add(Datetime.now().format('yyyy-MM-dd HH:mm:ss') + ' — ' + logLine);
        }
        String joined = String.join(stamped, '\n');
        caseRecord.KYC_Rejection_Log__c = String.isBlank(caseRecord.KYC_Rejection_Log__c)
            ? joined
            : caseRecord.KYC_Rejection_Log__c + '\n' + joined;
    }


    private static void failSafely(Id caseId, String message) {
        try {
            Case caseRecord = [SELECT Id, KYC_Rejection_Log__c FROM Case WHERE Id = :caseId LIMIT 1];
            updateCase(caseRecord, 'Failed', message);
        } catch (Exception ignoredError) {
            System.debug(LoggingLevel.ERROR, 'Could not record failure for Case ' + caseId + ': ' + ignoredError.getMessage());
        }
    }
}