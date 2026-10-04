public with sharing class CARAOrderCancellationController {

    private static final String SYSTEM_ACTOR = 'SFSC-Manual-CSR';
    private static final String REASON = 'Manual cancellation by CSR';

    public class CancellationException extends Exception {
    }

    public class CancelOrderResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        // True only when the Order was cancelled but a refund that SFCC
        // required could not be recorded — the Order is still Cancelled,
        // but the CSR needs to know the refund needs separate follow-up.
        @AuraEnabled public Boolean refundFailed;
    }


    /*
     * Manual "Cancel & Refund" action on the Order record page. Reuses the
     * exact same CARAOrderCancellationService (and therefore the same
     * CARASfscOrderOpsService callouts) as the automated KYC-rejection path
     * in CARAKycRejectionQueueable — no second integration.
     */
    @AuraEnabled
    public static CancelOrderResult cancelOrder(Id orderId) {
        CancelOrderResult result = new CancelOrderResult();

        try {
            List<Order> orders = [
                SELECT Id, OrderReferenceNumber, Storefront_Site_ID__c, Payment_Status__c,
                       CurrencyIsoCode__c, Product_Total__c, Shipping_Total_Cost__c, Tax_Total_Amount__c, Status,
                       Customer_Email__c, Customer_Name_Plain__c
                FROM Order
                WHERE Id = :orderId
                LIMIT 1
            ];

            if (orders.isEmpty()) {
                throw new CancellationException('Order not found.');
            }

            Order orderRecord = orders[0];

            // Prevent accidental repeated cancellation — no callouts fire at all.
            if (orderRecord.Status == 'Cancelled') {
                result.success = false;
                result.message = 'This Order is already Cancelled. No action was taken.';
                return result;
            }

            CARAOrderCancellationService.CancellationResult cancellation =
                CARAOrderCancellationService.cancelAndSettle(orderRecord, REASON, SYSTEM_ACTOR);

            // Refund success/failure never gates this — only whether the
            // order was actually cancelled at SFCC does.
            if (!cancellation.orderCancelled) {
                result.success = false;
                result.message = String.join(cancellation.logLines, ' ');
                return result;
            }

            update new Order(Id = orderRecord.Id, Status = 'Cancelled');

            Boolean refundFailed = cancellation.refundApplicable && cancellation.refundSuccess != true;
            result.success = true;
            result.refundFailed = refundFailed;
            result.message = refundFailed
                ? 'Order cancelled, but the refund could not be completed: ' + String.join(cancellation.logLines, ' ')
                : 'Order cancelled successfully.';
            return result;
        } catch (CancellationException expectedError) {
            result.success = false;
            result.message = expectedError.getMessage();
            return result;
        } catch (Exception unexpectedError) {
            throw new AuraHandledException(unexpectedError.getMessage());
        }
    }
}