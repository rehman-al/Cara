@IsTest
private class CARASplitPaymentSettingsTest {

    /*
     * The "Default" Split_Payment_Setting__mdt record ships with the
     * deployment, so these assert against its actual deployed values
     * rather than faking custom metadata (which Apex tests cannot insert).
     */
    @IsTest
    static void getDepositPercentageReturnsConfiguredValue() {
        System.assertEquals(0.25, CARASplitPaymentSettings.getDepositPercentage());
    }


    @IsTest
    static void getMaxRetryAttemptsReturnsConfiguredValue() {
        System.assertEquals(2, CARASplitPaymentSettings.getMaxRetryAttempts());
    }


    @IsTest
    static void getRetryableStatusCodesParsesConfiguredValue() {
        Set<Integer> codes = CARASplitPaymentSettings.getRetryableStatusCodes();
        System.assert(codes.contains(502));
        System.assertEquals(1, codes.size());
    }
}