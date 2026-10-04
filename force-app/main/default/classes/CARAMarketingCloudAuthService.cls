/*
 * OAuth 2.0 client_credentials token acquisition for Marketing Cloud,
 * mirroring the Postman collection's own two-step flow exactly (a
 * client_credentials POST to .../services/oauth2/token, then the bearer
 * token attached to the actions360 email call) rather than a Named
 * Credential-managed OAuth flow — this keeps every piece of auth
 * configuration in the same proven, already-deployed shape as
 * SFSC_Order_Ops (NoAuthentication Named Credential + a Custom Setting
 * holding the secret), with nothing guessed about a schema this org has
 * never used.
 *
 * The token is cached for the lifetime of the Apex transaction only
 * (static variable) so a single transaction sending multiple emails never
 * re-authenticates more than once; it is never logged or returned to any
 * caller.
 */
public with sharing class CARAMarketingCloudAuthService {

    private static final String TOKEN_NAMED_CREDENTIAL = 'callout:CARA_Marketing_Cloud_Token';
    private static final String TOKEN_PATH = '/services/oauth2/token';

    private static String cachedAccessToken;

    public class AuthException extends Exception {
    }


    public static String getAccessToken() {
        if (String.isNotBlank(cachedAccessToken)) {
            return cachedAccessToken;
        }

        CARA_Marketing_Cloud_Setting__c settings = CARA_Marketing_Cloud_Setting__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.Client_Id__c) || String.isBlank(settings.Client_Secret__c)) {
            throw new AuthException(
                'Marketing Cloud OAuth client credentials are not configured. Set them via ' +
                'Setup > Custom Settings > CARA Marketing Cloud Setting > Manage.'
            );
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(TOKEN_NAMED_CREDENTIAL + TOKEN_PATH);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        request.setBody(
            'grant_type=client_credentials' +
            '&client_id=' + EncodingUtil.urlEncode(settings.Client_Id__c, 'UTF-8') +
            '&client_secret=' + EncodingUtil.urlEncode(settings.Client_Secret__c, 'UTF-8')
        );
        request.setTimeout(20000);

        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (Exception calloutError) {
            throw new AuthException('Marketing Cloud token request failed: ' + calloutError.getMessage());
        }

        if (response.getStatusCode() != 200) {
            throw new AuthException('Marketing Cloud token request returned HTTP ' + response.getStatusCode());
        }

        Map<String, Object> tokenResponse;
        try {
            tokenResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        } catch (Exception parseError) {
            throw new AuthException('Marketing Cloud token response was not valid JSON.');
        }

        String accessToken = (String) tokenResponse.get('access_token');
        if (String.isBlank(accessToken)) {
            throw new AuthException('Marketing Cloud token response did not include an access_token.');
        }

        cachedAccessToken = accessToken;
        return cachedAccessToken;
    }
}