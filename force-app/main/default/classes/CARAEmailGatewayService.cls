/*
 * Centralized Marketing Cloud email gateway. Single entry point for both
 * SFCC (via CARAEmailGatewayRestService) and internal Service Cloud
 * automation (Order cancellation/refund, Order status Flow, etc.) so there
 * is exactly one place that resolves a recipient, picks a Send Definition,
 * builds the Marketing Cloud payload, and calls out.
 *
 * Never throws back to the caller — a send failure is reported in the
 * returned EmailGatewayResult, same best-effort contract as
 * CARASplitPaymentNotificationService, so a Flow/Queueable trigger can
 * never fail its own transaction because an email didn't go out.
 */
public with sharing class CARAEmailGatewayService {

    private static final Set<String> KNOWN_EMAIL_TYPES = new Set<String>{
        'ORDER_CONFIRMATION', 'DEPOSIT_CONFIRMATION', 'PASSWORD_RESET',
        'ORDER_CANCEL', 'ORDER_REFUND', 'ORDER_INVOICE', 'ORDER_DELIVERY', 'ORDER_APPOINTMENT'
    };

    public class EmailGatewayRequest {
        public String source;          // 'SFCC' or 'ServiceCloud'
        public String recipientEmail;
        public String externalId;      // optional SFCC customerId / Account.External_ID__c
        public Id relatedRecordId;     // optional Order/Case/etc. this send relates to
        public String requestId;       // optional caller-supplied correlation id
        public Map<String, Object> data;
    }

    public class EmailGatewayResult {
        public Boolean success = false;
        public String message;
        public String errorCode;
        public String requestId;
    }

    private class EmailGatewayException extends Exception {
    }

    private class RecipientContext {
        private String email;
        private Id contactId;
    }


    public static EmailGatewayResult sendEmail(String emailType, EmailGatewayRequest request) {
        return sendEmails(new List<String>{ emailType }, new List<EmailGatewayRequest>{ request })[0];
    }


    /*
     * Sends any number of emails in one call, performing every Marketing
     * Cloud callout FIRST and exactly one combined DML (the log upsert) at
     * the very end — Apex forbids a callout after a DML statement in the
     * same transaction, so sending two emails back to back (e.g. Order
     * Cancel followed by Order Refund from CARAOrderCancellationService)
     * would otherwise silently break the second send's callout. Each
     * request still gets its own independent EmailGatewayResult; one
     * entry failing never affects the others.
     */
    public static List<EmailGatewayResult> sendEmails(List<String> emailTypes, List<EmailGatewayRequest> requests) {
        List<EmailGatewayResult> results = new List<EmailGatewayResult>();
        List<Email_Gateway_Log__c> logsToSave = new List<Email_Gateway_Log__c>();

        for (Integer i = 0; i < emailTypes.size(); i++) {
            String emailType = emailTypes[i];
            EmailGatewayRequest request = requests[i];

            EmailGatewayResult result = new EmailGatewayResult();
            result.requestId = (request != null && String.isNotBlank(request.requestId))
                ? request.requestId
                : generateRequestId();

            try {
                if (String.isBlank(emailType) || !KNOWN_EMAIL_TYPES.contains(emailType)) {
                    throw new EmailGatewayException('UNSUPPORTED_EMAIL_TYPE|Unsupported email type: ' + emailType);
                }
                if (request == null || String.isBlank(request.recipientEmail)) {
                    throw new EmailGatewayException('RECIPIENT_REQUIRED|A recipient email is required.');
                }
                if (request.data == null || request.data.isEmpty()) {
                    throw new EmailGatewayException('DATA_REQUIRED|Template data is required.');
                }

                Email_Notification_Setting__mdt config = Email_Notification_Setting__mdt.getInstance(emailType);
                if (config == null || config.Active__c != true || String.isBlank(config.Send_Definition_Id__c)) {
                    throw new EmailGatewayException(
                        'EMAIL_TYPE_NOT_CONFIGURED|' + emailType + ' is not configured with a Send Definition yet.'
                    );
                }

                RecipientContext recipient = resolveRecipient(request.recipientEmail, request.externalId);

                // Confirmed against the live actions360 API: individualId is
                // mandatory on every request (not optional, despite the name
                // suggesting otherwise) — Marketing Cloud rejects a payload
                // without it with HTTP 400 "'individualId' field is required".
                // A Contact must therefore be resolvable; there is no valid
                // email-only fallback.
                if (recipient.contactId == null) {
                    throw new EmailGatewayException(
                        'RECIPIENT_NOT_FOUND|No Contact could be resolved for ' + recipient.email +
                        ' — Marketing Cloud requires a resolvable individualId.'
                    );
                }

                String idempotencyKey = emailType + ':' + firstNonBlank(
                    request.requestId,
                    request.relatedRecordId == null ? null : String.valueOf(request.relatedRecordId),
                    recipient.email
                );

                if (alreadySentSuccessfully(idempotencyKey)) {
                    result.success = true;
                    result.message = 'Email request already processed.';
                    results.add(result);
                    continue;
                }

                Map<String, Object> payload = buildPayload(config, recipient, request.data);

                Email_Gateway_Log__c logRecord = new Email_Gateway_Log__c(
                    Idempotency_Key__c = idempotencyKey,
                    Email_Type__c = emailType,
                    Source__c = String.isBlank(request.source) ? 'ServiceCloud' : request.source,
                    Recipient_Email__c = recipient.email,
                    Individual_Id__c = recipient.contactId,
                    Send_Definition_Id__c = config.Send_Definition_Id__c,
                    Related_Record_Id__c = request.relatedRecordId == null ? null : String.valueOf(request.relatedRecordId),
                    Request_Id__c = result.requestId
                );

                CARAMarketingCloudCalloutService.McResponse mcResponse;
                try {
                    mcResponse = CARAMarketingCloudCalloutService.send(config.Send_Definition_Id__c, payload);
                } catch (Exception calloutError) {
                    logRecord.Success__c = false;
                    logRecord.Error_Message__c = 'Callout failed: ' + calloutError.getMessage();
                    logsToSave.add(logRecord);
                    result.success = false;
                    result.errorCode = 'MC_CALLOUT_FAILED';
                    result.message = 'Email could not be sent';
                    results.add(result);
                    continue;
                }

                logRecord.Success__c = mcResponse.success;
                logRecord.HTTP_Status__c = mcResponse.statusCode;
                if (!mcResponse.success) {
                    logRecord.Error_Message__c = 'Marketing Cloud returned HTTP ' + mcResponse.statusCode;
                }
                logsToSave.add(logRecord);

                result.success = mcResponse.success;
                result.message = mcResponse.success ? 'Email request accepted' : 'Email could not be sent';
                result.errorCode = mcResponse.success ? null : 'MC_HTTP_' + mcResponse.statusCode;
                results.add(result);

            } catch (EmailGatewayException gatewayError) {
                List<String> parts = gatewayError.getMessage().split('\\|', 2);
                result.success = false;
                result.errorCode = parts[0];
                result.message = parts.size() > 1 ? parts[1] : 'Email could not be sent';
                results.add(result);
            } catch (Exception unexpectedError) {
                System.debug(LoggingLevel.ERROR, 'CARAEmailGatewayService unexpected error: ' + unexpectedError.getMessage());
                result.success = false;
                result.errorCode = 'UNEXPECTED_ERROR';
                result.message = 'Email could not be sent';
                results.add(result);
            }
        }

        saveLogs(logsToSave);
        return results;
    }


    /*
     * Read-only lookup, reusing the email/externalId resolution convention
     * from CARAOrderRestService.syncCustomer() — this service never
     * creates or updates Contact/Account. A miss is treated as
     * RECIPIENT_NOT_FOUND by the caller above (Marketing Cloud requires
     * individualId on every send).
     */
    private static RecipientContext resolveRecipient(String email, String externalId) {
        RecipientContext context = new RecipientContext();
        context.email = email.trim().toLowerCase();

        List<Contact> matches = [
            SELECT Id FROM Contact WHERE Email = :context.email ORDER BY CreatedDate ASC LIMIT 1
        ];
        if (matches.isEmpty() && String.isNotBlank(externalId)) {
            matches = [
                SELECT Id FROM Contact WHERE Account.External_ID__c = :externalId ORDER BY CreatedDate ASC LIMIT 1
            ];
        }
        if (!matches.isEmpty()) {
            context.contactId = matches[0].Id;
        }
        return context;
    }


    /*
     * Preserves the exact two payload shapes in the Postman collection —
     * {attributes: {<WrapperName>: {...}}} for ORDER_CONFIRMATION/
     * DEPOSIT_CONFIRMATION, {attributes: {"$content": {...}}} for the rest.
     * No attribute is ever renamed.
     */
    private static Map<String, Object> buildPayload(
        Email_Notification_Setting__mdt config,
        RecipientContext recipient,
        Map<String, Object> data
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('to', recipient.email);
        payload.put('individualId', recipient.contactId);

        String wrapperName = String.isBlank(config.Attribute_Wrapper_Name__c)
            ? '$content'
            : config.Attribute_Wrapper_Name__c;

        payload.put('attributes', new Map<String, Object>{ wrapperName => data });
        return payload;
    }


    /*
     * WITH SYSTEM_MODE — Email_Gateway_Log__c is purely Apex-managed
     * infrastructure; brand-new custom fields carry no FLS grants to any
     * profile by default, and this read must succeed regardless of which
     * user/integration context triggered the send (same reasoning as
     * saveLog()'s SYSTEM_MODE write).
     */
    private static Boolean alreadySentSuccessfully(String idempotencyKey) {
        for (Email_Gateway_Log__c existing : [
            SELECT Id FROM Email_Gateway_Log__c
            WHERE Idempotency_Key__c = :idempotencyKey AND Success__c = true
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            return true;
        }
        return false;
    }


    /*
     * Upsert-by-external-id so a retried business event updates the same
     * log row in place (no duplicate rows) while a genuinely new attempt
     * after an earlier failure can still go through — only a row already
     * marked Success__c is treated as "already sent" above.
     *
     * SYSTEM_MODE because this is infrastructure logging triggered from
     * wildly different user contexts (SFCC's integration user, a CSR's
     * manual cancel action, an automated Queueable) — none of which should
     * need CRUD/FLS on Email_Gateway_Log__c just for the gateway to record
     * its own outcome, same reasoning as CARAOrderRestService's
     * SYSTEM_MODE PricebookEntry update.
     */
    private static void saveLogs(List<Email_Gateway_Log__c> logsToSave) {
        if (logsToSave.isEmpty()) {
            return;
        }
        try {
            Database.upsert(logsToSave, Email_Gateway_Log__c.Idempotency_Key__c, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception dmlError) {
            System.debug(LoggingLevel.ERROR, 'Failed to write Email_Gateway_Log__c: ' + dmlError.getMessage());
        }
    }


    private static String generateRequestId() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 20);
    }


    private static String firstNonBlank(String firstValue, String secondValue, String thirdValue) {
        if (!String.isBlank(firstValue)) {
            return firstValue;
        }
        if (!String.isBlank(secondValue)) {
            return secondValue;
        }
        return thirdValue;
    }
}