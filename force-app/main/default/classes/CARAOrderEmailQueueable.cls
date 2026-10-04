/*
 * Order Invoice / Order Delivery — fired by a record-triggered Flow on
 * Order.Status (same trigger shape as KYC_Approved_Activate_Order), via
 * CARAOrderEmailStatusHandler. Queued (not called synchronously from the
 * Flow) for the same reason as CARABalanceLinkQueueable: an after-save
 * Flow's DML has already committed, so a same-transaction callout would
 * throw "You have uncommitted work pending".
 *
 * NOTE: the "Invoiced"/"Delivered" Status picklist values have been added
 * to Order.Status (Status Category: Activated). The Order_Status_Email
 * Flow still ships in Draft, so nothing invokes this class in production
 * until the Flow is reviewed and activated.
 */
public with sharing class CARAOrderEmailQueueable implements Queueable, Database.AllowsCallouts {

    private static final Map<String, String> EMAIL_TYPE_BY_STATUS = new Map<String, String>{
        'Invoiced' => 'ORDER_INVOICE',
        'Delivered' => 'ORDER_DELIVERY'
    };

    private List<Id> orderIds;

    public CARAOrderEmailQueueable(List<Id> orderIds) {
        this.orderIds = orderIds;
    }

    public void execute(QueueableContext context) {
        for (Id orderId : orderIds) {
            try {
                process(orderId);
            } catch (Exception unexpectedError) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Order status email failed for ' + orderId + ': ' + unexpectedError.getMessage()
                );
            }
        }
    }


    private static void process(Id orderId) {
        List<Order> orders = [
            SELECT Id, OrderReferenceNumber, Status, Customer_Email__c, Customer_Name_Plain__c, EffectiveDate
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
        if (orders.isEmpty()) {
            return;
        }

        Order orderRecord = orders[0];
        String emailType = resolveEmailType(orderRecord.Status);
        if (emailType == null || String.isBlank(orderRecord.Customer_Email__c)) {
            return;
        }

        CARAEmailGatewayService.EmailGatewayRequest request = new CARAEmailGatewayService.EmailGatewayRequest();
        request.source = 'ServiceCloud';
        request.recipientEmail = orderRecord.Customer_Email__c;
        request.relatedRecordId = orderRecord.Id;
        request.data = buildData(emailType, orderRecord);

        CARAEmailGatewayService.sendEmail(emailType, request);
    }


    /*
     * Pure lookup, pulled out so the mapping itself is also unit-testable
     * in isolation from the SOQL/callout path.
     */
    @TestVisible
    private static String resolveEmailType(String status) {
        return EMAIL_TYPE_BY_STATUS.get(status);
    }


    /*
     * Only fields with a verified source on Order are populated.
     * ORDER_INVOICE's InvoicNumber/TotalAmount/InvoiceDate and
     * ORDER_DELIVERY's EstimatedDelivery/DeliveryAdress (Postman sample
     * attribute names, kept as-is) have no corresponding field on Order in
     * this org and are deliberately left out rather than guessed.
     */
    private static Map<String, Object> buildData(String emailType, Order orderRecord) {
        Map<String, Object> data = new Map<String, Object>{
            'FirstName' => String.isNotBlank(orderRecord.Customer_Name_Plain__c) ? orderRecord.Customer_Name_Plain__c : 'Customer',
            'OrderNumber' => orderRecord.OrderReferenceNumber
        };
        if (emailType == 'ORDER_DELIVERY' && orderRecord.EffectiveDate != null) {
            data.put('OrderDate', orderRecord.EffectiveDate.format());
        }
        return data;
    }
}