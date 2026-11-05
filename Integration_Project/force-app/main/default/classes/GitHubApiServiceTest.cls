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
    Assert.areEqual(
      'application/vnd.github+json',
      mock.lastRequest.getHeader('Accept')
    );
    Assert.areEqual(
      '2022-11-28',
      mock.lastRequest.getHeader('X-GitHub-Api-Version')
    );
  }

  @IsTest
  static void unauthorizedThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockResponse(401, '{"message":"Bad credentials"}')
    );

    try {
      GitHubApiService.getAuthenticatedUser();
      Assert.fail('Expected GitHubApiException');
    } catch (GitHubApiService.GitHubApiException e) {
      Assert.areEqual(
        'GitHub request failed (HTTP 401): Authentication failed. Check the GithubAPI named credential. GitHub says: Bad credentials',
        e.getMessage()
      );
      Assert.areEqual(401, e.statusCode);
    }
  }

  @IsTest
  static void serverErrorThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockResponse(500, 'Internal Server Error')
    );

    try {
      GitHubApiService.getAuthenticatedUser();
      Assert.fail('Expected GitHubApiException');
    } catch (GitHubApiService.GitHubApiException e) {
      Assert.areEqual(
        'GitHub request failed (HTTP 500): GitHub is temporarily unavailable. Try again later.',
        e.getMessage()
      );
    }
  }

  private static final String ISSUE_BODY =
    '{"id":1001,"number":42,"html_url":"https://github.com/octocat/repo/issues/42",' +
    '"state":"open","title":"Subscription activation fails"}';

  private static GitHubApiService.CreateIssueRequest newIssue() {
    GitHubApiService.CreateIssueRequest issue = new GitHubApiService.CreateIssueRequest();
    issue.title = 'Subscription activation fails';
    issue.body = 'Steps to reproduce...';
    return issue;
  }

  @IsTest
  static void createIssueReturnsParsedIssue() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    GitHubApiService.IssueResponse result = GitHubApiService.createIssue(
      'octocat',
      'repo',
      newIssue()
    );
    Test.stopTest();

    Assert.areEqual(1001, result.id);
    Assert.areEqual(42, result.issueNumber);
    Assert.areEqual(
      'https://github.com/octocat/repo/issues/42',
      result.htmlUrl
    );
    Assert.areEqual('open', result.state);
    Assert.areEqual('Subscription activation fails', result.title);
  }

  @IsTest
  static void createIssueBuildsRequest() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    GitHubApiService.createIssue('octocat', 'repo', newIssue());
    Test.stopTest();

    Assert.areEqual(
      'callout:GithubAPI/repos/octocat/repo/issues',
      mock.lastRequest.getEndpoint()
    );
    Assert.areEqual('POST', mock.lastRequest.getMethod());
    Assert.areEqual(
      'application/json',
      mock.lastRequest.getHeader('Content-Type')
    );
    Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
      mock.lastRequest.getBody()
    );
    Assert.areEqual('Subscription activation fails', sent.get('title'));
    Assert.areEqual('Steps to reproduce...', sent.get('body'));
  }

  @IsTest
  static void createIssueWithMissingInputsThrows() {
    try {
      GitHubApiService.createIssue('', 'repo', newIssue());
      Assert.fail('Expected GitHubApiException');
    } catch (GitHubApiService.GitHubApiException e) {
      Assert.areEqual(
        'A valid GitHub repository owner is required.',
        e.getMessage()
      );
    }
  }

  @IsTest
  static void createIssueHttpErrorThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockResponse(422, '{"message":"Validation Failed"}')
    );

    try {
      GitHubApiService.createIssue('octocat', 'repo', newIssue());
      Assert.fail('Expected GitHubApiException');
    } catch (GitHubApiService.GitHubApiException e) {
      Assert.areEqual(
        'GitHub request failed (HTTP 422): GitHub rejected the request as invalid. GitHub says: Validation Failed',
        e.getMessage()
      );
      Assert.areEqual(422, e.statusCode);
    }
  }

  @IsTest
  static void createIssueInvalidResponseThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockResponse(201, '{"title":"No id or url"}')
    );

    try {
      GitHubApiService.createIssue('octocat', 'repo', newIssue());
      Assert.fail('Expected GitHubApiException');
    } catch (GitHubApiService.GitHubApiException e) {
      Assert.areEqual('Invalid response from GitHub.', e.getMessage());
    }
  }

  private class FailingMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      throw new CalloutException('Read timed out');
    }
  }

  private static void assertCreateIssueFails(
    String owner,
    String repository,
    GitHubApiService.CreateIssueRequest issue,
    String expected
  ) {
    try {
      GitHubApiService.createIssue(owner, repository, issue);
      Assert.fail('Expected GitHubApiException');
    } catch (GitHubApiService.GitHubApiException e) {
      Assert.areEqual(expected, e.getMessage());
    }
  }

  @IsTest
  static void createIssueRejectsUnsafeRepositoryPath() {
    assertCreateIssueFails(
      'octo/cat',
      'repo',
      newIssue(),
      'A valid GitHub repository owner is required.'
    );
    assertCreateIssueFails(
      'octocat',
      '../other',
      newIssue(),
      'A valid GitHub repository name is required.'
    );
    assertCreateIssueFails(
      'octocat',
      '..',
      newIssue(),
      'A valid GitHub repository name is required.'
    );
    assertCreateIssueFails(
      'octocat',
      '',
      newIssue(),
      'A valid GitHub repository name is required.'
    );
  }

  @IsTest
  static void createIssueRequiresTitle() {
    GitHubApiService.CreateIssueRequest issue = newIssue();
    issue.title = ' ';
    assertCreateIssueFails(
      'octocat',
      'repo',
      issue,
      'An issue title is required.'
    );
    assertCreateIssueFails(
      'octocat',
      'repo',
      null,
      'An issue title is required.'
    );
  }

  @IsTest
  static void createIssueOmitsNullBody() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);
    GitHubApiService.CreateIssueRequest issue = newIssue();
    issue.body = null;

    GitHubApiService.createIssue('octocat', 'repo', issue);

    Assert.isFalse(mock.lastRequest.getBody().contains('"body"'));
  }

  @IsTest
  static void calloutFailureThrowsWithoutStatusCode() {
    Test.setMock(HttpCalloutMock.class, new FailingMock());

    try {
      GitHubApiService.createIssue('octocat', 'repo', newIssue());
      Assert.fail('Expected GitHubApiException');
    } catch (GitHubApiService.GitHubApiException e) {
      Assert.areEqual('Could not reach GitHub: Read timed out', e.getMessage());
      Assert.isNull(e.statusCode);
    }
  }

  @IsTest
  static void nonJsonSuccessBodyThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockResponse(201, '<html>oops</html>')
    );
    assertCreateIssueFails(
      'octocat',
      'repo',
      newIssue(),
      'Invalid response from GitHub.'
    );
  }

  @IsTest
  static void httpErrorExplainsCommonStatusCodes() {
    Map<Integer, String> expected = new Map<Integer, String>{
      403 => 'Access denied, or the GitHub rate limit was exceeded.',
      404 => 'Repository not found, or the credential cannot access it.',
      410 => 'Issues are disabled for this repository.',
      429 => 'GitHub rate limit exceeded. Try again later.',
      418 => 'Unexpected response from GitHub.'
    };
    for (Integer code : expected.keySet()) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(code);
      res.setBody('not json');
      GitHubApiService.GitHubApiException e = GitHubApiService.httpError(res);
      Assert.areEqual(
        'GitHub request failed (HTTP ' + code + '): ' + expected.get(code),
        e.getMessage()
      );
      Assert.areEqual(code, e.statusCode);
    }
  }
}
