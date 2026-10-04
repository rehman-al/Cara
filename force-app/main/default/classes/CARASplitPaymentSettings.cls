/*
 * Admin-configurable knobs for the N-Genius split-payment integration,
 * backed by the Split_Payment_Setting__mdt custom metadata type (record
 * "Default"). Custom Metadata is used rather than a Custom Setting because
 * these values are the same across the org (no per-profile/per-user
 * override needed) and, unlike Custom Settings, ship with the deployment
 * and are visible/editable to admins under Setup > Custom Metadata Types
 * without an Apex change.
 *
 * Falls back to hardcoded defaults if the record is ever missing (e.g. a
 * sandbox where it hasn't been deployed yet) so a config gap degrades to
 * "current behavior" rather than breaking the integration outright.
 */
public with sharing class CARASplitPaymentSettings {

    private static final String DEFAULT_RECORD_NAME = 'Default';
    private static final Decimal FALLBACK_DEPOSIT_PERCENTAGE = 0.25;
    private static final Integer FALLBACK_MAX_RETRY_ATTEMPTS = 2;
    private static final Set<Integer> FALLBACK_RETRYABLE_STATUS_CODES = new Set<Integer>{ 502 };

    private static Split_Payment_Setting__mdt cachedSetting;
    private static Boolean loaded = false;


    public static Decimal getDepositPercentage() {
        Split_Payment_Setting__mdt setting = getSetting();
        return setting != null && setting.Deposit_Percentage__c != null
            ? setting.Deposit_Percentage__c
            : FALLBACK_DEPOSIT_PERCENTAGE;
    }


    public static Integer getMaxRetryAttempts() {
        Split_Payment_Setting__mdt setting = getSetting();
        return setting != null && setting.Max_Retry_Attempts__c != null
            ? setting.Max_Retry_Attempts__c.intValue()
            : FALLBACK_MAX_RETRY_ATTEMPTS;
    }


    public static Set<Integer> getRetryableStatusCodes() {
        Split_Payment_Setting__mdt setting = getSetting();

        if (setting == null || String.isBlank(setting.Retryable_Status_Codes__c)) {
            return FALLBACK_RETRYABLE_STATUS_CODES;
        }

        Set<Integer> statusCodes = new Set<Integer>();
        for (String codeText : setting.Retryable_Status_Codes__c.split(',')) {
            if (String.isNotBlank(codeText) && codeText.trim().isNumeric()) {
                statusCodes.add(Integer.valueOf(codeText.trim()));
            }
        }

        return statusCodes.isEmpty() ? FALLBACK_RETRYABLE_STATUS_CODES : statusCodes;
    }


    private static Split_Payment_Setting__mdt getSetting() {
        if (!loaded) {
            loaded = true;
            List<Split_Payment_Setting__mdt> records = [
                SELECT Deposit_Percentage__c, Max_Retry_Attempts__c, Retryable_Status_Codes__c
                FROM Split_Payment_Setting__mdt
                WHERE DeveloperName = :DEFAULT_RECORD_NAME
                LIMIT 1
            ];
            cachedSetting = records.isEmpty() ? null : records[0];
        }
        return cachedSetting;
    }
}