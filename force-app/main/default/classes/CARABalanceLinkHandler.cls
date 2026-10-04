/*
 * Invoked by a Flow when an Order is marked ready for delivery (e.g.
 * Shipping_Status__c changes to the "ready" value), or from an LWC button
 * via CARASplitPaymentController.
 */
public with sharing class CARABalanceLinkHandler {

    @InvocableMethod(
        label='Send N-Genius Balance Payment Link'
        description='Requests the SFCC/MRT balance link (Link 2) for an Order and emails the customer unless it is already paid.'
    )
    public static void sendBalanceLinks(List<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new CARABalanceLinkQueueable(orderIds));
    }
}