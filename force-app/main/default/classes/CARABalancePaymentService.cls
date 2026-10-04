/*
 * Business logic for the inbound balance (second/remaining) payment
 * confirmation callback from SFCC. Identifies the Order by
 * OrderReferenceNumber (the same identifier CARAOrderStatusRestService
 * uses), validates the payload against the Order's existing
 * Balance_Remaining__c, and is idempotent on Balance_Already_Paid__c so a
 * repeated SFCC callback never double-processes a payment.
 *
 * Pure DML, no callouts — Salesforce never calls back out here, it only
 * records what SFCC already told it.
 */
public with sharing class CARABalancePaymentService {

    private static final Set<String> SUCCESS_STATUSES = new Set<String>{ 'SUCCESS', 'COMPLETED', 'PAID' };
    private static final Set<String> FAILURE_STATUSES = new Set<String>{
        'FAILED', 'DECLINED', 'CANCELLED', 'CANCELED', 'INVALID'
    };
    private static final String PENDING_STATUS = 'PENDING';

    private static final String CODE_OK = 'OK';
    private static final String CODE_ALREADY_PROCESSED = 'ALREADY_PROCESSED';
    private static final String CODE_MISSING_REQUIRED_FIELD = 'MISSING_REQUIRED_FIELD';
    private static final String CODE_ORDER_NOT_FOUND = 'ORDER_NOT_FOUND';
    private static final String CODE_AMBIGUOUS_ORDER_REFERENCE = 'AMBIGUOUS_ORDER_REFERENCE';
    private static final String CODE_AMOUNT_MISMATCH = 'AMOUNT_MISMATCH';
    private static final String CODE_UNSUPPORTED_PAYMENT_STATUS = 'UNSUPPORTED_PAYMENT_STATUS';
    private static final String CODE_ORDER_UPDATE_FAILED = 'ORDER_UPDATE_FAILED';

    private static final Decimal AMOUNT_TOLERANCE = 0.01;


    public class ConfirmationRequest {
        public String orderReferenceNumber;
        public String paymentReference;
        public String paymentStatus;
        public Decimal amount;
        public String currencyCode;
        public String paymentTimestamp;
        public String siteId;
    }

    public class ConfirmationResult {
        public Boolean success = false;
        public Boolean alreadyProcessed = false;
        public Boolean paymentProcessed = false;
        public String code;
        public String message;
        public String orderReferenceNumber;
        public Id salesforceOrderId;
        public Decimal balanceRemaining;
    }

    public class ValidationException extends Exception {
    }


    public static ConfirmationResult confirmBalancePayment(ConfirmationRequest requestData) {
        ConfirmationResult result = new ConfirmationResult();

        try {
            validateRequiredFields(requestData);
        } catch (ValidationException validationError) {
            return fail(result, CODE_MISSING_REQUIRED_FIELD, validationError.getMessage());
        }

        result.orderReferenceNumber = requestData.orderReferenceNumber;
        String normalizedStatus = requestData.paymentStatus.trim().toUpperCase();

        Order orderRecord;
        try {
            orderRecord = findOrder(requestData.orderReferenceNumber);
        } catch (ValidationException lookupError) {
            String code = lookupError.getMessage().startsWith('Multiple')
                ? CODE_AMBIGUOUS_ORDER_REFERENCE
                : CODE_ORDER_NOT_FOUND;
            return fail(result, code, lookupError.getMessage());
        }
        result.salesforceOrderId = orderRecord.Id;
        result.balanceRemaining = orderRecord.Balance_Remaining__c;

        if (!SUCCESS_STATUSES.contains(normalizedStatus) && !FAILURE_STATUSES.contains(normalizedStatus) && normalizedStatus != PENDING_STATUS) {
            return fail(result, CODE_UNSUPPORTED_PAYMENT_STATUS, 'Unsupported paymentStatus: ' + requestData.paymentStatus);
        }

        // Idempotency: a balance already marked paid is never reprocessed,
        // regardless of what this callback reports.
        if (orderRecord.Balance_Already_Paid__c) {
            result.success = true;
            result.alreadyProcessed = true;
            result.paymentProcessed = true;
            result.code = CODE_ALREADY_PROCESSED;
            result.message = 'Balance payment was already confirmed for this Order; no changes made.';
            result.balanceRemaining = 0;
            return result;
        }

        if (!SUCCESS_STATUSES.contains(normalizedStatus)) {
            logNonSuccess(orderRecord, normalizedStatus, requestData);
            result.success = true;
            result.paymentProcessed = false;
            result.code = 'PAYMENT_' + normalizedStatus;
            result.message = 'SFCC reported payment status "' + requestData.paymentStatus + '"; Order was not updated.';
            return result;
        }

        if (
            orderRecord.Balance_Remaining__c != null &&
            (orderRecord.Balance_Remaining__c - requestData.amount).abs() > AMOUNT_TOLERANCE
        ) {
            return fail(
                result,
                CODE_AMOUNT_MISMATCH,
                'Payment amount ' + requestData.amount + ' does not match outstanding balance ' + orderRecord.Balance_Remaining__c + '.'
            );
        }

        try {
            applySuccessfulPayment(orderRecord, requestData);
        } catch (Exception updateError) {
            System.debug(
                LoggingLevel.ERROR,
                'Balance payment confirmation failed to update Order ' + requestData.orderReferenceNumber + ': ' + updateError.getMessage()
            );
            return fail(result, CODE_ORDER_UPDATE_FAILED, 'Order could not be updated with the confirmed payment.');
        }

        result.success = true;
        result.paymentProcessed = true;
        result.code = CODE_OK;
        result.message = 'Balance payment confirmed.';
        result.balanceRemaining = 0;
        return result;
    }


    private static void validateRequiredFields(ConfirmationRequest requestData) {
        if (requestData == null) {
            throw new ValidationException('A valid payment confirmation payload is required.');
        }

        List<String> missingFields = new List<String>();
        if (String.isBlank(requestData.orderReferenceNumber)) {
            missingFields.add('orderReferenceNumber');
        }
        if (String.isBlank(requestData.paymentReference)) {
            missingFields.add('paymentReference');
        }
        if (String.isBlank(requestData.paymentStatus)) {
            missingFields.add('paymentStatus');
        }
        if (requestData.amount == null) {
            missingFields.add('amount');
        }
        if (String.isBlank(requestData.currencyCode)) {
            missingFields.add('currencyCode');
        }

        if (!missingFields.isEmpty()) {
            throw new ValidationException('Missing required field(s): ' + String.join(missingFields, ', '));
        }
    }


    private static Order findOrder(String orderReferenceNumber) {
        List<Order> matchingOrders = [
            SELECT Id, OrderReferenceNumber, Balance_Remaining__c, Balance_Already_Paid__c,
                Balance_Link_Status__c, Balance_Link_Log__c, Balance_Payment_Reference__c
            FROM Order
            WHERE OrderReferenceNumber = :orderReferenceNumber
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
        if (matchingOrders.isEmpty()) {
            throw new ValidationException('No Order found with OrderReferenceNumber ' + orderReferenceNumber + '.');
        }
        if (matchingOrders.size() > 1) {
            throw new ValidationException('Multiple Orders use OrderReferenceNumber ' + orderReferenceNumber + '.');
        }
        return matchingOrders[0];
    }


    private static void applySuccessfulPayment(Order orderRecord, ConfirmationRequest requestData) {
        Order updateRecord = new Order(Id = orderRecord.Id);
        updateRecord.Balance_Already_Paid__c = true;
        updateRecord.Balance_Remaining__c = 0;
        updateRecord.Balance_Payment_Reference__c = requestData.paymentReference;
        updateRecord.Balance_Link_Status__c = 'Paid';
        updateRecord.Balance_Link_Log__c = appendLog(
            orderRecord.Balance_Link_Log__c,
            'Balance payment confirmed by SFCC. reference=' + requestData.paymentReference +
                ', amount=' + requestData.amount + ' ' + requestData.currencyCode
        );
        update updateRecord;
    }


    private static void logNonSuccess(Order orderRecord, String normalizedStatus, ConfirmationRequest requestData) {
        Order updateRecord = new Order(Id = orderRecord.Id);
        updateRecord.Balance_Link_Log__c = appendLog(
            orderRecord.Balance_Link_Log__c,
            'Balance payment confirmation received with non-success status ' + normalizedStatus +
                '. reference=' + requestData.paymentReference + ', amount=' + requestData.amount
        );
        update updateRecord;
    }


    private static String appendLog(String existingLog, String logLine) {
        String stamped = Datetime.now().format('yyyy-MM-dd HH:mm:ss') + ' — ' + logLine;
        return String.isBlank(existingLog) ? stamped : existingLog + '\n' + stamped;
    }


    private static ConfirmationResult fail(ConfirmationResult result, String code, String message) {
        result.success = false;
        result.code = code;
        result.message = message;
        return result;
    }
}