@IsTest
private class CARAOrderRestServiceTest {
    private static final String PRODUCT_CODE = 'solitaire-radiant-diamond-ring-in-18k-white-gold-8-1';

    @TestSetup
    static void createCatalogData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        insert new Product2(
            Name = 'Solitaire Radiant Diamond Ring in 18K White Gold',
            ProductCode = PRODUCT_CODE,
            IsActive = true
        );
    }

    @IsTest
    static void syncsFullPayloadAndRemainsIdempotent() {
        String requestBody = JSON.serialize(buildFullPayload());

        Test.startTest();
        invokeService(requestBody);
        Integer firstStatusCode = RestContext.response.statusCode;
        String firstResponseBody = RestContext.response.responseBody.toString();

        invokeService(requestBody);
        Integer secondStatusCode = RestContext.response.statusCode;
        Test.stopTest();

        Assert.areEqual(200, firstStatusCode, firstResponseBody);
        Assert.areEqual(200, secondStatusCode, RestContext.response.responseBody.toString());
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE External_ID__c = 'abmekYkHcUmbwRwuhKxGYYxrs0']);
        Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Email = 'nabeel@20three.digital']);
        Assert.areEqual(1, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = '00000429']);
        Assert.areEqual(1, [SELECT COUNT() FROM OrderItem WHERE Line_Item_External_ID__c = '9b3cbdd3b1bf7ba6db4a030b6c']);
        Assert.areEqual(1, [SELECT COUNT() FROM Shipment WHERE Shipment_External_ID__c = '00000429:me']);
        Assert.areEqual(1, [SELECT COUNT() FROM Payment WHERE Payment_Gateway_Token__c = '31640bb6c96ece3042d0035177']);
        Assert.areEqual(1, [SELECT COUNT() FROM CardPaymentMethod WHERE GatewayToken = '31640bb6c96ece3042d0035177']);

        Order synchronizedOrder = [
            SELECT
                AccountId,
                EffectiveDate,
                Status,
                OrderSource__c,
                CurrencyIsoCode__c,
                Product_Total__c,
                TotalAmount
            FROM Order
            WHERE OrderReferenceNumber = '00000429'
            LIMIT 1
        ];
        Assert.areEqual(Date.newInstance(2026, 8, 20), synchronizedOrder.EffectiveDate);
        Assert.areEqual('Draft', synchronizedOrder.Status);
        Assert.areEqual('storefront', synchronizedOrder.OrderSource__c);
        Assert.areEqual('AED', synchronizedOrder.CurrencyIsoCode__c);
        Assert.areEqual(Decimal.valueOf('500'), synchronizedOrder.Product_Total__c);
        Assert.areEqual(Decimal.valueOf('500'), synchronizedOrder.TotalAmount);

        OrderItem synchronizedItem = [
            SELECT Quantity, UnitPrice, Tax_Amount__c, Is_Gift__c, Product2.ProductCode
            FROM OrderItem
            WHERE OrderId = :synchronizedOrder.Id
            LIMIT 1
        ];
        Assert.areEqual(Decimal.valueOf('1'), synchronizedItem.Quantity);
        Assert.areEqual(Decimal.valueOf('500'), synchronizedItem.UnitPrice);
        Assert.areEqual(Decimal.valueOf('0'), synchronizedItem.Tax_Amount__c);
        Assert.areEqual(Decimal.valueOf('0'), synchronizedItem.Is_Gift__c);
        Assert.areEqual(PRODUCT_CODE, synchronizedItem.Product2.ProductCode);

        Payment synchronizedPayment = [
            SELECT AccountId, Amount, Status, Type, ProcessingMode, PaymentMethodId, Comments
            FROM Payment
            WHERE Payment_Gateway_Token__c = '31640bb6c96ece3042d0035177'
            LIMIT 1
        ];
        Assert.areEqual(synchronizedOrder.AccountId, synchronizedPayment.AccountId);
        Assert.areEqual(Decimal.valueOf('525'), synchronizedPayment.Amount);
        Assert.areEqual('Pending', synchronizedPayment.Status);
        Assert.areEqual('Sale', synchronizedPayment.Type);
        Assert.areEqual('External', synchronizedPayment.ProcessingMode);
        Assert.isNotNull(synchronizedPayment.PaymentMethodId);
        Assert.isTrue(synchronizedPayment.Comments.contains('00000429'));
    }

    // =========================================================
    // isKycNeed is derived from orderTotal vs. a per-currency threshold
    // (AED >= 50,000, GBP >= 20,000). SFCC's c_isKycNeed and the N-Genius
    // fields are no longer read by Order Sync. Currencies with no defined
    // threshold (e.g. USD) never trigger KYC via this rule.
    // =========================================================
    @IsTest
    static void kycFlagIsFalseWhenOrderTotalBelowThreshold() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('orderTotal', 49999);
        // SFCC still sending these must have no effect any more.
        payload.put('c_isKycNeed', true);
        payload.put('c_ngeniusOrderReference', 'ngen-order-00000429');
        payload.put('c_ngeniusPaymentReference', 'ngen-pay-00000429');
        payload.put('c_ngeniusPaymentState', 'AUTHORISED');

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());

        Order synchronizedOrder = [
            SELECT isKycNeed__c
            FROM Order
            WHERE OrderReferenceNumber = '00000429'
            LIMIT 1
        ];
        Assert.isFalse(synchronizedOrder.isKycNeed__c, 'orderTotal 49,999 AED is below the 50,000 threshold.');
    }

    @IsTest
    static void kycFlagIsTrueWhenOrderTotalAtThreshold() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('orderTotal', 50000);

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());

        Order synchronizedOrder = [SELECT isKycNeed__c FROM Order WHERE OrderReferenceNumber = '00000429' LIMIT 1];
        Assert.isTrue(synchronizedOrder.isKycNeed__c, 'orderTotal 50,000 AED meets the threshold.');
    }

    @IsTest
    static void kycFlagIsTrueWhenOrderTotalAboveThreshold() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('orderTotal', 50001);

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());

        Order synchronizedOrder = [SELECT isKycNeed__c FROM Order WHERE OrderReferenceNumber = '00000429' LIMIT 1];
        Assert.isTrue(synchronizedOrder.isKycNeed__c, 'orderTotal 50,001 AED exceeds the threshold.');
    }

    @IsTest
    static void kycFlagIsFalseForNonAedOrderEvenAboveThreshold() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('currency', 'USD');
        payload.put('orderTotal', 75000);

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());

        Order synchronizedOrder = [SELECT isKycNeed__c FROM Order WHERE OrderReferenceNumber = '00000429' LIMIT 1];
        Assert.isFalse(
            synchronizedOrder.isKycNeed__c,
            'The AED 50,000 threshold is not blindly applied to a non-AED orderTotal.'
        );
    }

    @IsTest
    static void kycFlagIsFalseWhenGbpOrderTotalBelowThreshold() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('currency', 'GBP');
        payload.put('orderTotal', 19999);

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());

        Order synchronizedOrder = [SELECT isKycNeed__c FROM Order WHERE OrderReferenceNumber = '00000429' LIMIT 1];
        Assert.isFalse(synchronizedOrder.isKycNeed__c, 'orderTotal 19,999 GBP is below the 20,000 threshold.');
    }

    @IsTest
    static void kycFlagIsTrueWhenGbpOrderTotalAtThreshold() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('currency', 'GBP');
        payload.put('orderTotal', 20000);

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());

        Order synchronizedOrder = [SELECT isKycNeed__c FROM Order WHERE OrderReferenceNumber = '00000429' LIMIT 1];
        Assert.isTrue(synchronizedOrder.isKycNeed__c, 'orderTotal 20,000 GBP meets the threshold.');
    }

    @IsTest
    static void kycFlagIsTrueWhenGbpOrderTotalAboveThreshold() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('currency', 'GBP');
        payload.put('orderTotal', 20001);

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());

        Order synchronizedOrder = [SELECT isKycNeed__c FROM Order WHERE OrderReferenceNumber = '00000429' LIMIT 1];
        Assert.isTrue(synchronizedOrder.isKycNeed__c, 'orderTotal 20,001 GBP exceeds the threshold.');
    }

    // =========================================================
    // Reusing the existing KYC Case + Order Hold automation: a KYC-required
    // Order is put On Hold and gets exactly one Compliance Case, even when
    // synced repeatedly while still above threshold.
    // =========================================================
    @IsTest
    static void kycAtThresholdHoldsOrderAndCreatesSingleCaseIdempotently() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('currency', 'AED');
        payload.put('orderTotal', 50000);

        Test.startTest();
        invokeService(JSON.serialize(payload));
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());

        Order synchronizedOrder = [
            SELECT Id, Status, isKycNeed__c
            FROM Order
            WHERE OrderReferenceNumber = '00000429'
            LIMIT 1
        ];
        Assert.isTrue(synchronizedOrder.isKycNeed__c, 'orderTotal 50,000 AED meets the threshold.');
        Assert.areEqual('On Hold', synchronizedOrder.Status, 'KYC - Hold High Value Orders should hold the order.');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Case WHERE KYC_Order__c = :synchronizedOrder.Id],
            'Re-syncing an already KYC-flagged Order must not create a duplicate Compliance Case.'
        );
    }

    @IsTest
    static void nonKycOrderIsNotHeld() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('currency', 'AED');
        payload.put('orderTotal', 49999);

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Order synchronizedOrder = [SELECT Status FROM Order WHERE OrderReferenceNumber = '00000429' LIMIT 1];
        Assert.areEqual('Draft', synchronizedOrder.Status, 'An Order below threshold must not be held.');
    }

    // =========================================================
    // SFCC status "new" is the status of a freshly placed order (before
    // fulfillment/activation) and must map the same as "created" — an
    // Order Sync failure previously surfaced as "Unsupported order status:
    // new" because mapOrderStatus() only recognized created/draft/activated.
    // =========================================================
    @IsTest
    static void sfccNewOrderStatusMapsToDraft() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('orderNo', '00000674');
        payload.put('status', 'new');

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        Order synchronizedOrder = [
            SELECT Status
            FROM Order
            WHERE OrderReferenceNumber = '00000674'
            LIMIT 1
        ];
        Assert.areEqual('Draft', synchronizedOrder.Status);
    }

    @IsTest
    static void missingRequiredFieldReturns400AndRollsBack() {
        Map<String, Object> invalidPayload = buildFullPayload();
        invalidPayload.remove('orderNo');

        Test.startTest();
        invokeService(JSON.serialize(invalidPayload));
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode);
        Assert.isTrue(RestContext.response.responseBody.toString().contains('orderNo'));
        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
        Assert.areEqual(0, [SELECT COUNT() FROM Contact]);
        Assert.areEqual(0, [SELECT COUNT() FROM Order]);
        Assert.areEqual(0, [SELECT COUNT() FROM OrderItem]);
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment]);
        Assert.areEqual(0, [SELECT COUNT() FROM Payment]);
        Assert.areEqual(0, [SELECT COUNT() FROM CardPaymentMethod]);
    }

    // =========================================================
    // Non-card payment instruments (gift certificate, wallet, COD, etc.)
    // legitimately omit paymentCard. Order 00000676 failed with "requires
    // paymentCard" because that case previously hard-failed the whole
    // order; it must now be skipped (with a warning) instead of rejecting
    // the order.
    // =========================================================
    @IsTest
    static void nonCardPaymentInstrumentIsSkippedWithWarningInsteadOfFailingOrder() {
        Map<String, Object> payload = buildFullPayload();
        payload.put('orderNo', '00000676');

        Map<String, Object> giftCertificateInstrument = new Map<String, Object>{
            'amount' => 50,
            'paymentInstrumentId' => 'gift-cert-00000676',
            'paymentMethodId' => 'GIFT_CERTIFICATE'
        };
        List<Object> instruments = (List<Object>) payload.get('paymentInstruments');
        instruments.add(giftCertificateInstrument);

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        String responseBody = RestContext.response.responseBody.toString();
        Assert.areEqual(200, RestContext.response.statusCode, responseBody);

        Map<String, Object> parsedResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> warnings = (List<Object>) parsedResponse.get('warnings');
        Boolean hasSkipWarning = false;
        for (Object warningValue : warnings) {
            if (((String) warningValue).contains('gift-cert-00000676')) {
                hasSkipWarning = true;
            }
        }
        Assert.isTrue(hasSkipWarning, 'Expected a warning noting the non-card instrument was not synced: ' + responseBody);

        Assert.areEqual(1, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = '00000676']);
        Assert.areEqual(1, [SELECT COUNT() FROM Payment WHERE Payment_Gateway_Token__c = '31640bb6c96ece3042d0035177']);
        Assert.areEqual(0, [SELECT COUNT() FROM Payment WHERE Payment_Gateway_Token__c = 'gift-cert-00000676']);
        Assert.areEqual(0, [SELECT COUNT() FROM CardPaymentMethod WHERE GatewayToken = 'gift-cert-00000676']);
    }

    @IsTest
    static void missingProductIsCreatedAndUsedForOrderItem() {
        Map<String, Object> payload = buildFullPayload();
        List<Object> items = (List<Object>) payload.get('productItems');
        Map<String, Object> item = (Map<String, Object>) items[0];
        item.put('productId', 'missing-product');
        item.put('productName', 'Product Created by CARA Sync');

        Test.startTest();
        invokeService(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        Product2 createdProduct = [
            SELECT Id, Name, ProductCode, IsActive
            FROM Product2
            WHERE ProductCode = 'missing-product'
            LIMIT 1
        ];
        Assert.areEqual('Product Created by CARA Sync', createdProduct.Name);
        Assert.isTrue(createdProduct.IsActive);

        OrderItem createdItem = [
            SELECT Product2Id, Product2.ProductCode
            FROM OrderItem
            WHERE Line_Item_External_ID__c = '9b3cbdd3b1bf7ba6db4a030b6c'
            LIMIT 1
        ];
        Assert.areEqual(createdProduct.Id, createdItem.Product2Id);
        Assert.areEqual('missing-product', createdItem.Product2.ProductCode);
    }

    @IsTest
    static void activatesStandardPricebookWhenNeeded() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = false);

        Test.startTest();
        invokeService(JSON.serialize(buildFullPayload()));
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
        Pricebook2 activatedPricebook = [
            SELECT IsActive
            FROM Pricebook2
            WHERE Id = :standardPricebookId
        ];
        Assert.isTrue(activatedPricebook.IsActive);
        Assert.areEqual(1, [SELECT COUNT() FROM Order WHERE OrderReferenceNumber = '00000429']);
    }

    private static void invokeService(String requestBody) {
        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/order';
        requestRecord.httpMethod = 'POST';
        requestRecord.requestBody = Blob.valueOf(requestBody);
        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();
        CARAOrderRestService.syncOrder();
    }

    private static Map<String, Object> buildFullPayload() {
        Map<String, Object> billingAddress = new Map<String, Object>{
            'address1' => '20three.digital',
            'city' => 'Dubai',
            'countryCode' => 'US',
            'firstName' => 'Nabeel',
            'fullName' => 'Nabeel Iftikhar',
            'id' => 'b46a7dddb02e405b3bedad1968',
            'lastName' => 'Iftikhar',
            'phone' => '+1 5555555555',
            'postalCode' => '54000',
            'stateCode' => 'AR'
        };
        Map<String, Object> shippingAddress = new Map<String, Object>(billingAddress);
        shippingAddress.put('id', 'cb327e7fc2ccc6beb003f497ac');

        Map<String, Object> productItem = new Map<String, Object>{
            'adjustedTax' => 0,
            'basePrice' => 500,
            'bonusProductLineItem' => false,
            'gift' => false,
            'itemId' => '9b3cbdd3b1bf7ba6db4a030b6c',
            'itemText' => 'Solitaire Radiant Diamond Ring in 18K White Gold',
            'price' => 500,
            'priceAfterItemDiscount' => 500,
            'priceAfterOrderDiscount' => 500,
            'productId' => PRODUCT_CODE,
            'productName' => 'Solitaire Radiant Diamond Ring in 18K White Gold',
            'quantity' => 1,
            'shipmentId' => 'me',
            'tax' => 0,
            'taxBasis' => 500,
            'taxClassId' => 'default',
            'taxRate' => 0
        };
        Map<String, Object> shipment = new Map<String, Object>{
            'shipmentId' => 'me',
            'shippingAddress' => shippingAddress,
            'shippingMethod' => new Map<String, Object>{
                'id' => 'standard-delivery',
                'name' => 'Standard Delivery',
                'price' => 25
            },
            'shippingStatus' => 'not_shipped',
            'shippingTotal' => 25
        };
        Map<String, Object> paymentInstrument = new Map<String, Object>{
            'amount' => 525,
            'paymentCard' => new Map<String, Object>{
                'cardType' => 'Visa',
                'creditCardExpired' => false,
                'expirationMonth' => 12,
                'expirationYear' => 2030,
                'holder' => 'Nabeel Iftikhar',
                'maskedNumber' => '************1111',
                'numberLastDigits' => '1111'
            },
            'paymentInstrumentId' => '31640bb6c96ece3042d0035177',
            'paymentMethodId' => 'CREDIT_CARD'
        };

        return new Map<String, Object>{
            'adjustedMerchandizeTotalTax' => 0,
            'adjustedShippingTotalTax' => 0,
            'billingAddress' => billingAddress,
            'channelType' => 'storefront',
            'confirmationStatus' => 'not_confirmed',
            'createdBy' => 'Customer',
            'creationDate' => '2026-08-20T12:41:03.553Z',
            'currency' => 'AED',
            'customerInfo' => new Map<String, Object>{
                'customerId' => 'abmekYkHcUmbwRwuhKxGYYxrs0',
                'customerName' => 'Nabeel Iftikhar',
                'email' => 'nabeel@20three.digital'
            },
            'customerName' => 'Nabeel Iftikhar',
            'exportStatus' => 'not_exported',
            'guest' => true,
            'lastModified' => '2026-08-20T12:41:03.559Z',
            'merchandizeTotalTax' => 0,
            'notes' => new Map<String, Object>(),
            'orderNo' => '00000429',
            'orderToken' => '2xH6z1V3b2V0_jYhPRV8jbaoAR5USZvgcQZAzY3u-SI',
            'orderTotal' => 525,
            'orderViewCode' => '4D3fcO_FVkyKYLnLjUEuFkgWBNxiGRbNh947vQlIESk',
            'paymentInstruments' => new List<Object>{ paymentInstrument },
            'paymentStatus' => 'not_paid',
            'productItems' => new List<Object>{ productItem },
            'productSubTotal' => 500,
            'productTotal' => 500,
            'shipments' => new List<Object>{ shipment },
            'shippingStatus' => 'not_shipped',
            'shippingTotal' => 25,
            'shippingTotalTax' => 0,
            'siteId' => 'CARA_AE',
            'status' => 'created',
            'taxation' => 'net',
            'taxRoundedAtGroup' => false,
            'taxTotal' => 0
        };
    }
}