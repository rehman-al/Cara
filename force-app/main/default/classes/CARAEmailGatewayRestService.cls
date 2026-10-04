/*
 * Single SFCC-facing entry point for the centralized Marketing Cloud email
 * gateway — replaces SFCC having to resolve a Salesforce recipient and
 * call Marketing Cloud directly. Same @RestResource/@HttpPost/try-catch
 * shape as CARAOrderRestService; relies on the same platform/Site
 * authentication already protecting the /cara/* endpoint family (no new
 * auth mechanism introduced).
 *
 * Only the 3 SFCC-triggered email types are accepted here — the 5 Service
 * Cloud-triggered ones go through CARAEmailGatewayService directly from
 * internal Apex/Flow automation, never over this REST surface.
 */
@RestResource(urlMapping='/cara/email/send')
global with sharing class CARAEmailGatewayRestService {

    private static final Set<String> SFCC_EMAIL_TYPES = new Set<String>{
        'ORDER_CONFIRMATION', 'DEPOSIT_CONFIRMATION', 'PASSWORD_RESET'
    };

    @HttpPost
    global static void sendEmail() {
        String requestId = generateRequestId();

        try {
            Map<String, Object> payload = deserializePayload();
            String emailType = (String) payload.get('emailType');
            Map<String, Object> recipient = (Map<String, Object>) payload.get('recipient');
            Map<String, Object> data = (Map<String, Object>) payload.get('data');
            String recipientEmail = recipient == null ? null : (String) recipient.get('email');
            String externalId = recipient == null ? null : (String) recipient.get('externalId');

            validate(emailType, recipientEmail, data);

            CARAEmailGatewayService.EmailGatewayRequest request = new CARAEmailGatewayService.EmailGatewayRequest();
            request.source = 'SFCC';
            request.requestId = requestId;
            request.recipientEmail = recipientEmail;
            request.externalId = externalId;
            request.data = data;

            CARAEmailGatewayService.EmailGatewayResult result = CARAEmailGatewayService.sendEmail(emailType, request);
            writeResponse(result.success ? 200 : 400, result, emailType, requestId);

        } catch (IntegrationException validationError) {
            writeResponse(400, errorResult('INVALID_REQUEST', validationError.getMessage()), null, requestId);
        } catch (Exception unexpectedError) {
            System.debug(LoggingLevel.ERROR, 'CARAEmailGatewayRestService unexpected error: ' + unexpectedError.getMessage());
            writeResponse(500, errorResult('UNEXPECTED_ERROR', 'Email could not be sent'), null, requestId);
        }
    }


    /*
     * Manual Map navigation (same approach CARAOrderRestService uses for
     * its own tricky fields) rather than deserializing into a typed inner
     * DTO class — keeps this simple 3-field payload free of any ambiguity
     * around nested custom-type resolution.
     */
    private static Map<String, Object> deserializePayload() {
        if (RestContext.request == null || RestContext.request.requestBody == null) {
            throw new IntegrationException('A JSON request body is required.');
        }
        String requestBody = RestContext.request.requestBody.toString();
        if (String.isBlank(requestBody)) {
            throw new IntegrationException('A JSON request body is required.');
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(requestBody);
        } catch (Exception jsonException) {
            throw new IntegrationException('Invalid JSON payload: ' + jsonException.getMessage());
        }
    }


    private static void validate(String emailType, String recipientEmail, Map<String, Object> data) {
        if (String.isBlank(emailType)) {
            throw new IntegrationException('emailType is required.');
        }
        if (!SFCC_EMAIL_TYPES.contains(emailType)) {
            throw new IntegrationException('Unsupported emailType for this endpoint: ' + emailType);
        }
        if (String.isBlank(recipientEmail)) {
            throw new IntegrationException('recipient.email is required.');
        }
        if (data == null || data.isEmpty()) {
            throw new IntegrationException('data is required.');
        }
    }


    private static CARAEmailGatewayService.EmailGatewayResult errorResult(String errorCode, String message) {
        CARAEmailGatewayService.EmailGatewayResult result = new CARAEmailGatewayService.EmailGatewayResult();
        result.success = false;
        result.errorCode = errorCode;
        result.message = message;
        return result;
    }


    private static String generateRequestId() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 20);
    }


    private static void writeResponse(
        Integer statusCode,
        CARAEmailGatewayService.EmailGatewayResult result,
        String emailType,
        String requestId
    ) {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }

        Map<String, Object> body = new Map<String, Object>{
            'success' => result.success,
            'message' => result.message,
            'requestId' => requestId
        };
        if (result.success) {
            body.put('emailType', emailType);
        } else {
            body.put('errorCode', result.errorCode);
        }

        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }


    private class IntegrationException extends Exception {
    }
}