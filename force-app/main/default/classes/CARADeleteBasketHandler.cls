public with sharing class CARADeleteBasketHandler {

    public class CancelRequest {
        @InvocableVariable(required=true label='Custom Product Request Id')
        public Id customProductRequestId;

        @InvocableVariable(label='Cancellation Reason')
        public String reason;
    }

    @InvocableMethod(
        label='Cancel N-Genius Deposit Basket'
        description='Deletes the SFCC/MRT deposit basket for a cancelled Quote/Custom Product Request before the customer has paid.'
    )
    public static void cancelDepositBaskets(List<CancelRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        List<CARADeleteBasketQueueable.CancelRequest> queueableRequests = new List<CARADeleteBasketQueueable.CancelRequest>();

        for (CancelRequest requestItem : requests) {
            CARADeleteBasketQueueable.CancelRequest queueableRequest = new CARADeleteBasketQueueable.CancelRequest();
            queueableRequest.customProductRequestId = requestItem.customProductRequestId;
            queueableRequest.reason = requestItem.reason;
            queueableRequests.add(queueableRequest);
        }

        System.enqueueJob(new CARADeleteBasketQueueable(queueableRequests));
    }
}