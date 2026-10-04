@isTest
private class DepositConfirmationInputTest {

    @isTest
    static void testNormalCalculation() {
        DepositConfirmationInput input = new DepositConfirmationInput();
        input.FirstName = 'Ahsan';
        input.orderNumber = 'MM-204583';
        input.paymentDate = 'Monday, 5 October 2026';
        input.cardType = 'Visa';
        input.last4 = '4821';
        input.transactionId = 'TXN-88231';
        input.depositAmount = 1850;
        input.remainingBalance = 5550;

        System.assertEquals('MM-204583', input.orderNumber);
        System.assertEquals('Monday, 5 October 2026', input.paymentDate);
        System.assertEquals('Visa', input.cardType);
        System.assertEquals('4821', input.last4);
        System.assertEquals('TXN-88231', input.transactionId);
        System.assertEquals(1850, input.depositAmount);
        System.assertEquals(5550, input.remainingBalance);

        System.assertEquals(25, input.depositPercent);
        System.assertEquals(75, input.balancePercent);
    }

    @isTest
    static void testZeroTotalEdgeCase() {
        DepositConfirmationInput input = new DepositConfirmationInput();
        input.depositAmount = 0;
        input.remainingBalance = 0;

        System.assertEquals(0, input.depositPercent);
        System.assertEquals(100, input.balancePercent);
    }
}