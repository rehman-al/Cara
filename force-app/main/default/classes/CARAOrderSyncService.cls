/**
 * Centralized Order Sync service. Reads a staged SFCC payload from a
 * SFCC_Order_Staging__c row, creates/updates the Account, Contact, Order,
 * OrderItem, Shipment, Payment and CardPaymentMethod records, and writes the
 * outcome back onto the staging row. Used by both CARAOrderRestService (the
 * inbound /cara/createOrder API) and CARAOrderStagingRetryController (the
 * manual Retry Sync action), so both paths share one implementation.
 */
public with sharing class CARAOrderSyncService {
    private static final String ORDER_STATUS_DRAFT = 'Draft';
    private static final String PAYMENT_STATUS_PENDING = 'Pending';
    private static final String PAYMENT_TYPE_SALE = 'Sale';
    private static final String PROCESSING_MODE_EXTERNAL = 'External';
    private static final Map<String, Decimal> KYC_ORDER_TOTAL_THRESHOLD_BY_CURRENCY = new Map<String, Decimal>{
        'AED' => 50000,
        'GBP' => 20000
    };

    private static final String STATUS_RECEIVED = 'Received';
    private static final String STATUS_SYNCING = 'Syncing';
    private static final String STATUS_SYNCED = 'Synced';
    private static final String STATUS_FAILED = 'Failed';

    public class SyncOutcome {
        public Boolean success;
        public String message;
        public Id orderId;
        public List<String> warnings;
    }

    public class SyncInProgressException extends Exception {
    }

    public class IntegrationException extends Exception {
    }

    private class CatalogContext {
        private Id pricebookId;
        private Map<String, Product2> productByCode;
        private Map<Id, PricebookEntry> pricebookEntryByProductId;
    }

    private class CustomerContext {
        private Account accountRecord;
        private Contact contactRecord;
    }

    /**
     * Persists the raw inbound payload to a staging row, keyed on the SFCC
     * order number so a repeat API call for the same order reuses the same
     * row instead of creating a duplicate. Called before any validation so
     * the payload is never lost even if it later fails to sync.
     */
    public static Id capturePayload(String orderNo, String rawPayload) {
        if (String.isBlank(orderNo)) {
            SFCC_Order_Staging__c stagingRecord = new SFCC_Order_Staging__c(
                Order_Payload__c = rawPayload,
                Sync_Status__c = STATUS_RECEIVED
            );
            insert stagingRecord;
            return stagingRecord.Id;
        }

        List<SFCC_Order_Staging__c> existingRows = [
            SELECT Id
            FROM SFCC_Order_Staging__c
            WHERE SFCC_Order_Number__c = :orderNo
            LIMIT 1
        ];
        if (!existingRows.isEmpty()) {
            update new SFCC_Order_Staging__c(Id = existingRows[0].Id, Order_Payload__c = rawPayload);
            return existingRows[0].Id;
        }

        SFCC_Order_Staging__c stagingRecord = new SFCC_Order_Staging__c(
            SFCC_Order_Number__c = orderNo,
            Order_Payload__c = rawPayload,
            Sync_Status__c = STATUS_RECEIVED
        );
        insert stagingRecord;
        return stagingRecord.Id;
    }

    /**
     * Processes (or re-processes) one staging row. Row-locks it first so two
     * overlapping requests for the same staging record (a retry click racing
     * a resent API call, or two retry clicks) serialize instead of both
     * creating/duplicating the Order: the second caller's SELECT ... FOR
     * UPDATE blocks until the first transaction commits, then observes the
     * final Synced/Failed status rather than acting on stale data.
     */
    public static SyncOutcome syncFromStaging(Id stagingId) {
        List<SFCC_Order_Staging__c> lockedRows = [
            SELECT Id, Sync_Status__c, Retry_Count__c, Order_Payload__c, Salesforce_Order__c, Last_Sync_Attempt__c
            FROM SFCC_Order_Staging__c
            WHERE Id = :stagingId
            FOR UPDATE
        ];
        if (lockedRows.isEmpty()) {
            throw new IntegrationException('Staging record not found.');
        }
        SFCC_Order_Staging__c staging = lockedRows[0];

        if (staging.Sync_Status__c == STATUS_SYNCED) {
            SyncOutcome alreadySynced = new SyncOutcome();
            alreadySynced.success = true;
            alreadySynced.orderId = staging.Salesforce_Order__c;
            alreadySynced.message = 'Order already synchronized.';
            alreadySynced.warnings = new List<String>();
            return alreadySynced;
        }
        if (staging.Sync_Status__c == STATUS_SYNCING) {
            throw new SyncInProgressException('This order is currently syncing. Please try again shortly.');
        }

        // The very first attempt (Last_Sync_Attempt__c still null) is not a
        // retry; every attempt after that increments Retry_Count__c.
        Boolean isRetryAttempt = staging.Last_Sync_Attempt__c != null;
        Decimal nextRetryCount = (staging.Retry_Count__c == null ? 0 : staging.Retry_Count__c) + (isRetryAttempt ? 1 : 0);

        update new SFCC_Order_Staging__c(
            Id = staging.Id,
            Sync_Status__c = STATUS_SYNCING,
            Last_Sync_Attempt__c = Datetime.now(),
            Retry_Count__c = nextRetryCount
        );

        Savepoint orderDataSavepoint = Database.setSavepoint();
        try {
            CARAOrderPayload payload = parsePayload(staging.Order_Payload__c);
            validateRequiredFields(payload);

            CatalogContext catalog = resolveCatalog(payload.productItems);
            CustomerContext customer = syncCustomer(payload);
            Order orderRecord = syncOrderRecord(payload, customer.accountRecord.Id, catalog.pricebookId);

            ensurePricebookEntries(catalog, payload.productItems);
            syncOrderItems(orderRecord.Id, payload.productItems, catalog);

            Set<String> warnings = new Set<String>();
            syncShipments(payload, warnings);
            syncPayments(payload, customer, orderRecord, warnings);

            update new SFCC_Order_Staging__c(
                Id = staging.Id,
                Sync_Status__c = STATUS_SYNCED,
                Salesforce_Order__c = orderRecord.Id,
                Last_Successful_Sync__c = Datetime.now(),
                Sync_Error__c = null
            );

            SyncOutcome outcome = new SyncOutcome();
            outcome.success = true;
            outcome.orderId = orderRecord.Id;
            outcome.message = 'Order synchronized successfully.';
            outcome.warnings = new List<String>(warnings);
            return outcome;
        } catch (Exception syncException) {
            Database.rollback(orderDataSavepoint);
            String errorMessage = truncateError(syncException.getMessage());
            update new SFCC_Order_Staging__c(
                Id = staging.Id,
                Sync_Status__c = STATUS_FAILED,
                Sync_Error__c = errorMessage
            );

            SyncOutcome outcome = new SyncOutcome();
            outcome.success = false;
            outcome.message = errorMessage;
            outcome.warnings = new List<String>();
            return outcome;
        }
    }

    private static String truncateError(String message) {
        if (message == null) {
            return null;
        }
        return message.length() > 32000 ? message.substring(0, 32000) : message;
    }

    private static CARAOrderPayload parsePayload(String requestBody) {
        if (String.isBlank(requestBody)) {
            throw new IntegrationException('A JSON request body is required.');
        }

        CARAOrderPayload payload;
        try {
            Map<String, Object> payloadValues = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            if (payloadValues.containsKey('currency')) {
                payloadValues.put('currencyCode', payloadValues.remove('currency'));
            }
            if (payloadValues.containsKey('notes')) {
                Object notesValue = payloadValues.remove('notes');
                String normalizedNotes = null;
                if (notesValue instanceof String) {
                    normalizedNotes = (String) notesValue;
                } else if (notesValue != null) {
                    String serializedNotes = JSON.serialize(notesValue);
                    normalizedNotes = serializedNotes == '{}' || serializedNotes == '[]'
                        ? null
                        : serializedNotes;
                }
                payload = (CARAOrderPayload) JSON.deserialize(
                    JSON.serialize(payloadValues),
                    CARAOrderPayload.class
                );
                payload.notes = normalizedNotes;
            } else {
                payload = (CARAOrderPayload) JSON.deserialize(
                    JSON.serialize(payloadValues),
                    CARAOrderPayload.class
                );
            }
        } catch (Exception jsonException) {
            throw new IntegrationException('Invalid JSON payload: ' + jsonException.getMessage());
        }

        if (payload == null) {
            throw new IntegrationException('A valid order payload is required.');
        }
        return payload;
    }

    private static void validateRequiredFields(CARAOrderPayload payload) {
        List<String> missingFields = new List<String>();

        if (String.isBlank(payload.orderNo)) {
            missingFields.add('orderNo');
        }
        if (String.isBlank(payload.status)) {
            missingFields.add('status');
        }
        if (String.isBlank(payload.currencyCode)) {
            missingFields.add('currency');
        }
        if (payload.customerInfo == null || String.isBlank(payload.customerInfo.email)) {
            missingFields.add('customerInfo.email');
        }

        if (!missingFields.isEmpty()) {
            throw new IntegrationException('Missing required field(s): ' + String.join(missingFields, ', '));
        }
    }

    private static CatalogContext resolveCatalog(List<CARAOrderPayload.ProductItem> productItems) {
        CatalogContext context = new CatalogContext();
        context.productByCode = new Map<String, Product2>();
        context.pricebookEntryByProductId = new Map<Id, PricebookEntry>();

        if (productItems == null || productItems.isEmpty()) {
            return context;
        }

        Set<String> productCodes = new Set<String>();
        Set<String> lineItemKeys = new Set<String>();
        Map<String, CARAOrderPayload.ProductItem> sampleItemByProductCode = new Map<String, CARAOrderPayload.ProductItem>();
        for (CARAOrderPayload.ProductItem item : productItems) {
            if (item == null || String.isBlank(item.itemId) || String.isBlank(item.productId)) {
                throw new IntegrationException('Each productItems entry requires itemId and productId.');
            }
            if (item.quantity == null || item.quantity <= 0) {
                throw new IntegrationException('Product item ' + item.itemId + ' requires a quantity greater than zero.');
            }
            if (!lineItemKeys.add(item.itemId)) {
                throw new IntegrationException('Duplicate product itemId in payload: ' + item.itemId);
            }
            productCodes.add(item.productId);
            if (!sampleItemByProductCode.containsKey(item.productId)) {
                sampleItemByProductCode.put(item.productId, item);
            }
        }

        List<Product2> productsToActivate = new List<Product2>();
        for (Product2 productRecord : [
            SELECT Id, Name, ProductCode, IsActive
            FROM Product2
            WHERE ProductCode IN :productCodes
        ]) {
            if (context.productByCode.containsKey(productRecord.ProductCode)) {
                throw new IntegrationException('Multiple Product2 records use ProductCode ' + productRecord.ProductCode + '.');
            }
            if (!productRecord.IsActive) {
                productRecord.IsActive = true;
                productsToActivate.add(productRecord);
            }
            context.productByCode.put(productRecord.ProductCode, productRecord);
        }

        List<Product2> productsToInsert = new List<Product2>();
        for (String productCode : productCodes) {
            if (!context.productByCode.containsKey(productCode)) {
                CARAOrderPayload.ProductItem sampleItem = sampleItemByProductCode.get(productCode);
                productsToInsert.add(
                    new Product2(
                        Name = firstNonBlank(sampleItem.productName, sampleItem.itemText, productCode),
                        ProductCode = productCode,
                        IsActive = true
                    )
                );
            }
        }

        if (!productsToActivate.isEmpty()) {
            update productsToActivate;
        }
        if (!productsToInsert.isEmpty()) {
            insert productsToInsert;
            for (Product2 productRecord : productsToInsert) {
                context.productByCode.put(productRecord.ProductCode, productRecord);
            }
        }

        List<Pricebook2> standardPricebooks = [
            SELECT Id, IsActive
            FROM Pricebook2
            WHERE IsStandard = true
            LIMIT 1
        ];
        if (standardPricebooks.isEmpty()) {
            throw new IntegrationException('The standard Salesforce price book could not be found.');
        }
        if (!standardPricebooks[0].IsActive) {
            standardPricebooks[0].IsActive = true;
            update standardPricebooks[0];
        }
        context.pricebookId = standardPricebooks[0].Id;

        Set<Id> productIds = new Set<Id>();
        for (Product2 productRecord : context.productByCode.values()) {
            productIds.add(productRecord.Id);
        }
        Id standardPricebookId = context.pricebookId;
        for (PricebookEntry entry : [
            SELECT Id, Product2Id, UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
            AND Product2Id IN :productIds
            AND IsActive = true
        ]) {
            context.pricebookEntryByProductId.put(entry.Product2Id, entry);
        }

        return context;
    }

    /**
     * Resolves the Account/Contact for the order. Guest and logged-in
     * orders go through the exact same path: resolution is keyed on
     * customerInfo.email (required for every order), and a guest order with
     * no matching Contact simply creates a fresh Account+Contact flagged
     * Is_Guest__c — there is no dependency on a pre-existing Account,
     * Contact or User for a guest checkout.
     */
    private static CustomerContext syncCustomer(CARAOrderPayload payload) {
        String emailAddress = payload.customerInfo.email.trim().toLowerCase();
        List<Contact> matchingContacts = [
            SELECT Id, AccountId, Email
            FROM Contact
            WHERE Email = :emailAddress
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
        if (matchingContacts.size() > 1) {
            throw new IntegrationException('Multiple contacts use customer email ' + emailAddress + '.');
        }

        Contact contactRecord = matchingContacts.isEmpty() ? null : matchingContacts[0];
        Account accountRecord;

        if (contactRecord != null && contactRecord.AccountId != null) {
            Id contactAccountId = contactRecord.AccountId;
            accountRecord = [
                SELECT Id, External_ID__c
                FROM Account
                WHERE Id = :contactAccountId
                LIMIT 1
            ];
            if (
                payload.guest != true &&
                !String.isBlank(payload.customerInfo.customerId) &&
                !String.isBlank(accountRecord.External_ID__c) &&
                accountRecord.External_ID__c != payload.customerInfo.customerId
            ) {
                throw new IntegrationException('Customer email and customerId resolve to different accounts.');
            }
            // Guest checkouts get a fresh, synthetic customerId from SFCC on every
            // session even when the same person (same email) checks out again, so
            // a customerId mismatch is expected and not a real identity conflict.
            // applyAccountValues() below will refresh External_ID__c to the latest
            // guest id for this account; only registered (non-guest) customers are
            // held to a stable customerId.
        } else if (!String.isBlank(payload.customerInfo.customerId)) {
            String customerId = payload.customerInfo.customerId;
            List<Account> matchingAccounts = [
                SELECT Id, External_ID__c
                FROM Account
                WHERE External_ID__c = :customerId
                ORDER BY CreatedDate ASC
                LIMIT 2
            ];
            if (matchingAccounts.size() > 1) {
                throw new IntegrationException('Multiple accounts use customerId ' + payload.customerInfo.customerId + '.');
            }
            accountRecord = matchingAccounts.isEmpty() ? null : matchingAccounts[0];
        }
        // No Contact match and no (or blank) customerId — e.g. a first-time
        // guest checkout — falls through with accountRecord still null, and
        // a brand new Account+Contact is created for this order below.

        Boolean isNewAccount = accountRecord == null;
        if (isNewAccount) {
            accountRecord = new Account();
        }
        applyAccountValues(accountRecord, payload, isNewAccount);
        if (isNewAccount) {
            insert accountRecord;
        } else {
            update accountRecord;
        }

        Boolean isNewContact = contactRecord == null;
        if (isNewContact) {
            contactRecord = new Contact();
        } else {
            // AccountId is only writable on insert; for a Contact that is the
            // Person Account's own 1:1 contact, it is auto-managed and becomes
            // read-only after creation, so re-querying it with AccountId still
            // populated (even unchanged) and sending it back on update throws
            // INVALID_FIELD_FOR_INSERT_UPDATE. Rebuild a bare sObject so only
            // the fields applyContactValues() actually sets go out on update.
            contactRecord = new Contact(Id = contactRecord.Id);
        }
        applyContactValues(contactRecord, accountRecord.Id, payload, isNewContact);
        if (isNewContact) {
            insert contactRecord;
        } else {
            update contactRecord;
        }

        CustomerContext context = new CustomerContext();
        context.accountRecord = accountRecord;
        context.contactRecord = contactRecord;
        return context;
    }

    private static void applyAccountValues(Account accountRecord, CARAOrderPayload payload, Boolean isNewAccount) {
        if (isNewAccount) {
            // Name is only writable on insert; on Person Accounts it becomes a
            // read-only compound field (derived from FirstName/LastName) after
            // creation, so updating it on an existing Account throws
            // INVALID_FIELD_FOR_INSERT_UPDATE.
            String customerName = firstNonBlank(
                payload.customerInfo == null ? null : payload.customerInfo.customerName,
                payload.customerName,
                payload.customerInfo.email
            );
            accountRecord.Name = customerName;
        }
        accountRecord.External_ID__c = payload.customerInfo.customerId;
        accountRecord.Is_Guest__c = payload.guest == true;

        if (payload.billingAddress != null) {
            accountRecord.BillingStreet = payload.billingAddress.address1;
            accountRecord.BillingCity = payload.billingAddress.city;
            accountRecord.BillingState = payload.billingAddress.stateCode;
            accountRecord.BillingPostalCode = payload.billingAddress.postalCode;
            accountRecord.BillingCountry = payload.billingAddress.countryCode;
            accountRecord.Phone = payload.billingAddress.phone;
        }
    }

    private static void applyContactValues(
        Contact contactRecord,
        Id accountId,
        CARAOrderPayload payload,
        Boolean isNewContact
    ) {
        String customerName = firstNonBlank(payload.customerInfo.customerName, payload.customerName, 'Customer');
        List<String> nameParts = splitName(customerName);

        if (isNewContact) {
            contactRecord.AccountId = accountId;
        }
        contactRecord.FirstName = nameParts[0];
        contactRecord.LastName = nameParts[1];
        contactRecord.Email = payload.customerInfo.email.trim().toLowerCase();
        contactRecord.Is_Guest__c = payload.guest == true;

        if (payload.billingAddress != null) {
            contactRecord.MailingStreet = payload.billingAddress.address1;
            contactRecord.MailingCity = payload.billingAddress.city;
            contactRecord.MailingState = payload.billingAddress.stateCode;
            contactRecord.MailingPostalCode = payload.billingAddress.postalCode;
            contactRecord.MailingCountry = payload.billingAddress.countryCode;
            contactRecord.Phone = payload.billingAddress.phone;
            contactRecord.Billing_Address_External_ID__c = payload.billingAddress.id;
        }
    }

    private static Order syncOrderRecord(CARAOrderPayload payload, Id accountId, Id pricebookId) {
        List<Order> matchingOrders = [
            SELECT Id, Status, Pricebook2Id
            FROM Order
            WHERE OrderReferenceNumber = :payload.orderNo
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
        if (matchingOrders.size() > 1) {
            throw new IntegrationException('Multiple Orders use OrderReferenceNumber ' + payload.orderNo + '.');
        }

        Boolean isNewOrder = matchingOrders.isEmpty();
        Order orderRecord = isNewOrder ? new Order() : matchingOrders[0];
        String targetStatus = mapOrderStatus(payload.status);

        if (!isNewOrder && orderRecord.Status == 'Activated' && targetStatus != 'Activated') {
            throw new IntegrationException('Activated Order ' + payload.orderNo + ' cannot be returned to Draft.');
        }

        orderRecord.AccountId = accountId;
        orderRecord.OrderReferenceNumber = payload.orderNo;
        orderRecord.EffectiveDate = resolveCreationDatetime(payload.creationDate).dateGmt();
        orderRecord.Status = targetStatus;
        if (pricebookId != null) {
            orderRecord.Pricebook2Id = pricebookId;
        }
        orderRecord.Storefront_Token__c = payload.orderToken;
        orderRecord.Storefront_View_Code__c = payload.orderViewCode;
        orderRecord.Storefront_Site_ID__c = payload.siteId;
        orderRecord.OrderSource__c = payload.channelType;
        orderRecord.Confirmation_Status__c = payload.confirmationStatus;
        orderRecord.Payment_Status__c = payload.paymentStatus;
        // KYC requirement is derived from orderTotal (see isKycRequired), not
        // from SFCC's c_isKycNeed or any N-Genius field.
        orderRecord.isKycNeed__c = isKycRequired(payload);
        orderRecord.Shipping_Status__c = payload.shippingStatus;
        orderRecord.Export_Status__c = payload.exportStatus;
        orderRecord.CurrencyIsoCode__c = payload.currencyCode;
        orderRecord.Storefront_Last_Modified__c = String.isBlank(payload.lastModified)
            ? null
            : parseDatetime(payload.lastModified, 'lastModified');
        orderRecord.Created_By_Context__c = payload.createdBy;
        orderRecord.Customer_Name_Plain__c = payload.customerName;
        orderRecord.Product_Subtotal__c = payload.productSubTotal;
        orderRecord.Product_Total__c = payload.productTotal;
        orderRecord.Shipping_Total_Cost__c = payload.shippingTotal;
        orderRecord.Shipping_Total_Tax__c = payload.shippingTotalTax;
        orderRecord.Tax_Total_Amount__c = payload.taxTotal;
        orderRecord.Merchandize_Total_Tax__c = payload.merchandizeTotalTax;
        orderRecord.Adjusted_Merch_Total_Tax__c = payload.adjustedMerchandizeTotalTax;
        orderRecord.Adjusted_Shipping_Total_Tax__c = payload.adjustedShippingTotalTax;
        orderRecord.Taxation_Type__c = payload.taxation;
        orderRecord.Tax_Rounded_At_Group__c = payload.taxRoundedAtGroup == true;
        orderRecord.Description = serializeNotes(payload.notes);

        if (payload.billingAddress != null) {
            orderRecord.BillingStreet = payload.billingAddress.address1;
            orderRecord.BillingCity = payload.billingAddress.city;
            orderRecord.BillingState = payload.billingAddress.stateCode;
            orderRecord.BillingPostalCode = payload.billingAddress.postalCode;
            orderRecord.BillingCountry = payload.billingAddress.countryCode;
        }

        if (isNewOrder) {
            insert orderRecord;
        } else {
            update orderRecord;
        }
        return orderRecord;
    }

    private static void ensurePricebookEntries(
        CatalogContext catalog,
        List<CARAOrderPayload.ProductItem> productItems
    ) {
        if (productItems == null || productItems.isEmpty()) {
            return;
        }

        Map<Id, CARAOrderPayload.ProductItem> sampleItemByProductId = new Map<Id, CARAOrderPayload.ProductItem>();
        for (CARAOrderPayload.ProductItem item : productItems) {
            Product2 productRecord = catalog.productByCode.get(item.productId);
            if (!sampleItemByProductId.containsKey(productRecord.Id)) {
                sampleItemByProductId.put(productRecord.Id, item);
            }
        }

        List<PricebookEntry> entriesToInsert = new List<PricebookEntry>();
        List<PricebookEntry> entriesToUpdate = new List<PricebookEntry>();
        for (Id productId : sampleItemByProductId.keySet()) {
            CARAOrderPayload.ProductItem item = sampleItemByProductId.get(productId);
            Decimal listPrice = item.basePrice == null ? item.price : item.basePrice;
            PricebookEntry existingEntry = catalog.pricebookEntryByProductId.get(productId);

            if (existingEntry == null) {
                if (listPrice == null) {
                    throw new IntegrationException('A price is required to create a PricebookEntry for ' + item.productId + '.');
                }
                entriesToInsert.add(
                    new PricebookEntry(
                        Pricebook2Id = catalog.pricebookId,
                        Product2Id = productId,
                        UnitPrice = listPrice,
                        IsActive = true
                    )
                );
            } else if (listPrice != null && existingEntry.UnitPrice != listPrice) {
                // SFCC is the source of truth for current pricing. Without this,
                // a later order referencing a product whose price has changed
                // since its PricebookEntry was first created would fail with
                // FIELD_INTEGRITY_EXCEPTION ("Order Product must have the same
                // List Price as the related Price Book Entry") when syncOrderItems
                // sets OrderItem.ListPrice from the fresh payload price.
                existingEntry.UnitPrice = listPrice;
                entriesToUpdate.add(existingEntry);
            }
        }

        if (!entriesToInsert.isEmpty()) {
            insert entriesToInsert;
            for (PricebookEntry entry : entriesToInsert) {
                catalog.pricebookEntryByProductId.put(entry.Product2Id, entry);
            }
        }
        if (!entriesToUpdate.isEmpty()) {
            Database.update(entriesToUpdate, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void syncOrderItems(
        Id orderId,
        List<CARAOrderPayload.ProductItem> productItems,
        CatalogContext catalog
    ) {
        if (productItems == null || productItems.isEmpty()) {
            return;
        }

        Set<String> lineItemKeys = new Set<String>();
        for (CARAOrderPayload.ProductItem item : productItems) {
            lineItemKeys.add(item.itemId);
        }

        Map<String, OrderItem> existingByKey = new Map<String, OrderItem>();
        for (OrderItem existingItem : [
            SELECT Id, Product2Id, PricebookEntryId, Line_Item_External_ID__c
            FROM OrderItem
            WHERE OrderId = :orderId
            AND Line_Item_External_ID__c IN :lineItemKeys
        ]) {
            if (existingByKey.containsKey(existingItem.Line_Item_External_ID__c)) {
                throw new IntegrationException('Duplicate OrderItem key already exists: ' + existingItem.Line_Item_External_ID__c);
            }
            existingByKey.put(existingItem.Line_Item_External_ID__c, existingItem);
        }

        List<OrderItem> itemsToInsert = new List<OrderItem>();
        List<OrderItem> itemsToUpdate = new List<OrderItem>();
        for (CARAOrderPayload.ProductItem payloadItem : productItems) {
            Product2 productRecord = catalog.productByCode.get(payloadItem.productId);
            PricebookEntry entry = catalog.pricebookEntryByProductId.get(productRecord.Id);
            OrderItem orderItemRecord = existingByKey.get(payloadItem.itemId);
            Boolean isNewItem = orderItemRecord == null;

            if (isNewItem) {
                orderItemRecord = new OrderItem(
                    OrderId = orderId,
                    Product2Id = productRecord.Id,
                    PricebookEntryId = entry.Id,
                    Line_Item_External_ID__c = payloadItem.itemId
                );
            } else if (
                orderItemRecord.Product2Id != productRecord.Id ||
                orderItemRecord.PricebookEntryId != entry.Id
            ) {
                throw new IntegrationException('Existing OrderItem ' + payloadItem.itemId + ' references a different product.');
            }

            orderItemRecord.Quantity = payloadItem.quantity;
            orderItemRecord.UnitPrice = payloadItem.price;
            orderItemRecord.Storefront_Product_Name__c = payloadItem.productName;
            orderItemRecord.Price_After_Item_Discount__c = payloadItem.priceAfterItemDiscount;
            orderItemRecord.Price_After_Order_Discount__c = payloadItem.priceAfterOrderDiscount;
            orderItemRecord.Tax_Amount__c = payloadItem.tax;
            orderItemRecord.Tax_Rate__c = payloadItem.taxRate;
            orderItemRecord.Tax_Basis__c = payloadItem.taxBasis;
            orderItemRecord.Tax_Class_ID__c = payloadItem.taxClassId;
            orderItemRecord.Shipment_Group_Key__c = payloadItem.shipmentId;
            orderItemRecord.Is_Bonus_Item__c = payloadItem.bonusProductLineItem == true;
            orderItemRecord.Is_Gift__c = payloadItem.gift == true ? 1 : 0;

            if (isNewItem) {
                orderItemRecord.ListPrice = payloadItem.basePrice;
                itemsToInsert.add(orderItemRecord);
            } else {
                // Product2Id/PricebookEntryId are read-only once an OrderItem exists.
                // orderItemRecord still carries those fields from the existingByKey
                // query (needed for the comparison above) — updating with that same
                // instance fails with CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY, so the
                // update DML uses a fresh record with only the mutable fields.
                OrderItem updateRecord = new OrderItem(Id = orderItemRecord.Id);
                updateRecord.Quantity = orderItemRecord.Quantity;
                updateRecord.UnitPrice = orderItemRecord.UnitPrice;
                updateRecord.Storefront_Product_Name__c = orderItemRecord.Storefront_Product_Name__c;
                updateRecord.Price_After_Item_Discount__c = orderItemRecord.Price_After_Item_Discount__c;
                updateRecord.Price_After_Order_Discount__c = orderItemRecord.Price_After_Order_Discount__c;
                updateRecord.Tax_Amount__c = orderItemRecord.Tax_Amount__c;
                updateRecord.Tax_Rate__c = orderItemRecord.Tax_Rate__c;
                updateRecord.Tax_Basis__c = orderItemRecord.Tax_Basis__c;
                updateRecord.Tax_Class_ID__c = orderItemRecord.Tax_Class_ID__c;
                updateRecord.Shipment_Group_Key__c = orderItemRecord.Shipment_Group_Key__c;
                updateRecord.Is_Bonus_Item__c = orderItemRecord.Is_Bonus_Item__c;
                updateRecord.Is_Gift__c = orderItemRecord.Is_Gift__c;
                itemsToUpdate.add(updateRecord);
            }
        }

        if (!itemsToInsert.isEmpty()) {
            insert itemsToInsert;
        }
        if (!itemsToUpdate.isEmpty()) {
            update itemsToUpdate;
        }
    }

    private static void syncShipments(CARAOrderPayload payload, Set<String> warnings) {
        if (payload.shipments == null || payload.shipments.isEmpty()) {
            return;
        }

        Set<String> shipmentKeys = new Set<String>();
        Map<String, CARAOrderPayload.ShipmentPayload> payloadByKey = new Map<String, CARAOrderPayload.ShipmentPayload>();
        for (CARAOrderPayload.ShipmentPayload shipmentPayload : payload.shipments) {
            if (shipmentPayload == null || String.isBlank(shipmentPayload.shipmentId)) {
                throw new IntegrationException('Each shipments entry requires shipmentId.');
            }
            String shipmentKey = payload.orderNo + ':' + shipmentPayload.shipmentId;
            if (!shipmentKeys.add(shipmentKey)) {
                throw new IntegrationException('Duplicate shipmentId in payload: ' + shipmentPayload.shipmentId);
            }
            payloadByKey.put(shipmentKey, shipmentPayload);
        }

        Map<String, Shipment> existingByKey = new Map<String, Shipment>();
        for (Shipment existingShipment : [
            SELECT Id, Shipment_External_ID__c
            FROM Shipment
            WHERE Shipment_External_ID__c IN :shipmentKeys
        ]) {
            existingByKey.put(existingShipment.Shipment_External_ID__c, existingShipment);
        }

        List<Shipment> shipmentsToInsert = new List<Shipment>();
        List<Shipment> shipmentsToUpdate = new List<Shipment>();
        for (String shipmentKey : payloadByKey.keySet()) {
            CARAOrderPayload.ShipmentPayload shipmentPayload = payloadByKey.get(shipmentKey);
            Shipment shipmentRecord = existingByKey.get(shipmentKey);
            Boolean isNewShipment = shipmentRecord == null;
            if (isNewShipment) {
                shipmentRecord = new Shipment(Shipment_External_ID__c = shipmentKey);
            }

            shipmentRecord.ShipToName = formatAddressName(shipmentPayload.shippingAddress);
            shipmentRecord.Shipping_Method_Code__c = shipmentPayload.shippingMethod == null
                ? null
                : shipmentPayload.shippingMethod.id;
            shipmentRecord.Shipment_Method_Display__c = shipmentPayload.shippingMethod == null
                ? null
                : shipmentPayload.shippingMethod.name;
            shipmentRecord.Base_Shipping_Price__c = shipmentPayload.shippingMethod == null
                ? null
                : shipmentPayload.shippingMethod.price;
            shipmentRecord.Shipping_Cost_Final__c = shipmentPayload.shippingTotal;
            shipmentRecord.Status__c = shipmentPayload.shippingStatus;

            if (isNewShipment) {
                shipmentsToInsert.add(shipmentRecord);
            } else {
                shipmentsToUpdate.add(shipmentRecord);
            }
        }

        if (!shipmentsToInsert.isEmpty()) {
            insert shipmentsToInsert;
        }
        if (!shipmentsToUpdate.isEmpty()) {
            update shipmentsToUpdate;
        }

        warnings.add('Shipment has no Order lookup or destination address fields; the external key contains the Order reference.');
    }

    private static void syncPayments(
        CARAOrderPayload payload,
        CustomerContext customer,
        Order orderRecord,
        Set<String> warnings
    ) {
        if (payload.paymentInstruments == null || payload.paymentInstruments.isEmpty()) {
            return;
        }

        Set<String> gatewayTokens = new Set<String>();
        Map<String, CARAOrderPayload.PaymentInstrument> instrumentByToken = new Map<String, CARAOrderPayload.PaymentInstrument>();
        for (CARAOrderPayload.PaymentInstrument instrument : payload.paymentInstruments) {
            if (instrument == null || String.isBlank(instrument.paymentInstrumentId)) {
                throw new IntegrationException('Each paymentInstruments entry requires paymentInstrumentId.');
            }
            if (instrument.amount == null) {
                throw new IntegrationException('Payment instrument ' + instrument.paymentInstrumentId + ' requires amount.');
            }
            if (instrument.paymentCard == null) {
                warnings.add(
                    'Payment instrument ' + instrument.paymentInstrumentId +
                    (String.isBlank(instrument.paymentMethodId) ? '' : ' (method ' + instrument.paymentMethodId + ')') +
                    ' has no paymentCard and was not synced.'
                );
                continue;
            }
            if (!gatewayTokens.add(instrument.paymentInstrumentId)) {
                throw new IntegrationException('Duplicate paymentInstrumentId in payload: ' + instrument.paymentInstrumentId);
            }
            instrumentByToken.put(instrument.paymentInstrumentId, instrument);
        }

        Map<String, CardPaymentMethod> methodByToken = new Map<String, CardPaymentMethod>();
        Id customerAccountId = customer.accountRecord.Id;
        for (CardPaymentMethod methodRecord : [
            SELECT Id, GatewayToken
            FROM CardPaymentMethod
            WHERE AccountId = :customerAccountId
            AND GatewayToken IN :gatewayTokens
        ]) {
            if (methodByToken.containsKey(methodRecord.GatewayToken)) {
                throw new IntegrationException('Multiple CardPaymentMethod records use gateway token ' + methodRecord.GatewayToken + '.');
            }
            methodByToken.put(methodRecord.GatewayToken, methodRecord);
        }

        List<CardPaymentMethod> methodsToInsert = new List<CardPaymentMethod>();
        List<CardPaymentMethod> methodsToUpdate = new List<CardPaymentMethod>();
        for (String gatewayToken : gatewayTokens) {
            CARAOrderPayload.PaymentInstrument instrument = instrumentByToken.get(gatewayToken);
            CARAOrderPayload.PaymentCard card = instrument.paymentCard;
            if (!methodByToken.containsKey(gatewayToken)) {
                CardPaymentMethod methodRecord = new CardPaymentMethod(
                    AccountId = customer.accountRecord.Id,
                    CardCategory = 'CreditCard',
                    CardHolderName = card.holder,
                    Email = customer.contactRecord.Email,
                    ExpiryMonth = card.expirationMonth,
                    ExpiryYear = card.expirationYear,
                    GatewayToken = gatewayToken,
                    IsAutoPayEnabled = false,
                    Phone = payload.billingAddress == null ? null : payload.billingAddress.phone,
                    ProcessingMode = PROCESSING_MODE_EXTERNAL,
                    Status = 'Active'
                );
                methodsToInsert.add(methodRecord);
                methodByToken.put(gatewayToken, methodRecord);
            } else {
                CardPaymentMethod methodRecord = methodByToken.get(gatewayToken);
                methodRecord.CardHolderName = card.holder;
                methodRecord.Email = customer.contactRecord.Email;
                methodRecord.ExpiryMonth = card.expirationMonth;
                methodRecord.ExpiryYear = card.expirationYear;
                methodRecord.Phone = payload.billingAddress == null ? null : payload.billingAddress.phone;
                methodsToUpdate.add(methodRecord);
            }
        }
        if (!methodsToInsert.isEmpty()) {
            insert methodsToInsert;
        }
        if (!methodsToUpdate.isEmpty()) {
            update methodsToUpdate;
        }

        Map<String, Payment> existingPaymentByToken = new Map<String, Payment>();
        for (Payment paymentRecord : [
            // Status/ProcessingMode are read-only once a Payment exists and are
            // never reassigned below — they must stay out of this SELECT, since
            // Apex update DML resends every populated field on the sObject
            // (not just the ones explicitly changed), and including either here
            // would make every re-sync of an already-paid order fail with
            // CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY.
            SELECT Id, Payment_Gateway_Token__c
            FROM Payment
            WHERE AccountId = :customerAccountId
            AND Payment_Gateway_Token__c IN :gatewayTokens
        ]) {
            if (existingPaymentByToken.containsKey(paymentRecord.Payment_Gateway_Token__c)) {
                throw new IntegrationException('Multiple Payment records use gateway token ' + paymentRecord.Payment_Gateway_Token__c + '.');
            }
            existingPaymentByToken.put(paymentRecord.Payment_Gateway_Token__c, paymentRecord);
        }

        List<Payment> paymentsToInsert = new List<Payment>();
        List<Payment> paymentsToUpdate = new List<Payment>();
        for (String gatewayToken : gatewayTokens) {
            CARAOrderPayload.PaymentInstrument instrument = instrumentByToken.get(gatewayToken);
            CARAOrderPayload.PaymentCard card = instrument.paymentCard;
            Payment paymentRecord = existingPaymentByToken.get(gatewayToken);
            Boolean isNewPayment = paymentRecord == null;
            if (isNewPayment) {
                paymentRecord = new Payment(
                    Payment_Gateway_Token__c = gatewayToken,
                    ProcessingMode = PROCESSING_MODE_EXTERNAL,
                    Status = PAYMENT_STATUS_PENDING
                );
            }

            paymentRecord.AccountId = customer.accountRecord.Id;
            paymentRecord.PaymentMethodId = methodByToken.get(gatewayToken).Id;
            paymentRecord.Amount = instrument.amount;
            paymentRecord.Type = PAYMENT_TYPE_SALE;
            paymentRecord.EffectiveDate = resolveCreationDatetime(payload.creationDate);
            paymentRecord.Email = customer.contactRecord.Email;
            paymentRecord.Phone = payload.billingAddress == null ? null : payload.billingAddress.phone;
            paymentRecord.GatewayRefNumber = gatewayToken;
            paymentRecord.Comments = 'CARA Order Reference: ' + payload.orderNo +
                (String.isBlank(instrument.paymentMethodId) ? '' : '; Method: ' + instrument.paymentMethodId);
            paymentRecord.Card_Type__c = card.cardType;
            paymentRecord.Masked_Card_Number__c = card.maskedNumber;
            paymentRecord.Card_Last_Four_Digits__c = card.numberLastDigits;
            paymentRecord.Card_Expiration_Year__c = card.expirationYear == null
                ? null
                : String.valueOf(card.expirationYear);

            if (isNewPayment) {
                paymentsToInsert.add(paymentRecord);
            } else {
                paymentsToUpdate.add(paymentRecord);
            }
        }

        if (!paymentsToInsert.isEmpty()) {
            insert paymentsToInsert;
        }
        if (!paymentsToUpdate.isEmpty()) {
            update paymentsToUpdate;
        }

        warnings.add('Payment is linked to the customer Account; the Order reference is stored in Payment.Comments.');
    }

    /*
     * KYC is required purely on orderTotal >= 50,000 in the order's
     * settlement currency. The threshold is only meaningful in AED, and the
     * integration accepts SFCC's currencyCode as free text with no
     * conversion support, so a non-AED order is never blindly compared
     * against the AED threshold.
     */
    private static Boolean isKycRequired(CARAOrderPayload payload) {
        if (payload.orderTotal == null || String.isBlank(payload.currencyCode)) {
            return false;
        }
        Decimal threshold = KYC_ORDER_TOTAL_THRESHOLD_BY_CURRENCY.get(payload.currencyCode.trim().toUpperCase());
        if (threshold == null) {
            return false;
        }
        return payload.orderTotal >= threshold;
    }

    private static String mapOrderStatus(String sourceStatus) {
        if (sourceStatus == null) {
            return null;
        }
        if (
            sourceStatus.equalsIgnoreCase('created') ||
            sourceStatus.equalsIgnoreCase('draft') ||
            sourceStatus.equalsIgnoreCase('new')
        ) {
            return ORDER_STATUS_DRAFT;
        }
        if (sourceStatus.equalsIgnoreCase('activated')) {
            return 'Activated';
        }
        throw new IntegrationException('Unsupported order status: ' + sourceStatus);
    }

    private static Datetime parseDatetime(String sourceValue, String fieldName) {
        if (String.isBlank(sourceValue)) {
            throw new IntegrationException(fieldName + ' is required.');
        }
        try {
            return (Datetime) JSON.deserialize(JSON.serialize(sourceValue), Datetime.class);
        } catch (Exception parseException) {
            throw new IntegrationException('Invalid ISO-8601 datetime in ' + fieldName + ': ' + sourceValue);
        }
    }

    private static Datetime resolveCreationDatetime(String sourceValue) {
        return String.isBlank(sourceValue) ? Datetime.now() : parseDatetime(sourceValue, 'creationDate');
    }

    private static List<String> splitName(String fullName) {
        String normalizedName = String.isBlank(fullName) ? 'Customer' : fullName.trim();
        Integer firstSpace = normalizedName.indexOf(' ');
        if (firstSpace <= 0) {
            return new List<String>{ null, normalizedName };
        }
        String firstName = normalizedName.substring(0, firstSpace).trim();
        String lastName = normalizedName.substring(firstSpace + 1).trim();
        if (String.isBlank(lastName)) {
            lastName = firstName;
            firstName = null;
        }
        return new List<String>{ firstName, lastName };
    }

    private static String formatAddressName(CARAOrderPayload.Address addressRecord) {
        if (addressRecord == null) {
            throw new IntegrationException('Each shipment requires shippingAddress.');
        }
        String fullName = firstNonBlank(
            addressRecord.fullName,
            String.join(
                new List<String>{
                    String.isBlank(addressRecord.firstName) ? '' : addressRecord.firstName.trim(),
                    String.isBlank(addressRecord.lastName) ? '' : addressRecord.lastName.trim()
                },
                ' '
            ).trim(),
            null
        );
        if (String.isBlank(fullName)) {
            throw new IntegrationException('Each shipment shippingAddress requires a recipient name.');
        }
        return fullName;
    }

    private static String serializeNotes(Object notes) {
        if (notes == null) {
            return null;
        }
        if (notes instanceof String) {
            return String.isBlank((String) notes) ? null : (String) notes;
        }
        String serializedNotes = JSON.serialize(notes);
        return serializedNotes == '{}' || serializedNotes == '[]' || serializedNotes == 'null'
            ? null
            : serializedNotes;
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