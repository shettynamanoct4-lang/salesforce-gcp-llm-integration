/**
 * @description Mints short-lived Google identity tokens so Apex can call a private Cloud Run service.
 *              Flow: build an RS256 JWT for the GCP service account -> sign it with a Salesforce
 *              certificate -> exchange it at Google's OAuth endpoint for an id_token.
 * @author      Naman G Shetty
 */
public with sharing class GcpAuthService {

    @TestVisible
    private static final String TOKEN_URL = 'https://oauth2.googleapis.com/token';
    private static final Integer TOKEN_TTL_SECONDS = 3600;

    @TestVisible
    private static String mockSignature;

    /**
     * @description Returns an identity token whose audience is the given Cloud Run URL.
     * @param  audience Exact Cloud Run service URL.
     * @return Google-signed id_token to send as `Authorization: Bearer <token>`.
     */
    public static String getIdentityToken(String audience) {
        AI_Service_Settings__c settings = AI_Service_Settings__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.Service_Account_Email__c)) {
            throw new GcpAuthException('AI_Service_Settings__c is not configured.');
        }

        String assertion = buildSignedJwt(settings, audience);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(TOKEN_URL);
        req.setMethod('POST');
        req.setTimeout(20000);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody('grant_type=' + EncodingUtil.urlEncode('urn:ietf:params:oauth:grant-type:jwt-bearer', 'UTF-8')
            + '&assertion=' + assertion);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new GcpAuthException('Token exchange failed: HTTP ' + res.getStatusCode());
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) body.get('id_token');
    }

    @TestVisible
    private static String buildSignedJwt(AI_Service_Settings__c settings, String audience) {
        Long issuedAt = Datetime.now().getTime() / 1000;
        Map<String, Object> header = new Map<String, Object>{ 'alg' => 'RS256', 'typ' => 'JWT' };
        Map<String, Object> claims = new Map<String, Object>{
            'iss' => settings.Service_Account_Email__c,
            'sub' => settings.Service_Account_Email__c,
            'aud' => TOKEN_URL,
            'iat' => issuedAt,
            'exp' => issuedAt + TOKEN_TTL_SECONDS,
            'target_audience' => audience
        };

        String unsigned = base64Url(Blob.valueOf(JSON.serialize(header)))
            + '.' + base64Url(Blob.valueOf(JSON.serialize(claims)));

        String signature = Test.isRunningTest() && mockSignature != null
            ? mockSignature
            : base64Url(Crypto.signWithCertificate('RSA-SHA256', Blob.valueOf(unsigned), settings.Certificate_Name__c));

        return unsigned + '.' + signature;
    }

    private static String base64Url(Blob input) {
        return EncodingUtil.base64Encode(input).replace('+', '-').replace('/', '_').replace('=', '');
    }

    public class GcpAuthException extends Exception {}
}
