public with sharing class CARAKycRejectionHandler {

    /*
     * Invoked by the KYC_Rejected_Cancel_And_Refund Flow when a Case's
     * Status changes to 'Compliance Rejected' by the existing
     * Case_Finance_Approval approval process. This does not touch the
     * approval process itself — it only reacts to the outcome.
     *
     * The actual work is enqueued rather than run here directly: this
     * action fires in the same transaction as the Case save that
     * triggered it (an after-save flow), and that save's DML has
     * already committed by the time this runs — attempting an HTTP
     * callout in that same transaction throws "You have uncommitted
     * work pending". Queueable gives the real work its own transaction.
     */
    @InvocableMethod(
        label='Handle KYC Case Rejection'
        description='Cancels the related SFCC order and initiates the N-Genius void/refund when a KYC compliance Case is rejected.'
    )
    public static void handleRejection(List<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new CARAKycRejectionQueueable(caseIds));
    }
}