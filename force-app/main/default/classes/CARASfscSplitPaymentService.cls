/*
 * N-Genius split-payment (deposit + balance) callouts to the SFCC/MRT
 * order-ops endpoints. Deliberately built on top of
 * CARASfscOrderOpsService.callOut(...) rather than a new HTTP stack: same
 * Named Credential (callout:SFSC_Order_Ops), same X-SFSC-Order-Secret
 * header sourced from SFSC_Order_Ops_Setting__c, same
 * success/statusCode/rawBody response shape already used by order
 * cancel/refund. This class only adds the deposit/balance payloads, JSON
 * parsing, and the retry/error-category rules specific to those three
 * actions.
 *
 * Pure callout + parsing — no DML, no notifications. Callers (the
 * Queueables) decide what to persist and when to notify, same separation
 * CARAOrderCancellationService already uses for cancel/refund.
 *
 * Retry count and which status codes are retryable are admin-configurable
 * via Split_Payment_Setting__mdt (see CARASplitPaymentSettings) rather than
 * hardcoded — 400 (payload) and 401 (auth) must never be listed there, and
 * are always surfaced immediately regardless of configuration.
 */
public with sharing class CARASfscSplitPaymentService {

    private static final String DEPOSIT_BASKET_PATH = '/action/sfsc-deposit-basket';
    private static final String DELETE_BASKET_PATH = '/action/sfsc-delete-basket';
    private static final String BALANCE_LINK_PATH = '/action/sfsc-balance-link';

    public static final String ERROR_PAYLOAD = 'PAYLOAD_ERROR';
    public static final String ERROR_AUTH = 'AUTH_ERROR';
    public static final String ERROR_GATEWAY = 'GATEWAY_ERROR';
    public static final String ERROR_UNKNOWN = 'UNKNOWN_ERROR';


    public abstract class BaseResult {
        public Boolean success = false;
        public Integer statusCode;
        public String errorCategory;
        public String errorMessage;
    }

    public class ShippingAddress {
        public String firstName;
        public String lastName;
        public String address1;
        public String city;
        public String postalCode;
        public String countryCode;
        public String phone;
    }

    public class DepositBasketRequest {
        public String customerLogin;
        public String sku;
        public Decimal price;
        public Decimal deposit;
        public ShippingAddress shippingAddress;
        // Custom_Product_Request__c.Name (e.g. "CPR-00042") — the CPR
        // Number SFCC must echo back on the resulting Order so Salesforce
        // can link it without guessing (see CARAOrderSyncService).
        public String cprNumber;
    }

    public class DepositBasketResult extends BaseResult {
        public String basketId;
        public String link;
        public Decimal deposit;
        public Decimal orderTotal;
    }

    public class DeleteBasketResult extends BaseResult {
        public Boolean alreadyGone = false;
    }

    public class BalanceLinkResult extends BaseResult {
        public String link;
        public Decimal remaining;
        public Decimal paid;
        public Boolean alreadyPaid = false;
    }


    /*
     * Link 1 — Deposit. Trigger: Quote/Custom Product Request approval.
     */
    public static DepositBasketResult createDepositBasket(DepositBasketRequest requestData) {
        Map<String, Object> shippingAddressPayload = new Map<String, Object>{
            'firstName' => requestData.shippingAddress?.firstName,
            'lastName' => requestData.shippingAddress?.lastName,
            'address1' => requestData.shippingAddress?.address1,
            'city' => requestData.shippingAddress?.city,
            'postalCode' => requestData.shippingAddress?.postalCode,
            'countryCode' => requestData.shippingAddress?.countryCode,
            'phone' => requestData.shippingAddress?.phone
        };

        Map<String, Object> payload = new Map<String, Object>{
            'customerLogin' => requestData.customerLogin,
            'sku' => requestData.sku,
            'price' => requestData.price,
            'deposit' => requestData.deposit,
            'shippingAddress' => shippingAddressPayload,
            'cprNumber' => requestData.cprNumber
        };

        CARASfscOrderOpsService.SfscResponse response = callOutWithRetry(DEPOSIT_BASKET_PATH, payload);

        DepositBasketResult result = new DepositBasketResult();
        result.statusCode = response.statusCode;
        result.success = response.success;

        if (!response.success) {
            applyErrorCategory(result, response);
            return result;
        }

        Map<String, Object> body = parseBody(response.rawBody);
        if (body == null) {
            result.success = false;
            result.errorCategory = ERROR_PAYLOAD;
            result.errorMessage = 'Deposit basket response could not be parsed as JSON: ' + response.rawBody;
            return result;
        }

        result.basketId = (String) body.get('basketId');
        result.link = (String) body.get('link');
        result.deposit = toDecimal(body.get('deposit'));
        result.orderTotal = toDecimal(body.get('orderTotal'));
        return result;
    }


    /*
     * Cancel Quote (before deposit is paid). Idempotent: a basket the
     * gateway already considers gone (alreadyGone:true, or a 404) is
     * treated as a successful delete.
     */
    public static DeleteBasketResult deleteBasket(String basketId, String customerLogin) {
        Map<String, Object> payload = new Map<String, Object>{
            'basketId' => basketId,
            'customerLogin' => customerLogin
        };

        CARASfscOrderOpsService.SfscResponse response = callOutWithRetry(DELETE_BASKET_PATH, payload);

        DeleteBasketResult result = new DeleteBasketResult();
        result.statusCode = response.statusCode;

        Map<String, Object> body = parseBody(response.rawBody);
        Object alreadyGoneRaw = body == null ? null : body.get('alreadyGone');
        result.alreadyGone = alreadyGoneRaw instanceof Boolean && (Boolean) alreadyGoneRaw;
        result.success = response.success || result.alreadyGone || response.statusCode == 404;

        if (!result.success) {
            applyErrorCategory(result, response);
        }

        return result;
    }


    /*
     * Link 2 — Balance. Trigger: piece ready for delivery.
     */
    public static BalanceLinkResult getBalanceLink(String orderNo, String customerLogin) {
        Map<String, Object> payload = new Map<String, Object>{
            'orderNo' => orderNo,
            'customerLogin' => customerLogin
        };

        CARASfscOrderOpsService.SfscResponse response = callOutWithRetry(BALANCE_LINK_PATH, payload);

        BalanceLinkResult result = new BalanceLinkResult();
        result.statusCode = response.statusCode;
        result.success = response.success;

        if (!response.success) {
            applyErrorCategory(result, response);
            return result;
        }

        Map<String, Object> body = parseBody(response.rawBody);
        if (body == null) {
            result.success = false;
            result.errorCategory = ERROR_PAYLOAD;
            result.errorMessage = 'Balance link response could not be parsed as JSON: ' + response.rawBody;
            return result;
        }

        result.link = (String) body.get('link');
        result.remaining = toDecimal(body.get('remaining'));
        result.paid = toDecimal(body.get('paid'));
        Object alreadyPaidRaw = body.get('alreadyPaid');
        result.alreadyPaid = alreadyPaidRaw instanceof Boolean && (Boolean) alreadyPaidRaw;
        return result;
    }


    /*
     * SFCC/MRT's OCAPI customer login is rate-limited to once per
     * customerLogin every 3 seconds ("Tenant id ... has already performed
     * a login operation ... in the last 3 seconds"). Retrying immediately
     * re-triggers that same login for the same customer and collides with
     * it, so every retry must wait out the window first — otherwise the
     * retry is guaranteed to fail the same way and just burns the attempt.
     */
    private static final Integer OCAPI_LOGIN_BACKOFF_MILLIS = 3500;

    private static CARASfscOrderOpsService.SfscResponse callOutWithRetry(String path, Map<String, Object> payload) {
        CARASfscOrderOpsService.SfscResponse response;
        Exception lastCalloutError;
        Integer maxAttempts = CARASplitPaymentSettings.getMaxRetryAttempts();
        Set<Integer> retryableStatusCodes = CARASplitPaymentSettings.getRetryableStatusCodes();

        for (Integer attempt = 1; attempt <= maxAttempts; attempt++) {
            response = null;
            lastCalloutError = null;

            try {
                response = CARASfscOrderOpsService.callOut(path, payload);
            } catch (Exception calloutError) {
                lastCalloutError = calloutError;
            }

            Boolean isRetryableFailure = (response != null && retryableStatusCodes.contains(response.statusCode))
                || lastCalloutError != null;

            if (!isRetryableFailure || attempt == maxAttempts) {
                break;
            }

            waitOutOcapiLoginWindow();
        }

        if (response == null) {
            // Every attempt raised a callout exception (network/timeout) —
            // surfaced as a synthetic non-2xx response so callers only ever
            // branch on SfscResponse/BaseResult, never on caught exceptions.
            response = new CARASfscOrderOpsService.SfscResponse();
            response.success = false;
            response.statusCode = 0;
            response.rawBody = lastCalloutError != null ? lastCalloutError.getMessage() : 'Unknown callout failure.';
        }

        return response;
    }


    /*
     * Apex has no sleep/delay API — this busy-waits on wall-clock time.
     * Only reached on a retryable failure, at most (maxAttempts - 1)
     * times per callout, so the added CPU time stays well within the
     * governor limit even in the synchronous-Apex paths that call this.
     */
    private static void waitOutOcapiLoginWindow() {
        Long deadline = System.currentTimeMillis() + OCAPI_LOGIN_BACKOFF_MILLIS;
        while (System.currentTimeMillis() < deadline) {
        }
    }


    private static void applyErrorCategory(BaseResult result, CARASfscOrderOpsService.SfscResponse response) {
        if (response.statusCode == 400) {
            result.errorCategory = ERROR_PAYLOAD;
            result.errorMessage = 'SFCC/MRT rejected the request payload (missing fields or invalid JSON): ' + response.rawBody;

        } else if (response.statusCode == 401) {
            result.errorCategory = ERROR_AUTH;
            result.errorMessage = 'SFCC/MRT rejected the request — X-SFSC-Order-Secret mismatch or trusted-system issue.';

        } else if (response.statusCode == 0 || CARASplitPaymentSettings.getRetryableStatusCodes().contains(response.statusCode)) {
            result.errorCategory = ERROR_GATEWAY;
            result.errorMessage = 'SFCC/MRT gateway or network error after retry: ' + response.rawBody;

        } else {
            result.errorCategory = ERROR_UNKNOWN;
            result.errorMessage = 'Unexpected response ' + response.statusCode + ': ' + response.rawBody;
        }
    }


    private static Map<String, Object> parseBody(String rawBody) {
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(rawBody);
        } catch (Exception parseError) {
            return null;
        }
    }


    private static Decimal toDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }
}