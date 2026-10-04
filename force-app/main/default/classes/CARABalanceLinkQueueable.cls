/*
 * Link 2 (Balance) — requested when a piece is ready for delivery. Saves
 * the returned link/remaining/paid/alreadyPaid onto the Order, and emails
 * the customer the balance payment link unless it is already paid.
 */
public with sharing class CARABalanceLinkQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> orderIds;

    public CARABalanceLinkQueueable(List<Id> orderIds) {
        this.orderIds = orderIds;
    }

    public void execute(QueueableContext context) {
        for (Id orderId : orderIds) {
            try {
                process(orderId);
            } catch (Exception unexpectedError) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Balance link request failed for ' + orderId + ': ' + unexpectedError.getMessage()
                );
                failSafely(orderId, 'Unexpected error: ' + unexpectedError.getMessage());
            }
        }
    }


    private static void process(Id orderId) {
        List<Order> orders = [
            SELECT
                Id, OrderReferenceNumber, Customer_Email__c, Customer_Name__c,
                Balance_Link_Status__c, Balance_Link_Log__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];

        if (orders.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Order ' + orderId + ' could not be found.');
            return;
        }

        Order orderRecord = orders[0];

        if (String.isBlank(orderRecord.OrderReferenceNumber) || String.isBlank(orderRecord.Customer_Email__c)) {
            fail(
                orderRecord,
                CARASfscSplitPaymentService.ERROR_PAYLOAD,
                'Cannot request balance link — missing Order Reference Number or Customer Email.'
            );
            return;
        }

        CARASfscSplitPaymentService.BalanceLinkResult result = CARASfscSplitPaymentService.getBalanceLink(
            orderRecord.OrderReferenceNumber,
            orderRecord.Customer_Email__c
        );

        if (!result.success) {
            fail(orderRecord, result.errorCategory, result.errorMessage);
            return;
        }

        orderRecord.Balance_Link__c = result.link;
        orderRecord.Balance_Remaining__c = result.remaining;
        orderRecord.Balance_Already_Paid__c = result.alreadyPaid;
        orderRecord.Balance_Link_Status__c = result.alreadyPaid ? 'Already Paid' : 'Sent';
        appendLog(
            orderRecord,
            'Balance link retrieved. remaining=' + result.remaining + ', alreadyPaid=' + result.alreadyPaid
        );
        update orderRecord;

        if (result.alreadyPaid) {
            // Per the balance-link contract: only notify when alreadyPaid is false.
            return;
        }

        CARASplitPaymentNotificationService.NotificationOutcome notifyOutcome =
            CARASplitPaymentNotificationService.sendBalanceLink(
                orderRecord.Customer_Email__c,
                orderRecord.Customer_Name__c,
                orderRecord.OrderReferenceNumber,
                orderRecord.Balance_Remaining__c,
                orderRecord.Balance_Link__c
            );

        appendLogAndSave(orderRecord.Id, 'Balance link notification: ' + notifyOutcome.detail);
    }


    private static void fail(Order orderRecord, String errorCategory, String errorMessage) {
        orderRecord.Balance_Link_Status__c = 'Error';
        appendLog(orderRecord, '[' + errorCategory + '] ' + errorMessage);
        update orderRecord;
    }


    private static void appendLog(Order orderRecord, String logLine) {
        String stamped = Datetime.now().format('yyyy-MM-dd HH:mm:ss') + ' — ' + logLine;
        orderRecord.Balance_Link_Log__c = String.isBlank(orderRecord.Balance_Link_Log__c)
            ? stamped
            : orderRecord.Balance_Link_Log__c + '\n' + stamped;
    }


    private static void appendLogAndSave(Id orderId, String logLine) {
        try {
            Order orderRecord = [SELECT Id, Balance_Link_Log__c FROM Order WHERE Id = :orderId LIMIT 1];
            appendLog(orderRecord, logLine);
            update orderRecord;
        } catch (Exception ignoredError) {
            System.debug(
                LoggingLevel.ERROR,
                'Could not append notification outcome for Order ' + orderId + ': ' + ignoredError.getMessage()
            );
        }
    }


    private static void failSafely(Id orderId, String message) {
        try {
            Order orderRecord = [SELECT Id, Balance_Link_Log__c FROM Order WHERE Id = :orderId LIMIT 1];
            fail(orderRecord, CARASfscSplitPaymentService.ERROR_UNKNOWN, message);
        } catch (Exception ignoredError) {
            System.debug(LoggingLevel.ERROR, 'Could not record failure for Order ' + orderId + ': ' + ignoredError.getMessage());
        }
    }
}