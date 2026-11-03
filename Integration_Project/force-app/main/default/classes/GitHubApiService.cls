public with sharing class GitHubApiService {
    public static String getAuthenticatedUser() {
        Httprequest req = new HttpRequest();
        req.setEndpoint('callout:GithubAPI/user');
        req.setMethod('GET');
        req.setheader('Accept', 'application/vnd.github.v3+json');
        req.setHeader('X-GitHub-Api-Version', '2022-11-28');
        req.setTimeout(10000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        Integer statusCode = res.getStatusCode();
        System.debug('GitHub HTTP Status: ' + statusCode);

        if(statusCode == 200) {
            return res.getBody();
        }

        throw new GitHubApiException('GitHub request failed. HTTP status: ' + statusCode);
        
    }

    public class GitHubApiException extends Exception {}
}