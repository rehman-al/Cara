// Run this file in VS Code with: SFDX: Execute Anonymous Apex with Editor Contents
// It invokes the Apex REST handler directly and commits the records when the
// response is successful. Every run uses unique integration identifiers.

String runKey = String.valueOf(Datetime.now().getTime());
String orderNumber = 'CARA-TEST-' + runKey;
String customerExternalId = 'CARA-CUSTOMER-' + runKey;
String customerEmail = 'cara.test.' + runKey + '@example.com';
String paymentToken = 'CARA-PAYMENT-' + runKey;
// A unique ProductCode verifies that the REST service creates Product2 itself.
String productCode = 'CARA-TEST-PRODUCT-' + runKey;

Map<String, Object> billingAddress = new Map<String, Object>{
    'address1' => '20three.digital',
    'city' => 'Dubai',
    'countryCode' => 'US',
    'firstName' => 'Nabeel',
    'fullName' => 'Nabeel Iftikhar',
    'id' => 'BILLING-' + runKey,
    'lastName' => 'Iftikhar',
    'phone' => '+1 5555555555',
    'postalCode' => '54000',
    'stateCode' => 'AR'
};

Map<String, Object> payload = new Map<String, Object>{
    'adjustedMerchandizeTotalTax' => 0,
    'adjustedShippingTotalTax' => 0,
    'billingAddress' => billingAddress,
    'channelType' => 'storefront',
    'confirmationStatus' => 'not_confirmed',
    'createdBy' => 'Execute Anonymous Test',
    'creationDate' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
    'currency' => 'AED',
    'customerInfo' => new Map<String, Object>{
        'customerId' => customerExternalId,
        'customerName' => 'Nabeel Iftikhar',
        'email' => customerEmail
    },
    'customerName' => 'Nabeel Iftikhar',
    'exportStatus' => 'not_exported',
    'guest' => true,
    'lastModified' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
    'merchandizeTotalTax' => 0,
    'notes' => new Map<String, Object>{ 'source' => 'Execute Anonymous' },
    'orderNo' => orderNumber,
    'orderToken' => 'CARA-TOKEN-' + runKey,
    'orderTotal' => 525,
    'orderViewCode' => 'CARA-VIEW-' + runKey,
    'paymentInstruments' => new List<Object>{
        new Map<String, Object>{
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
            'paymentInstrumentId' => paymentToken,
            'paymentMethodId' => 'CREDIT_CARD'
        }
    },
    'paymentStatus' => 'not_paid',
    'productItems' => new List<Object>{
        new Map<String, Object>{
            'adjustedTax' => 0,
            'basePrice' => 500,
            'bonusProductLineItem' => false,
            'gift' => false,
            'itemId' => 'CARA-ITEM-' + runKey,
            'itemText' => 'Solitaire Radiant Diamond Ring in 18K White Gold',
            'price' => 500,
            'priceAfterItemDiscount' => 500,
            'priceAfterOrderDiscount' => 500,
            'productId' => productCode,
            'productName' => 'Solitaire Radiant Diamond Ring in 18K White Gold',
            'quantity' => 1,
            'shipmentId' => 'main',
            'tax' => 0,
            'taxBasis' => 500,
            'taxClassId' => 'default',
            'taxRate' => 0
        }
    },
    'productSubTotal' => 500,
    'productTotal' => 500,
    'shipments' => new List<Object>{
        new Map<String, Object>{
            'shipmentId' => 'main',
            'shippingAddress' => new Map<String, Object>{
                'address1' => '20three.digital',
                'city' => 'Dubai',
                'countryCode' => 'US',
                'firstName' => 'Nabeel',
                'fullName' => 'Nabeel Iftikhar',
                'id' => 'SHIPPING-' + runKey,
                'lastName' => 'Iftikhar',
                'postalCode' => '54000',
                'stateCode' => 'AR'
            },
            'shippingMethod' => new Map<String, Object>{
                'id' => 'standard-delivery',
                'name' => 'Standard Delivery',
                'price' => 25
            },
            'shippingStatus' => 'not_shipped',
            'shippingTotal' => 25
        }
    },
    'shippingStatus' => 'not_shipped',
    'shippingTotal' => 25,
    'shippingTotalTax' => 0,
    'siteId' => 'CARA_AE',
    'status' => 'created',
    'taxation' => 'net',
    'taxRoundedAtGroup' => false,
    'taxTotal' => 0
};

RestRequest requestRecord = new RestRequest();
requestRecord.requestUri = '/services/apexrest/cara/order';
requestRecord.httpMethod = 'POST';
requestRecord.addHeader('Content-Type', 'application/json');
requestRecord.requestBody = Blob.valueOf(JSON.serialize(payload));

RestContext.request = requestRecord;
RestContext.response = new RestResponse();
CARAOrderRestService.syncOrder();

System.debug(LoggingLevel.ERROR, 'CARA TEST HTTP STATUS: ' + RestContext.response.statusCode);
System.debug(LoggingLevel.ERROR, 'CARA TEST RESPONSE: ' + RestContext.response.responseBody.toString());

if (RestContext.response.statusCode == 200) {
    Order createdOrder = [
        SELECT Id, OrderNumber, OrderReferenceNumber, Status, TotalAmount, AccountId
        FROM Order
        WHERE OrderReferenceNumber = :orderNumber
        LIMIT 1
    ];
    System.debug(LoggingLevel.ERROR, 'CARA ORDER CREATED: ' + JSON.serializePretty(createdOrder));
    System.debug(LoggingLevel.ERROR, 'CARA ORDER RECORD URL: /' + createdOrder.Id);
} else {
    System.debug(LoggingLevel.ERROR, 'CARA ORDER WAS NOT CREATED. Review the response above.');
}
