/*
 * Invoked by a Flow on Custom_Product_Request__c approval (Status__c =
 * 'Approved'), or from an LWC button via CARASplitPaymentController — both
 * surfaces enqueue the exact same Queueable so there is one path that
 * calls the SFCC/MRT deposit-basket API.
 */
public with sharing class CARADepositBasketHandler {

    @InvocableMethod(
        label='Create N-Genius Deposit Basket'
        description='Creates the SFCC/MRT deposit basket (Link 1) for an approved Custom Product Request and emails the customer the payment link.'
    )
    public static void createDepositBaskets(List<Id> customProductRequestIds) {
        if (customProductRequestIds == null || customProductRequestIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new CARADepositBasketQueueable(customProductRequestIds));
    }
}