@RestResource(urlMapping='/cara/stores')
global with sharing class CARAStoreRestService {

    @HttpGet
    global static void getStores() {

        try {

            Boolean useArabic = isArabic(
                RestContext.request.params.get('lang')
            );

            List<Store__c> stores = [
                SELECT
                    Id,
                    Name,
                    Address__c,
                    Name_AR__c,
                    Address_AR__c,
                    Active__c
                FROM Store__c
                WHERE Active__c = true
                ORDER BY Name
            ];

            StoreListResponse responseBody = new StoreListResponse();
            responseBody.success = true;
            responseBody.stores = new List<StoreDetail>();
            responseBody.interestCategories =
                CARAAppointmentApiSupport.getInterestCategories();

            for (Store__c storeRecord : stores) {

                StoreDetail storeDetail = new StoreDetail();
                storeDetail.storeId = String.valueOf(storeRecord.Id);

                storeDetail.storeName = useArabic
                    ? firstNonBlank(storeRecord.Name_AR__c, storeRecord.Name)
                    : storeRecord.Name;

                storeDetail.address = useArabic
                    ? firstNonBlank(storeRecord.Address_AR__c, storeRecord.Address__c)
                    : storeRecord.Address__c;

                responseBody.stores.add(storeDetail);
            }

            CARAAppointmentApiSupport.writeResponse(200, responseBody);

        } catch (Exception error) {

            System.debug(
                LoggingLevel.ERROR,
                'Store list API error: ' + error.getMessage()
            );

            CARAAppointmentApiSupport.writeError(
                500,
                'Unable to retrieve store list.'
            );
        }
    }


    // =========================================================
    // LOCALIZATION HELPERS
    // =========================================================

    private static Boolean isArabic(String langValue) {
        return String.isNotBlank(langValue)
            && langValue.trim().equalsIgnoreCase('ar');
    }


    private static String firstNonBlank(String preferredValue, String fallbackValue) {
        return String.isNotBlank(preferredValue) ? preferredValue : fallbackValue;
    }


    public class StoreListResponse {
        public Boolean success;
        public List<StoreDetail> stores;
        public List<CARAAppointmentApiSupport.InterestCategory> interestCategories;
    }


    public class StoreDetail {
        public String storeId;
        public String storeName;
        public String address;
    }
}