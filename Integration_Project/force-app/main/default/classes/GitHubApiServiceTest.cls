@IsTest
private class GitHubApiServiceTest {
    private static final String SUCCESS_BODY = '{"login":"octocat","id":1,"name":"The Octocat"}';

    private class MockResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        public HttpRequest lastRequest;

        MockResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            lastRequest = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }
    }

    @IsTest
    static void getAuthenticatedUserReturnsBody() {
        MockResponse mock = new MockResponse(200, SUCCESS_BODY);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String body = GitHubApiService.getAuthenticatedUser();
        Test.stopTest();

        Assert.areEqual(SUCCESS_BODY, body);
    }

    @IsTest
    static void getAuthenticatedUserBuildsRequest() {
        MockResponse mock = new MockResponse(200, SUCCESS_BODY);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GitHubApiService.getAuthenticatedUser();
        Test.stopTest();

        Assert.areEqual('callout:GithubAPI/user', mock.lastRequest.getEndpoint());
        Assert.areEqual('GET', mock.lastRequest.getMethod());
        Assert.areEqual('application/vnd.github.v3+json', mock.lastRequest.getHeader('Accept'));
        Assert.areEqual('2022-11-28', mock.lastRequest.getHeader('X-GitHub-Api-Version'));
    }

    @IsTest
    static void unauthorizedThrows() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(401, '{"message":"Bad credentials"}'));

        try {
            GitHubApiService.getAuthenticatedUser();
            Assert.fail('Expected GitHubApiException');
        } catch (GitHubApiService.GitHubApiException e) {
            Assert.areEqual('GitHub request failed. HTTP status: 401', e.getMessage());
        }
    }

    @IsTest
    static void serverErrorThrows() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(500, 'Internal Server Error'));

        try {
            GitHubApiService.getAuthenticatedUser();
            Assert.fail('Expected GitHubApiException');
        } catch (GitHubApiService.GitHubApiException e) {
            Assert.areEqual('GitHub request failed. HTTP status: 500', e.getMessage());
        }
    }
}
