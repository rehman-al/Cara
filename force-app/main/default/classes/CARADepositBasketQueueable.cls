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

        /*
         * Validated here, at the actual request-submission point, before
         * the first (Link 1 deposit) callout — and BEFORE the idempotency
         * guard, so a request re-approved after its data was broken (e.g.
         * Product cleared on a request that already has a basket) is still
         * marked Failed instead of silently staying 'Approved'. The same
         * check runs synchronously from the "Product Finalized" button via
         * CARADepositBasketPreflight, so every entry point shares one rule set.
         */
        List<String> missingFields = findMissingFields(requestRecord);
        if (!missingFields.isEmpty()) {
            fail(
                requestRecord,
                CARASfscSplitPaymentService.ERROR_PAYLOAD,
                'Cannot create deposit basket — missing: ' + String.join(missingFields, ', ')
            );
            return;
        }

        // Idempotency guard: never re-create a basket that already exists.
        if (String.isNotBlank(requestRecord.Basket_Id__c) && requestRecord.Basket_Status__c == 'Created') {
            return;
        }

        Contact customerContact = requestRecord.Case__r.Contact;
        String customerLogin = customerContact.Email;
        String sku = requestRecord.Product__r.StockKeepingUnit;
        Decimal price = requestRecord.Selling_Price__c;

        Decimal depositAmount = (price * CARASplitPaymentSettings.getDepositPercentage()).setScale(2);

        CARASfscSplitPaymentService.DepositBasketRequest depositRequest =
            new CARASfscSplitPaymentService.DepositBasketRequest();
        depositRequest.customerLogin = customerLogin;
        depositRequest.sku = sku;
        depositRequest.price = price;
        depositRequest.deposit = depositAmount;
        depositRequest.shippingAddress = buildShippingAddress(requestRecord.Case__r.Contact);
        depositRequest.cprNumber = requestRecord.Name;

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


    /*
     * Everything the SFCC/MRT deposit-basket request needs: customer email,
     * Selling Price, Product with a SKU, and a full Mailing Address whose
     * country resolves to an ISO alpha-2 code. Returns readable names of
     * whatever is missing (empty = valid). Expects a queryRequest() record.
     */
    public static List<String> findMissingFields(Custom_Product_Request__c requestRecord) {
        Contact customerContact = requestRecord.Case__r != null ? requestRecord.Case__r.Contact : null;
        String sku = requestRecord.Product__r != null ? requestRecord.Product__r.StockKeepingUnit : null;
        String normalizedCountryCode = customerContact != null
            ? normalizeCountryCode(customerContact.MailingCountry)
            : null;

        List<String> missingFields = new List<String>();
        if (customerContact == null || String.isBlank(customerContact.Email)) {
            missingFields.add('customer email (Case Contact)');
        }
        if (requestRecord.Selling_Price__c == null || requestRecord.Selling_Price__c <= 0) {
            missingFields.add('Selling Price');
        }
        if (requestRecord.Product__c == null) {
            missingFields.add('Product');
        }
        if (String.isBlank(sku)) {
            missingFields.add('Product SKU');
        }
        if (customerContact == null
            || String.isBlank(customerContact.MailingStreet)
            || String.isBlank(customerContact.MailingCity)
            || (String.isBlank(customerContact.MailingPostalCode)
                && !COUNTRIES_WITHOUT_POSTAL_CODE.contains(normalizedCountryCode))) {
            missingFields.add('Mailing Address');
        }
        if (normalizedCountryCode == null || normalizedCountryCode.length() != 2) {
            missingFields.add('Mailing Address Country Code');
        }
        return missingFields;
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
        address.countryCode = normalizeCountryCode(customerContact.MailingCountry);
        address.postalCode = String.isBlank(customerContact.MailingPostalCode)
            && COUNTRIES_WITHOUT_POSTAL_CODE.contains(address.countryCode)
            ? NO_POSTAL_CODE_PLACEHOLDER
            : customerContact.MailingPostalCode;
        address.phone = customerContact.Phone;

        return address;
    }


    /*
     * State/country picklists are not enabled in this org (no
     * MailingCountryCode field exists), so MailingCountry is free text —
     * agents editing a Contact by hand can type the full country name
     * instead of the ISO 3166-1 alpha-2 code SFCC's Shopper Baskets API
     * requires for shippingAddress.countryCode ("value constraint
     * violation of property 'countryCode'"). Orders synced back from SFCC
     * already store the ISO code (see CARAOrderSyncService), so this only
     * has to translate the hand-typed case.
     */
    private static String normalizeCountryCode(String rawCountry) {
        if (String.isBlank(rawCountry)) {
            return null;
        }

        String trimmed = rawCountry.trim();
        if (trimmed.length() == 2) {
            return trimmed.toUpperCase();
        }

        String mapped = COUNTRY_ISO_CODE_BY_NAME.get(trimmed.toUpperCase());
        return mapped != null ? mapped : trimmed.toUpperCase();
    }

    /*
     * Countries with no postal code system (UAE, Qatar, Hong Kong, etc.).
     * A blank MailingPostalCode is valid for these, and SFCC is sent the
     * conventional '00000' placeholder so the basket address stays complete.
     */
    @TestVisible
    private static final String NO_POSTAL_CODE_PLACEHOLDER = '00000';

    private static final Set<String> COUNTRIES_WITHOUT_POSTAL_CODE = new Set<String>{
        'AE', 'AG', 'AO', 'AW', 'BF', 'BI', 'BJ', 'BO', 'BS', 'BW', 'BZ', 'CD', 'CF', 'CG',
        'CI', 'CK', 'CM', 'DJ', 'DM', 'ER', 'FJ', 'GA', 'GD', 'GH', 'GM', 'GQ', 'GY', 'HK',
        'JM', 'KI', 'KM', 'KN', 'KP', 'LC', 'ML', 'MO', 'MR', 'MW', 'NR', 'NU', 'QA', 'RW',
        'SB', 'SC', 'SL', 'SO', 'SR', 'ST', 'SY', 'TD', 'TG', 'TK', 'TL', 'TO', 'TV', 'UG',
        'VU', 'YE', 'ZW'
    };

    private static final Map<String, String> COUNTRY_ISO_CODE_BY_NAME = new Map<String, String>{
        'AFGHANISTAN' => 'AF', 'ALBANIA' => 'AL', 'ALGERIA' => 'DZ', 'ANDORRA' => 'AD',
        'ANGOLA' => 'AO', 'ANTIGUA AND BARBUDA' => 'AG', 'ARGENTINA' => 'AR', 'ARMENIA' => 'AM',
        'AUSTRALIA' => 'AU', 'AUSTRIA' => 'AT', 'AZERBAIJAN' => 'AZ', 'BAHAMAS' => 'BS',
        'BAHRAIN' => 'BH', 'BANGLADESH' => 'BD', 'BARBADOS' => 'BB', 'BELARUS' => 'BY',
        'BELGIUM' => 'BE', 'BELIZE' => 'BZ', 'BENIN' => 'BJ', 'BHUTAN' => 'BT',
        'BOLIVIA' => 'BO', 'BOSNIA AND HERZEGOVINA' => 'BA', 'BOTSWANA' => 'BW', 'BRAZIL' => 'BR',
        'BRUNEI' => 'BN', 'BULGARIA' => 'BG', 'BURKINA FASO' => 'BF', 'BURUNDI' => 'BI',
        'CAMBODIA' => 'KH', 'CAMEROON' => 'CM', 'CANADA' => 'CA', 'CAPE VERDE' => 'CV',
        'CENTRAL AFRICAN REPUBLIC' => 'CF', 'CHAD' => 'TD', 'CHILE' => 'CL', 'CHINA' => 'CN',
        'COLOMBIA' => 'CO', 'COMOROS' => 'KM', 'CONGO' => 'CG',
        'DEMOCRATIC REPUBLIC OF THE CONGO' => 'CD', 'COSTA RICA' => 'CR', 'COTE D\'IVOIRE' => 'CI',
        'CROATIA' => 'HR', 'CUBA' => 'CU', 'CYPRUS' => 'CY', 'CZECH REPUBLIC' => 'CZ',
        'CZECHIA' => 'CZ', 'DENMARK' => 'DK', 'DJIBOUTI' => 'DJ', 'DOMINICA' => 'DM',
        'DOMINICAN REPUBLIC' => 'DO', 'ECUADOR' => 'EC', 'EGYPT' => 'EG', 'EL SALVADOR' => 'SV',
        'EQUATORIAL GUINEA' => 'GQ', 'ERITREA' => 'ER', 'ESTONIA' => 'EE', 'ESWATINI' => 'SZ',
        'ETHIOPIA' => 'ET', 'FIJI' => 'FJ', 'FINLAND' => 'FI', 'FRANCE' => 'FR',
        'GABON' => 'GA', 'GAMBIA' => 'GM', 'GEORGIA' => 'GE', 'GERMANY' => 'DE',
        'GHANA' => 'GH', 'GREECE' => 'GR', 'GRENADA' => 'GD', 'GUATEMALA' => 'GT',
        'GUINEA' => 'GN', 'GUINEA-BISSAU' => 'GW', 'GUYANA' => 'GY', 'HAITI' => 'HT',
        'HONDURAS' => 'HN', 'HONG KONG' => 'HK', 'HUNGARY' => 'HU', 'ICELAND' => 'IS',
        'INDIA' => 'IN', 'INDONESIA' => 'ID', 'IRAN' => 'IR', 'IRAQ' => 'IQ',
        'IRELAND' => 'IE', 'ISRAEL' => 'IL', 'ITALY' => 'IT', 'JAMAICA' => 'JM',
        'JAPAN' => 'JP', 'JORDAN' => 'JO', 'KAZAKHSTAN' => 'KZ', 'KENYA' => 'KE',
        'KIRIBATI' => 'KI', 'KOSOVO' => 'XK', 'KUWAIT' => 'KW', 'KYRGYZSTAN' => 'KG',
        'LAOS' => 'LA', 'LATVIA' => 'LV', 'LEBANON' => 'LB', 'LESOTHO' => 'LS',
        'LIBERIA' => 'LR', 'LIBYA' => 'LY', 'LIECHTENSTEIN' => 'LI', 'LITHUANIA' => 'LT',
        'LUXEMBOURG' => 'LU', 'MACAU' => 'MO', 'MADAGASCAR' => 'MG', 'MALAWI' => 'MW',
        'MALAYSIA' => 'MY', 'MALDIVES' => 'MV', 'MALI' => 'ML', 'MALTA' => 'MT',
        'MARSHALL ISLANDS' => 'MH', 'MAURITANIA' => 'MR', 'MAURITIUS' => 'MU', 'MEXICO' => 'MX',
        'MICRONESIA' => 'FM', 'MOLDOVA' => 'MD', 'MONACO' => 'MC', 'MONGOLIA' => 'MN',
        'MONTENEGRO' => 'ME', 'MOROCCO' => 'MA', 'MOZAMBIQUE' => 'MZ', 'MYANMAR' => 'MM',
        'NAMIBIA' => 'NA', 'NAURU' => 'NR', 'NEPAL' => 'NP', 'NETHERLANDS' => 'NL',
        'NEW ZEALAND' => 'NZ', 'NICARAGUA' => 'NI', 'NIGER' => 'NE', 'NIGERIA' => 'NG',
        'NORTH KOREA' => 'KP', 'NORTH MACEDONIA' => 'MK', 'NORWAY' => 'NO', 'OMAN' => 'OM',
        'PAKISTAN' => 'PK', 'PALAU' => 'PW', 'PALESTINE' => 'PS', 'PANAMA' => 'PA',
        'PAPUA NEW GUINEA' => 'PG', 'PARAGUAY' => 'PY', 'PERU' => 'PE', 'PHILIPPINES' => 'PH',
        'POLAND' => 'PL', 'PORTUGAL' => 'PT', 'QATAR' => 'QA', 'ROMANIA' => 'RO',
        'RUSSIA' => 'RU', 'RWANDA' => 'RW', 'SAINT BARTHELEMY' => 'BL', 'SAINT BARTHÉLEMY' => 'BL',
        'SAINT KITTS AND NEVIS' => 'KN', 'SAINT LUCIA' => 'LC',
        'SAINT VINCENT AND THE GRENADINES' => 'VC', 'SAMOA' => 'WS', 'SAN MARINO' => 'SM',
        'SAO TOME AND PRINCIPE' => 'ST', 'SAUDI ARABIA' => 'SA', 'SENEGAL' => 'SN',
        'SERBIA' => 'RS', 'SEYCHELLES' => 'SC', 'SIERRA LEONE' => 'SL', 'SINGAPORE' => 'SG',
        'SLOVAKIA' => 'SK', 'SLOVENIA' => 'SI', 'SOLOMON ISLANDS' => 'SB', 'SOMALIA' => 'SO',
        'SOUTH AFRICA' => 'ZA', 'SOUTH KOREA' => 'KR', 'SOUTH SUDAN' => 'SS', 'SPAIN' => 'ES',
        'SRI LANKA' => 'LK', 'SUDAN' => 'SD', 'SURINAME' => 'SR', 'SWEDEN' => 'SE',
        'SWITZERLAND' => 'CH', 'SYRIA' => 'SY', 'TAIWAN' => 'TW', 'TAJIKISTAN' => 'TJ',
        'TANZANIA' => 'TZ', 'THAILAND' => 'TH', 'TIMOR-LESTE' => 'TL', 'TOGO' => 'TG',
        'TONGA' => 'TO', 'TRINIDAD AND TOBAGO' => 'TT', 'TUNISIA' => 'TN', 'TURKEY' => 'TR',
        'TURKMENISTAN' => 'TM', 'TUVALU' => 'TV', 'UGANDA' => 'UG', 'UKRAINE' => 'UA',
        'UNITED ARAB EMIRATES' => 'AE', 'UNITED KINGDOM' => 'GB', 'UNITED STATES' => 'US',
        'UNITED STATES OF AMERICA' => 'US', 'URUGUAY' => 'UY', 'UZBEKISTAN' => 'UZ',
        'VANUATU' => 'VU', 'VATICAN CITY' => 'VA', 'VENEZUELA' => 'VE', 'VIETNAM' => 'VN',
        'YEMEN' => 'YE', 'ZAMBIA' => 'ZM', 'ZIMBABWE' => 'ZW'
    };


    public static Custom_Product_Request__c queryRequest(Id requestId) {
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


    /*
     * Status__c -> 'Failed' so a request whose deposit basket was never
     * created (validation failure, API error or unexpected exception) no
     * longer sits as 'Approved'. Re-approving it re-fires the approval Flow.
     */
    public static void fail(Custom_Product_Request__c requestRecord, String errorCategory, String errorMessage) {
        requestRecord.Status__c = 'Failed';
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