/*
 * Link 1 (Deposit) — creates the SFCC/MRT basket for a custom-jewelry
 * request once it is approved, saves the returned basketId/link/deposit/
 * orderTotal back onto the Custom_Product_Request__c, and emails the
 * customer the deposit payment link.
 *
 * Runs as its own Queueable (own transaction) so the Flow that fires on
 * Custom_Product_Request__c approval can enqueue this after its own save
 * commits — an after-save Flow's DML has already committed by the time its
 * invocable action runs, and Apex forbids a callout in the same
 * transaction as pending DML. Same reasoning as CARAKycRejectionQueueable.
 */
public with sharing class CARADepositBasketQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> requestIds;

    public CARADepositBasketQueueable(List<Id> requestIds) {
        this.requestIds = requestIds;
    }

    public void execute(QueueableContext context) {
        for (Id requestId : requestIds) {
            try {
                process(requestId);
            } catch (Exception unexpectedError) {
                // One request's failure must never block the others in the same batch.
                System.debug(
                    LoggingLevel.ERROR,
                    'Deposit basket creation failed for ' + requestId + ': ' + unexpectedError.getMessage()
                );
                failSafely(requestId, 'Unexpected error: ' + unexpectedError.getMessage());
            }
        }
    }


    /*
     * Callout first, exactly one DML update for the basket result, then the
     * (non-callout) email, then a second small DML to log the notification
     * outcome — Apex forbids a callout after DML in the same transaction,
     * so nothing here can be reordered to do the callout later.
     */
    private static void process(Id requestId) {
        Custom_Product_Request__c requestRecord = queryRequest(requestId);

        if (requestRecord == null) {
            System.debug(LoggingLevel.ERROR, 'Custom Product Request ' + requestId + ' could not be found.');
            return;
        }

        // Idempotency guard: never re-create a basket that already exists.
        if (String.isNotBlank(requestRecord.Basket_Id__c) && requestRecord.Basket_Status__c == 'Created') {
            return;
        }

        String customerLogin = requestRecord.Case__r != null && requestRecord.Case__r.Contact != null
            ? requestRecord.Case__r.Contact.Email
            : null;
        String sku = requestRecord.Product__r != null ? requestRecord.Product__r.StockKeepingUnit : null;
        Decimal price = requestRecord.Selling_Price__c;

        List<String> missingFields = new List<String>();
        if (String.isBlank(customerLogin)) {
            missingFields.add('customer email (Case Contact)');
        }
        if (String.isBlank(sku)) {
            missingFields.add('Product SKU');
        }
        if (price == null || price <= 0) {
            missingFields.add('Selling Price');
        }

        if (!missingFields.isEmpty()) {
            fail(
                requestRecord,
                CARASfscSplitPaymentService.ERROR_PAYLOAD,
                'Cannot create deposit basket — missing: ' + String.join(missingFields, ', ')
            );
            return;
        }

        Decimal depositAmount = (price * CARASplitPaymentSettings.getDepositPercentage()).setScale(2);

        CARASfscSplitPaymentService.DepositBasketRequest depositRequest =
            new CARASfscSplitPaymentService.DepositBasketRequest();
        depositRequest.customerLogin = customerLogin;
        depositRequest.sku = sku;
        depositRequest.price = price;
        depositRequest.deposit = depositAmount;
        depositRequest.shippingAddress = buildShippingAddress(requestRecord.Case__r.Contact);

        CARASfscSplitPaymentService.DepositBasketResult result =
            CARASfscSplitPaymentService.createDepositBasket(depositRequest);

        if (!result.success) {
            fail(requestRecord, result.errorCategory, result.errorMessage);
            return;
        }

        requestRecord.Basket_Id__c = result.basketId;
        requestRecord.Deposit_Link__c = result.link;
        requestRecord.Deposit_Amount__c = result.deposit != null ? result.deposit : depositAmount;
        requestRecord.Order_Total__c = result.orderTotal;
        requestRecord.Basket_Status__c = 'Created';
        appendLog(requestRecord, 'Deposit basket created. basketId=' + result.basketId);
        update requestRecord;

        // Best-effort side effect after the basket has already been
        // committed — a failed send must never undo the basket creation.
        CARASplitPaymentNotificationService.NotificationOutcome notifyOutcome =
            CARASplitPaymentNotificationService.sendDepositLink(
                requestRecord.Case__r.Contact,
                requestRecord.Name,
                requestRecord.Deposit_Amount__c,
                requestRecord.Deposit_Link__c
            );

        appendLogAndSave(requestRecord.Id, 'Deposit link notification: ' + notifyOutcome.detail);
    }


    private static CARASfscSplitPaymentService.ShippingAddress buildShippingAddress(Contact customerContact) {
        CARASfscSplitPaymentService.ShippingAddress address = new CARASfscSplitPaymentService.ShippingAddress();

        if (customerContact == null) {
            return address;
        }

        address.firstName = customerContact.FirstName;
        address.lastName = customerContact.LastName;
        address.address1 = customerContact.MailingStreet;
        address.city = customerContact.MailingCity;
        address.postalCode = customerContact.MailingPostalCode;
        // State/country picklists are not enabled in this org (no
        // MailingCountryCode field exists) — MailingCountry is passed
        // through as-is and must already hold an ISO country code.
        address.countryCode = customerContact.MailingCountry;
        address.phone = customerContact.Phone;

        return address;
    }


    private static Custom_Product_Request__c queryRequest(Id requestId) {
        List<Custom_Product_Request__c> records = [
            SELECT
                Id, Name, Selling_Price__c, Basket_Id__c, Basket_Status__c, Basket_Log__c,
                Product__c, Product__r.StockKeepingUnit,
                Case__c,
                Case__r.Contact.Id, Case__r.Contact.Email, Case__r.Contact.FirstName, Case__r.Contact.LastName,
                Case__r.Contact.Phone, Case__r.Contact.MailingStreet, Case__r.Contact.MailingCity,
                Case__r.Contact.MailingPostalCode, Case__r.Contact.MailingCountry
            FROM Custom_Product_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }


    private static void fail(Custom_Product_Request__c requestRecord, String errorCategory, String errorMessage) {
        requestRecord.Basket_Status__c = 'Error';
        appendLog(requestRecord, '[' + errorCategory + '] ' + errorMessage);
        update requestRecord;
    }


    private static void appendLog(Custom_Product_Request__c requestRecord, String logLine) {
        String stamped = Datetime.now().format('yyyy-MM-dd HH:mm:ss') + ' — ' + logLine;
        requestRecord.Basket_Log__c = String.isBlank(requestRecord.Basket_Log__c)
            ? stamped
            : requestRecord.Basket_Log__c + '\n' + stamped;
    }


    private static void appendLogAndSave(Id requestId, String logLine) {
        try {
            Custom_Product_Request__c requestRecord = [
                SELECT Id, Basket_Log__c FROM Custom_Product_Request__c WHERE Id = :requestId LIMIT 1
            ];
            appendLog(requestRecord, logLine);
            update requestRecord;
        } catch (Exception ignoredError) {
            System.debug(
                LoggingLevel.ERROR,
                'Could not append notification outcome for ' + requestId + ': ' + ignoredError.getMessage()
            );
        }
    }


    private static void failSafely(Id requestId, String message) {
        try {
            Custom_Product_Request__c requestRecord = [
                SELECT Id, Basket_Log__c FROM Custom_Product_Request__c WHERE Id = :requestId LIMIT 1
            ];
            fail(requestRecord, CARASfscSplitPaymentService.ERROR_UNKNOWN, message);
        } catch (Exception ignoredError) {
            System.debug(LoggingLevel.ERROR, 'Could not record failure for ' + requestId + ': ' + ignoredError.getMessage());
        }
    }
}