public with sharing class CARASfscOrderOpsService {

    private static final String NAMED_CREDENTIAL = 'callout:SFSC_Order_Ops';
    private static final String CANCEL_PATH = '/action/sfsc-order-cancel';
    private static final String REFUND_RECORD_PATH = '/action/sfsc-refund-record';
    private static final String SECRET_HEADER = 'X-SFSC-Order-Secret';

    public class SfscCallException extends Exception {
    }

    public class SfscResponse {
        public Boolean success;
        public Integer statusCode;
        public String rawBody;
    }


    public static SfscResponse cancelOrder(
        String orderNo,
        String siteId,
        String reason,
        String cancelledBy,
        String paymentState
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'orderNo' => orderNo,
            'siteId' => siteId,
            'reason' => reason,
            'cancelCode' => 'CUSTOMERREQUEST',
            'cancelledBy' => cancelledBy,
            'paymentState' => paymentState
        };
        return callOut(CANCEL_PATH, payload);
    }


    public static SfscResponse recordRefund(
        String orderNo,
        String siteId,
        String refundReference,
        Decimal refundAmount,
        String refundCurrency,
        String refundStatus,
        String refundReason,
        Datetime refundRequestedAt,
        Datetime refundCompletedAt,
        String refundInitiatedBy,
        String paymentStatus
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'orderNo' => orderNo,
            'siteId' => siteId,
            'refundReference' => refundReference,
            'refundAmount' => refundAmount,
            'refundCurrency' => refundCurrency,
            'refundStatus' => refundStatus,
            'refundReason' => refundReason,
            'refundRequestedAt' => formatTimestamp(refundRequestedAt),
            'refundInitiatedBy' => refundInitiatedBy,
            'paymentStatus' => paymentStatus,
            'paymentState' => 'REFUNDED'
        };

        // Only present once the refund has actually completed — never sent
        // as a null placeholder for a pending/failed attempt.
        if (refundCompletedAt != null) {
            payload.put('refundCompletedAt', formatTimestamp(refundCompletedAt));
        }

        return callOut(REFUND_RECORD_PATH, payload);
    }


    /*
     * Public so CARASfscSplitPaymentService (N-Genius deposit/balance split
     * payments) can reuse the exact same endpoint, secret-header handling,
     * and success/failure shape rather than re-implementing the callout.
     */
    public static SfscResponse callOut(String path, Map<String, Object> payload) {

        HttpRequest request = new HttpRequest();
        request.setEndpoint(NAMED_CREDENTIAL + path);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader(SECRET_HEADER, getSecret());
        request.setBody(JSON.serialize(payload));
        request.setTimeout(20000);

        HttpResponse httpResponse;

        try {
            httpResponse = new Http().send(request);
        } catch (Exception calloutError) {
            throw new SfscCallException(
                'Callout to ' + path + ' failed: ' + calloutError.getMessage()
            );
        }

        SfscResponse result = new SfscResponse();
        result.statusCode = httpResponse.getStatusCode();
        result.rawBody = httpResponse.getBody();
        result.success = httpResponse.getStatusCode() >= 200
            && httpResponse.getStatusCode() < 300;

        return result;
    }


    private static String getSecret() {

        SFSC_Order_Ops_Setting__c settings = SFSC_Order_Ops_Setting__c.getOrgDefaults();

        if (settings == null || String.isBlank(settings.Order_Ops_Secret__c)) {
            throw new SfscCallException(
                'SFSC Order Ops secret is not configured. Set it via ' +
                'Setup > Custom Settings > SFSC Order Ops Setting > Manage.'
            );
        }

        return settings.Order_Ops_Secret__c;
    }


    private static String formatTimestamp(Datetime timestampValue) {
        return timestampValue == null
            ? null
            : timestampValue.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }
}