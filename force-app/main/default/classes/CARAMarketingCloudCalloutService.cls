/*
 * Thin HTTP wrapper around the Marketing Cloud actions360 email send API,
 * modeled on CARASfscOrderOpsService.callOut() — same typed response shape,
 * same "throw on transport failure, return statusCode/rawBody otherwise"
 * contract. The bearer token comes from CARAMarketingCloudAuthService
 * (client_credentials flow against carajewellers.my.salesforce.com, exactly
 * as in the Postman collection) — never a secret this class touches
 * directly.
 */
public with sharing class CARAMarketingCloudCalloutService {

    private static final String NAMED_CREDENTIAL = 'callout:CARA_Marketing_Cloud';
    private static final String EMAIL_PATH = '/automation/actions360/messaging/email/v1';

    public class McCallException extends Exception {
    }

    public class McResponse {
        public Boolean success;
        public Integer statusCode;
        public String rawBody;
    }


    public static McResponse send(String sendDefinitionId, Map<String, Object> payload) {

        String accessToken;
        try {
            accessToken = CARAMarketingCloudAuthService.getAccessToken();
        } catch (CARAMarketingCloudAuthService.AuthException authError) {
            throw new McCallException(authError.getMessage());
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(
            NAMED_CREDENTIAL + EMAIL_PATH + '?sendDefinitionId=' + EncodingUtil.urlEncode(sendDefinitionId, 'UTF-8')
        );
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Authorization', 'Bearer ' + accessToken);
        request.setBody(JSON.serialize(payload));
        request.setTimeout(20000);

        HttpResponse httpResponse;

        try {
            httpResponse = new Http().send(request);
        } catch (Exception calloutError) {
            throw new McCallException('Marketing Cloud callout failed: ' + calloutError.getMessage());
        }

        McResponse result = new McResponse();
        result.statusCode = httpResponse.getStatusCode();
        result.rawBody = httpResponse.getBody();
        result.success = httpResponse.getStatusCode() >= 200
            && httpResponse.getStatusCode() < 300;

        return result;
    }
}