/*
 * Synchronous pre-check run by the "Product Finalized (Quote Accepted)"
 * screen flow BEFORE it sets Status__c = 'Approved'. Uses the exact same
 * rules as CARADepositBasketQueueable (Selling Price, Product with SKU,
 * Mailing Address with a resolvable country code, customer email), so the
 * agent sees what is missing immediately instead of the request flipping to
 * 'Approved' and only failing later in the async deposit-basket job.
 *
 * On failure the request is marked Status__c = 'Failed' with the missing
 * fields appended to Basket_Log__c.
 */
public with sharing class CARADepositBasketPreflight {

    public class Request {
        @InvocableVariable(label='Custom Product Request Id' required=true)
        public Id requestId;
    }

    public class Result {
        @InvocableVariable(label='Is Valid')
        public Boolean isValid;

        @InvocableVariable(label='Missing Fields')
        public String missingFields;
    }

    @InvocableMethod(
        label='Validate Deposit Basket Request'
        description='Checks a Custom Product Request has Selling Price, Product with SKU and a Mailing Address with country code before approval. Marks it Failed if not.'
    )
    public static List<Result> validate(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request input : requests) {
            Result output = new Result();
            Custom_Product_Request__c requestRecord = CARADepositBasketQueueable.queryRequest(input.requestId);

            List<String> missingFields = requestRecord == null
                ? new List<String>{ 'Custom Product Request (not found)' }
                : CARADepositBasketQueueable.findMissingFields(requestRecord);

            output.isValid = missingFields.isEmpty();
            output.missingFields = String.join(missingFields, ', ');

            if (!output.isValid && requestRecord != null) {
                CARADepositBasketQueueable.fail(
                    requestRecord,
                    CARASfscSplitPaymentService.ERROR_PAYLOAD,
                    'Approval blocked — missing: ' + output.missingFields
                );
            }
            results.add(output);
        }
        return results;
    }
}