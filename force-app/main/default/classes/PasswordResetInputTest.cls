@isTest
private class PasswordResetInputTest {

    @isTest
    static void testFieldAssignment() {
        PasswordResetInput input = new PasswordResetInput();
        input.firstName = 'Ahsan';
        input.resetLink = 'https://cara.ae/reset-password?token=a8f3e9b2c1xyz';
        input.expiryTime = '30 minutes';

        System.assertEquals('Ahsan', input.firstName);
        System.assertEquals('https://cara.ae/reset-password?token=a8f3e9b2c1xyz', input.resetLink);
        System.assertEquals('30 minutes', input.expiryTime);
    }
}