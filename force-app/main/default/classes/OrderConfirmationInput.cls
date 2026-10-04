public class OrderConfirmationInput {
    // Personalization
    @AuraEnabled public String firstName { get; set; }
    @AuraEnabled public String orderLink { get; set; }

    // Basic Order Info
    @AuraEnabled public String orderNumber { get; set; }
    @AuraEnabled public String orderDate { get; set; }
    @AuraEnabled public String estimatedDelivery { get; set; }
    @AuraEnabled public String deliveryAddressLine1 { get; set; }
    @AuraEnabled public String deliveryAddressLine2 { get; set; }

    // Order Summary
    @AuraEnabled public Integer itemCount { get; set; }
    @AuraEnabled public String currencyCode { get; set; }
    @AuraEnabled public Decimal itemTotal { get; set; }
    @AuraEnabled public String totalWeight { get; set; }
    @AuraEnabled public Decimal subtotal { get; set; }
    @AuraEnabled public Decimal shipping { get; set; }
    @AuraEnabled public Decimal total { get; set; }

    // Payment Details
    @AuraEnabled public String cardType { get; set; }
    @AuraEnabled public String last4 { get; set; }
    @AuraEnabled public String paymentStatus { get; set; }

    // Fixed item slots (replaces List<CartItem> — repeater didn't render with Apex-based lists)
    @AuraEnabled public String item1Name { get; set; }
    @AuraEnabled public Decimal item1Price { get; set; }
    @AuraEnabled public Integer item1Qty { get; set; }
    @AuraEnabled public String item1ImageUrl { get; set; }

    @AuraEnabled public String item2Name { get; set; }
    @AuraEnabled public Decimal item2Price { get; set; }
    @AuraEnabled public Integer item2Qty { get; set; }
    @AuraEnabled public String item2ImageUrl { get; set; }

    @AuraEnabled public String item3Name { get; set; }
    @AuraEnabled public Decimal item3Price { get; set; }
    @AuraEnabled public Integer item3Qty { get; set; }
    @AuraEnabled public String item3ImageUrl { get; set; }

    @AuraEnabled public String item4Name { get; set; }
    @AuraEnabled public Decimal item4Price { get; set; }
    @AuraEnabled public Integer item4Qty { get; set; }
    @AuraEnabled public String item4ImageUrl { get; set; }

    @AuraEnabled public String item5Name { get; set; }
    @AuraEnabled public Decimal item5Price { get; set; }
    @AuraEnabled public Integer item5Qty { get; set; }
    @AuraEnabled public String item5ImageUrl { get; set; }
}