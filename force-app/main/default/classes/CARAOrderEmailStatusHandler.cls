/*
 * Flow-invocable handler for the Order Invoice/Delivery Status-change
 * trigger (Order_Status_Email flow) — same pattern as
 * CARABalanceLinkHandler, enqueueing the actual callout work so the
 * after-save Flow never attempts a callout in its own transaction.
 */
public with sharing class CARAOrderEmailStatusHandler {

    @InvocableMethod(
        label='Send Order Status Email'
        description='Enqueues the Marketing Cloud Invoice/Delivery email for an Order whose Status changed.'
    )
    public static void sendOrderStatusEmail(List<Id> orderIds) {
        System.enqueueJob(new CARAOrderEmailQueueable(orderIds));
    }
}