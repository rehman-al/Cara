/**
 * Inbound SFCC Order Sync API. Captures the raw payload onto a
 * SFCC_Order_Staging__c row first (so it is never lost even if Order
 * creation fails) and then delegates the actual Account/Order/OrderItem
 * work to CARAOrderSyncService, the same centralized service used by the
 * Retry Sync action (CARAOrderStagingRetryController).
 */
@RestResource(urlMapping='/cara/createOrder')
global with sharing class CARAOrderRestService {

    @HttpPost
    global static void syncOrder() {
        try {
            String requestBody = readRequestBody();
            String orderNo = tryExtractOrderNo(requestBody);

            Id stagingId = CARAOrderSyncService.capturePayload(orderNo, requestBody);
            CARAOrderSyncService.SyncOutcome outcome = CARAOrderSyncService.syncFromStaging(stagingId);

            writeResponse(
                outcome.success ? 200 : 400,
                outcome.success,
                outcome.message,
                outcome.orderId,
                outcome.warnings
            );
        } catch (Exception exceptionRecord) {
            writeResponse(400, false, exceptionRecord.getMessage(), null, new List<String>());
        }
    }

    private static String readRequestBody() {
        if (RestContext.request == null || RestContext.request.requestBody == null) {
            throw new IntegrationException('A JSON request body is required.');
        }
        String requestBody = RestContext.request.requestBody.toString();
        if (String.isBlank(requestBody)) {
            throw new IntegrationException('A JSON request body is required.');
        }
        return requestBody;
    }

    /**
     * Best-effort extraction of orderNo purely to key the staging record.
     * A malformed/unparsable body yields null here — capturePayload() still
     * stores the raw text, and CARAOrderSyncService.syncFromStaging() then
     * surfaces the real parse error onto that staging record as Failed.
     */
    private static String tryExtractOrderNo(String requestBody) {
        try {
            Map<String, Object> rawPayload = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            Object orderNoValue = rawPayload.get('orderNo');
            return orderNoValue == null ? null : String.valueOf(orderNoValue);
        } catch (Exception parseException) {
            return null;
        }
    }

    private static void writeResponse(
        Integer statusCode,
        Boolean success,
        String message,
        Id orderId,
        List<String> warnings
    ) {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }
        ResponseBody responseBody = new ResponseBody();
        responseBody.success = success;
        responseBody.message = message;
        responseBody.orderId = orderId;
        responseBody.warnings = warnings == null ? new List<String>() : new List<String>(warnings);
        responseBody.warnings.sort();

        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(responseBody));
    }

    private class ResponseBody {
        public Boolean success;
        public String message;
        public Id orderId;
        public List<String> warnings;
    }

    private class IntegrationException extends Exception {
    }
}