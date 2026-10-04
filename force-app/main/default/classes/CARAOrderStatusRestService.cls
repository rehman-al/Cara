@RestResource(urlMapping='/cara/orders/status')
global with sharing class CARAOrderStatusRestService {

    @HttpPost
    global static void updateOrderStatus() {
        try {
            RequestBody payload = deserializePayload();
            validateRequiredFields(payload);

            Order orderRecord = findOrder(payload.orderReferenceNumber);
            String targetStatus = validateStatus(payload.status);
            String statusBefore = orderRecord.Status;

            if (statusBefore == 'Activated' && targetStatus != 'Activated') {
                throw new IntegrationException('Activated Order ' + payload.orderReferenceNumber + ' cannot be moved out of Activated status.');
            }

            Boolean statusChanged = statusBefore != targetStatus;
            if (statusChanged) {
                // OrderHistory captures Before/After Status + timestamp automatically
                // via the Status field's history tracking; no separate history DML needed.
                orderRecord.Status = targetStatus;
                update orderRecord;
            }

            writeResponse(200, true, 'Order status updated successfully.', orderRecord.Id, payload.orderReferenceNumber, statusBefore, targetStatus, statusChanged);
        } catch (IntegrationException exceptionRecord) {
            writeResponse(400, false, exceptionRecord.getMessage(), null, null, null, null, false);
        } catch (Exception exceptionRecord) {
            writeResponse(400, false, 'Unable to update order status: ' + exceptionRecord.getMessage(), null, null, null, null, false);
        }
    }

    private static RequestBody deserializePayload() {
        if (RestContext.request == null || RestContext.request.requestBody == null) {
            throw new IntegrationException('A JSON request body is required.');
        }

        String requestBody = RestContext.request.requestBody.toString();
        if (String.isBlank(requestBody)) {
            throw new IntegrationException('A JSON request body is required.');
        }

        RequestBody payload;
        try {
            payload = (RequestBody) JSON.deserialize(requestBody, RequestBody.class);
        } catch (Exception jsonException) {
            throw new IntegrationException('Invalid JSON payload: ' + jsonException.getMessage());
        }

        if (payload == null) {
            throw new IntegrationException('A valid order status payload is required.');
        }
        return payload;
    }

    private static void validateRequiredFields(RequestBody payload) {
        payload.orderReferenceNumber = payload.orderReferenceNumber == null ? null : payload.orderReferenceNumber.trim();
        payload.status = payload.status == null ? null : payload.status.trim();

        List<String> missingFields = new List<String>();

        if (String.isBlank(payload.orderReferenceNumber)) {
            missingFields.add('orderReferenceNumber');
        }
        if (String.isBlank(payload.status)) {
            missingFields.add('status');
        }

        if (!missingFields.isEmpty()) {
            throw new IntegrationException('Missing required field(s): ' + String.join(missingFields, ', '));
        }
    }

    private static Order findOrder(String orderReferenceNumber) {
        List<Order> matchingOrders = [
            SELECT Id, Status
            FROM Order
            WHERE OrderReferenceNumber = :orderReferenceNumber
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
        if (matchingOrders.isEmpty()) {
            throw new IntegrationException('No Order found with OrderReferenceNumber ' + orderReferenceNumber + '.');
        }
        if (matchingOrders.size() > 1) {
            throw new IntegrationException('Multiple Orders use OrderReferenceNumber ' + orderReferenceNumber + '.');
        }
        return matchingOrders[0];
    }

    /*
     * Validated against the Order.Status picklist as actually configured in the org
     * (describe, not a hardcoded list) so Sandbox/STG stay in sync automatically if
     * the picklist is ever changed via Setup.
     */
    private static String validateStatus(String sourceStatus) {
        for (Schema.PicklistEntry entry : Order.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue().equalsIgnoreCase(sourceStatus)) {
                return entry.getValue();
            }
        }
        throw new IntegrationException('Unsupported order status: ' + sourceStatus);
    }

    private static void writeResponse(
        Integer statusCode,
        Boolean success,
        String message,
        Id orderId,
        String orderReferenceNumber,
        String statusBefore,
        String statusAfter,
        Boolean statusChanged
    ) {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }
        ResponseBody responseBody = new ResponseBody();
        responseBody.success = success;
        responseBody.message = message;
        responseBody.orderId = orderId;
        responseBody.orderReferenceNumber = orderReferenceNumber;
        responseBody.statusBefore = statusBefore;
        responseBody.statusAfter = statusAfter;
        responseBody.statusChanged = statusChanged;

        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(responseBody));
    }

    private class RequestBody {
        public String orderReferenceNumber;
        public String status;
    }

    private class ResponseBody {
        public Boolean success;
        public String message;
        public Id orderId;
        public String orderReferenceNumber;
        public String statusBefore;
        public String statusAfter;
        public Boolean statusChanged;
    }

    private class IntegrationException extends Exception {
    }
}