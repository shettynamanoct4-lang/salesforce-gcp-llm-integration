/**
 * @description Routes mocked HTTP callouts for every endpoint used in this project.
 * @author      Naman G Shetty
 */
@IsTest
public class AiServiceMock implements HttpCalloutMock {

    public Integer statusCode = 200;
    public Map<Id, String> predictionsById = new Map<Id, String>();

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        String endpoint = req.getEndpoint();

        if (endpoint.contains('oauth2.googleapis.com')) {
            res.setStatusCode(200);
            res.setBody('{"id_token":"test-id-token"}');
            return res;
        }

        res.setStatusCode(statusCode);
        if (endpoint.endsWith('/api/v1/summarize')) {
            res.setBody('{"summary":["Customer reports billing issue","Refund promised by Friday"]}');
        } else if (endpoint.endsWith('/api/v1/taxonomy')) {
            res.setBody('{"status":"ok"}');
        } else if (endpoint.endsWith('/api/v1/enrich')) {
            List<String> rows = new List<String>();
            for (Id recordId : predictionsById.keySet()) {
                rows.add('{"id":"' + recordId + '",' + predictionsById.get(recordId) + '}');
            }
            res.setBody('{"predictions":[' + String.join(rows, ',') + ']}');
        }
        return res;
    }
}
