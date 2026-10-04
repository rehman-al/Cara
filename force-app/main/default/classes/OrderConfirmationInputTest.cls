@isTest
private class OrderConfirmationInputTest {
    @isTest
    static void testOrderConfirmationInputStructure() {
        OrderConfirmationInput input = new OrderConfirmationInput();

        input.firstName = 'Ahsan';
        input.orderLink = 'https://cara.ae/orders/ORD-9988?token=abc123xyz';
        input.orderNumber = 'ORD-9988';
        input.orderDate = '5 October 2026';
        input.estimatedDelivery = '3-5 business days';
        input.deliveryAddressLine1 = 'House 12, Street 5';
        input.deliveryAddressLine2 = 'Lahore, Pakistan';

        input.itemCount = 5;
        input.currencyCode = 'AED';
        input.itemTotal = 25000;
        input.totalWeight = '1.2 kg';
        input.subtotal = 25000;
        input.shipping = 0;
        input.total = 25000;

        input.cardType = 'Visa';
        input.last4 = '4821';
        input.paymentStatus = 'Paid';

        // Item 1
        input.item1Name = 'Diamond Ring';
        input.item1Price = 8000;
        input.item1Qty = 1;
        input.item1ImageUrl = 'https://example.com/ring.jpg';

        // Item 2
        input.item2Name = 'Gold Necklace';
        input.item2Price = 7000;
        input.item2Qty = 1;
        input.item2ImageUrl = 'https://example.com/necklace.jpg';

        // Item 3
        input.item3Name = 'Silver Bracelet';
        input.item3Price = 3000;
        input.item3Qty = 2;
        input.item3ImageUrl = 'https://example.com/bracelet.jpg';

        // Item 4
        input.item4Name = 'Pearl Earrings';
        input.item4Price = 4000;
        input.item4Qty = 1;
        input.item4ImageUrl = 'https://example.com/earrings.jpg';

        // Item 5
        input.item5Name = 'Platinum Pendant';
        input.item5Price = 3000;
        input.item5Qty = 1;
        input.item5ImageUrl = 'https://example.com/pendant.jpg';

        // Assertions
        System.assertEquals('Ahsan', input.firstName);
        System.assertEquals('ORD-9988', input.orderNumber);
        System.assertEquals('Diamond Ring', input.item1Name);
        System.assertEquals(8000, input.item1Price);
        System.assertEquals('Gold Necklace', input.item2Name);
        System.assertEquals('Silver Bracelet', input.item3Name);
        System.assertEquals('Pearl Earrings', input.item4Name);
        System.assertEquals('Platinum Pendant', input.item5Name);
        System.assertEquals(25000, input.total);
    }
}