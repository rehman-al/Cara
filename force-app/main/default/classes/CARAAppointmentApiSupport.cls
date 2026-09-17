public with sharing class CARAAppointmentApiSupport {

    public static void writeResponse(
        Integer statusCode,
        Object responseBody
    ) {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }

        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader(
            'Content-Type',
            'application/json'
        );
        RestContext.response.addHeader(
            'Cache-Control',
            'no-store'
        );

        RestContext.response.responseBody = Blob.valueOf(
            JSON.serialize(responseBody)
        );
    }


    public static void writeError(
        Integer statusCode,
        String message
    ) {
        ErrorResponse responseBody = new ErrorResponse();

        responseBody.success = false;
        responseBody.message = message;

        writeResponse(
            statusCode,
            responseBody
        );
    }


    public class ErrorResponse {
        public Boolean success;
        public String message;
    }


    public class RequestException extends Exception {
    }


    public class ConflictException extends Exception {
    }


    // =========================================================
    // INTEREST CATEGORIES
    // =========================================================

    /*
     * Single source of truth for the "what are you interested in"
     * options. The id is the stable wire contract SFCC sends back
     * on booking; the label is what is written to the existing
     * interested_in__c picklist. Keeping this list here means the
     * store API and the booking validator can never drift apart.
     *
     * Adding, renaming, or retiring a category is a deliberate code
     * change + deploy — not self-service. That trade was made on
     * purpose: it keeps the id (the part SFCC depends on) from ever
     * changing silently.
     */
    private static final List<String> INTEREST_CATEGORY_IDS =
        new List<String>{
            'general',
            'bridal',
            'high-jewellery',
            'repairs'
        };

    private static final Map<String, String> INTEREST_LABELS_BY_ID =
        new Map<String, String>{
            'general' => 'General appointment',
            'bridal' => 'Bridal & engagement',
            'high-jewellery' => 'High jewellery',
            'repairs' => 'Repairs & servicing'
        };

    public static List<InterestCategory> getInterestCategories() {

        List<InterestCategory> categories = new List<InterestCategory>();

        for (String categoryId : INTEREST_CATEGORY_IDS) {

            InterestCategory category = new InterestCategory();
            category.id = categoryId;
            category.label = INTEREST_LABELS_BY_ID.get(categoryId);

            categories.add(category);
        }

        return categories;
    }


    /*
     * Returns the picklist label for a category id, or null if the
     * id is blank or unrecognized. Callers decide how to treat null.
     */
    public static String getInterestLabelById(String interestId) {

        if (String.isBlank(interestId)) {
            return null;
        }

        return INTEREST_LABELS_BY_ID.get(
            interestId.trim().toLowerCase()
        );
    }


    public class InterestCategory {
        public String id;
        public String label;
    }
}