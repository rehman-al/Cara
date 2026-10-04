public with sharing class CARAOrderCancellationService {

    private static final Set<String> AUTHORISED_STATES = new Set<String>{ 'AUTHORISED', 'AUTHORIZED' };
    private static final Set<String> CAPTURED_STATES = new Set<String>{ 'CAPTURED', 'PURCHASED' };

    public class CancellationResult {
        // True once the SFCC cancel-order callout itself has succeeded. This is
        // the ONLY thing that should gate whether Order.Status moves to
        // Cancelled — refund reporting is a separate, independent outcome and
        // must never roll back a cancellation that already happened.
        public Boolean orderCancelled = false;

        // True when Payment_Status__c indicated a refund needed to be reported
        // back to SFCC (i.e. payment was CAPTURED/PURCHASED). False for
        // AUTHORISED-only orders (nothing was captured, so nothing to refund)
        // and for any other/unrecognised payment status (no refund rule
        // applies, so none is attempted).
        public Boolean refundApplicable = false;

        // Meaningful only when refundApplicable is true.
        public Boolean refundSuccess;

        public List<String> logLines = new List<String>();
    }


    /*
     * Shared by the KYC-rejection automation (CARAKycRejectionQueueable) and
     * the manual Order "Cancel & Refund" action (CARAOrderCancellationController)
     * so there is exactly one place that calls the SFCC cancel/refund APIs and
     * decides void vs refund from Payment_Status__c.
     *
     * Performs callouts only — never any DML. Callers decide what to persist
     * (Case fields, Order.Status, etc.) based on the returned result.
     */
    public static CancellationResult cancelAndSettle(Order orderRecord, String reason, String actor) {
        CancellationResult result = new CancellationResult();
        result.logLines.add('Starting cancellation for Order ' + orderRecord.OrderReferenceNumber + '.');

        CARASfscOrderOpsService.SfscResponse cancelResponse;
        try {
            cancelResponse = CARASfscOrderOpsService.cancelOrder(
                orderRecord.OrderReferenceNumber,
                orderRecord.Storefront_Site_ID__c,
                reason,
                actor,
                'REVERSED'
            );
        } catch (Exception calloutError) {
            result.logLines.add('SFCC cancel call failed: ' + calloutError.getMessage());
            return result;
        }

        if (cancelResponse == null || !cancelResponse.success) {
            result.logLines.add(
                'SFCC cancel call did not succeed: ' +
                (cancelResponse == null ? 'no response' : cancelResponse.statusCode + ' ' + cancelResponse.rawBody)
            );
            return result;
        }

        result.logLines.add('SFCC order cancelled. Response ' + cancelResponse.statusCode + ': ' + cancelResponse.rawBody);

        // The order is cancelled at SFCC from this point on, regardless of
        // what happens with the refund below — a failed or not-applicable
        // refund must never make this look like the cancellation didn't happen.
        result.orderCancelled = true;

        // Email sends are deliberately NOT fired here: each one performs its
        // own DML (via CARAEmailGatewayService's log write), and Apex forbids
        // a callout after DML in the same transaction — the refund-record
        // callout below would silently fail if an email went out first. Every
        // email send is pushed to just before each return below, once no
        // further callout can follow it in that branch.

        // Decide void vs refund from Payment_Status__c.
        // NOTE: placeholder value set (AUTHORISED / CAPTURED, PURCHASED) — per
        // explicit instruction, to be updated once confirmed with the SFCC team.
        String paymentState = String.isBlank(orderRecord.Payment_Status__c)
            ? ''
            : orderRecord.Payment_Status__c.trim().toUpperCase();

        Boolean isAuthorisedOnly = AUTHORISED_STATES.contains(paymentState);
        Boolean isCapturedOrPurchased = CAPTURED_STATES.contains(paymentState);

        if (!isCapturedOrPurchased) {
            // AUTHORISED-only (void already handled by the cancel call above)
            // or any other/unrecognised payment status — no refund is due, and
            // per business rule that must never block the cancellation itself.
            result.logLines.add(
                isAuthorisedOnly
                    ? 'Order cancelled. Payment was only authorised (never captured), so no refund is required.'
                    : 'Order cancelled. Payment_Status__c ("' + orderRecord.Payment_Status__c +
                      '") is not CAPTURED/PURCHASED, so no refund is applicable.'
            );
            sendCancelEmail(orderRecord);
            return result;
        }


        // Payment was captured/purchased — a refund is required. Report it to
        // SFCC now; if this fails the cancellation above still stands.
        result.refundApplicable = true;
        Datetime completedAt = Datetime.now();
        CARASfscOrderOpsService.SfscResponse refundRecordResponse = reportRefundOutcome(
            orderRecord, 'Refund Successful', completedAt, reason, actor
        );

        if (refundRecordResponse == null || !refundRecordResponse.success) {
            result.logLines.add(
                'Order cancelled, but recording the refund back to SFCC failed: ' +
                (refundRecordResponse == null ? 'no response' : refundRecordResponse.statusCode + ' ' + refundRecordResponse.rawBody)
            );
            result.refundSuccess = false;
            sendCancelEmail(orderRecord);
            return result;
        }

        result.logLines.add('Order cancelled and refund recorded back to SFCC.');
        result.refundSuccess = true;
        sendCancelAndRefundEmails(orderRecord, completedAt);
        return result;
    }


    /*
     * Both email sends are best-effort via CARAEmailGatewayService, which
     * never throws — a Marketing Cloud outage must never roll back a
     * cancellation/refund that already happened at SFCC. Neither existing
     * caller (CARAKycRejectionQueueable, CARAOrderCancellationController)
     * previously sent any customer email for these events, so this is
     * purely additive.
     */
    private static void sendCancelEmail(Order orderRecord) {
        if (String.isBlank(orderRecord.Customer_Email__c)) {
            return;
        }
        CARAEmailGatewayService.sendEmail('ORDER_CANCEL', buildCancelEmailRequest(orderRecord));
    }


    /*
     * Sends both together via sendEmails() (one combined DML after both
     * callouts) rather than two separate sendEmail() calls — calling
     * sendEmail() twice in a row would have the second call's callout
     * follow the first call's DML, which Apex forbids.
     */
    private static void sendCancelAndRefundEmails(Order orderRecord, Datetime completedAt) {
        if (String.isBlank(orderRecord.Customer_Email__c)) {
            return;
        }
        CARAEmailGatewayService.sendEmails(
            new List<String>{ 'ORDER_CANCEL', 'ORDER_REFUND' },
            new List<CARAEmailGatewayService.EmailGatewayRequest>{
                buildCancelEmailRequest(orderRecord),
                buildRefundEmailRequest(orderRecord, completedAt)
            }
        );
    }


    private static CARAEmailGatewayService.EmailGatewayRequest buildCancelEmailRequest(Order orderRecord) {
        CARAEmailGatewayService.EmailGatewayRequest request = new CARAEmailGatewayService.EmailGatewayRequest();
        request.source = 'ServiceCloud';
        request.recipientEmail = orderRecord.Customer_Email__c;
        request.relatedRecordId = orderRecord.Id;
        request.data = new Map<String, Object>{
            'FirstName' => firstNameOf(orderRecord),
            'OrderNumber' => orderRecord.OrderReferenceNumber,
            'CancelOrderDate' => Date.today().format(),
            'OrderTotal' => calculateRefundAmount(orderRecord)
        };
        return request;
    }


    private static CARAEmailGatewayService.EmailGatewayRequest buildRefundEmailRequest(Order orderRecord, Datetime completedAt) {
        CARAEmailGatewayService.EmailGatewayRequest request = new CARAEmailGatewayService.EmailGatewayRequest();
        request.source = 'ServiceCloud';
        request.recipientEmail = orderRecord.Customer_Email__c;
        request.relatedRecordId = orderRecord.Id;
        // PaymentMethod (present in the Postman ORDER_REFUND sample) has no
        // verified source field on Order in this org's schema and is left
        // out rather than guessed — Marketing Cloud's template must
        // tolerate its absence.
        request.data = new Map<String, Object>{
            'FirstName' => firstNameOf(orderRecord),
            'OrderNumber' => orderRecord.OrderReferenceNumber,
            'RefundDate' => completedAt.format('yyyy-MM-dd'),
            'RefundAmount' => calculateRefundAmount(orderRecord),
            'RefundReference' => orderRecord.OrderReferenceNumber,
            'RefundTime' => '3 - 5 Working Days'
        };
        return request;
    }


    private static String firstNameOf(Order orderRecord) {
        return String.isNotBlank(orderRecord.Customer_Name_Plain__c) ? orderRecord.Customer_Name_Plain__c : 'Customer';
    }


    private static Decimal calculateRefundAmount(Order orderRecord) {
        return (orderRecord.Product_Total__c == null ? 0 : orderRecord.Product_Total__c)
            + (orderRecord.Shipping_Total_Cost__c == null ? 0 : orderRecord.Shipping_Total_Cost__c)
            + (orderRecord.Tax_Total_Amount__c == null ? 0 : orderRecord.Tax_Total_Amount__c);
    }


    /*
     * refundAmount is approximated as Product_Total__c + Shipping_Total_Cost__c
     * + Tax_Total_Amount__c — the existing order sync (CARAOrderRestService)
     * deserializes payload.orderTotal but never maps it to a Salesforce Order
     * field, so there is no single authoritative "order total" to read.
     * That gap predates this work and is out of scope here.
     */
    private static CARASfscOrderOpsService.SfscResponse reportRefundOutcome(
        Order orderRecord,
        String refundStatus,
        Datetime completedAt,
        String reason,
        String actor
    ) {
        Decimal refundAmount = calculateRefundAmount(orderRecord);

        try {
            return CARASfscOrderOpsService.recordRefund(
                orderRecord.OrderReferenceNumber,
                orderRecord.Storefront_Site_ID__c,
                orderRecord.OrderReferenceNumber,
                refundAmount,
                orderRecord.CurrencyIsoCode__c,
                refundStatus,
                reason,
                Datetime.now(),
                completedAt,
                actor,
                orderRecord.Payment_Status__c
            );
        } catch (Exception calloutError) {
            System.debug(LoggingLevel.ERROR, 'refund-record callout failed: ' + calloutError.getMessage());
            return null;
        }
    }
}