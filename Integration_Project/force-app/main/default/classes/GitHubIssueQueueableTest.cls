@IsTest
private class GitHubIssueQueueableTest {
  private static final String ISSUE_BODY = '{"id":1001,"number":42,"html_url":"https://github.com/octocat/test-repo/issues/42","state":"open","title":"t"}';

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

  @TestSetup
  static void setup() {
    insert new Case(
      Subject = 'Subscription activation fails',
      Description = 'Steps to reproduce...',
      Status = 'New',
      Origin = 'Web',
      Priority = 'High',
      Engineering_Sync_Status__c = 'Pending'
    );
  }

  private static void useTestRepository() {
    GitHubIssueQueueable.settings = new GitHub_Integration_Setting__mdt(
      Repository_Owner__c = 'octocat',
      Repository_Name__c = 'test-repo'
    );
  }

  private static Case getCase() {
    return [
      SELECT
        Id,
        CaseNumber,
        GitHub_Issue_ID__c,
        GitHub_Issue_Number__c,
        GitHub_Issue_URL__c,
        Engineering_Status__c,
        Engineering_Sync_Status__c,
        Last_Engineering_Sync__c
      FROM Case
      LIMIT 1
    ];
  }

  private static Integration_Log__c getLog() {
    return [
      SELECT
        Case__c,
        Operation__c,
        Status__c,
        HTTP_Status_Code__c,
        Attempt_Count__c,
        Correlation_ID__c,
        Error_Message__c
      FROM Integration_Log__c
    ];
  }

  @IsTest
  static void successUpdatesCaseAndLogs() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);
    useTestRepository();
    Case c = getCase();

    Test.startTest();
    System.enqueueJob(new GitHubIssueQueueable(c.Id, 'corr-123'));
    Test.stopTest();

    Assert.areEqual(
      'callout:GithubAPI/repos/octocat/test-repo/issues',
      mock.lastRequest.getEndpoint()
    );
    Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
      mock.lastRequest.getBody()
    );
    Assert.areEqual(
      '[Case ' + c.CaseNumber + '] Subscription activation fails',
      sent.get('title')
    );

    c = getCase();
    Assert.areEqual('1001', c.GitHub_Issue_ID__c);
    Assert.areEqual(42, c.GitHub_Issue_Number__c);
    Assert.areEqual(
      'https://github.com/octocat/test-repo/issues/42',
      c.GitHub_Issue_URL__c
    );
    Assert.areEqual('Open', c.Engineering_Status__c);
    Assert.areEqual('Success', c.Engineering_Sync_Status__c);
    Assert.isNotNull(c.Last_Engineering_Sync__c);

    Integration_Log__c log = getLog();
    Assert.areEqual(c.Id, log.Case__c);
    Assert.areEqual('Create Issue', log.Operation__c);
    Assert.areEqual('Success', log.Status__c);
    Assert.areEqual(201, log.HTTP_Status_Code__c);
    Assert.areEqual(1, log.Attempt_Count__c);
    Assert.areEqual('corr-123', log.Correlation_ID__c);
    Assert.isNull(log.Error_Message__c);
  }

  @IsTest
  static void httpFailureMarksCaseFailedAndLogsStatusCode() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockResponse(500, '{"message":"Server Error"}')
    );
    useTestRepository();
    Case c = getCase();

    Test.startTest();
    System.enqueueJob(new GitHubIssueQueueable(c.Id, 'corr-456'));
    Test.stopTest();

    c = getCase();
    Assert.areEqual('Failed', c.Engineering_Sync_Status__c);
    Assert.isNull(c.GitHub_Issue_Number__c);
    Assert.isNull(
      c.Last_Engineering_Sync__c,
      'Only successful syncs update Last Engineering Sync'
    );

    Integration_Log__c log = getLog();
    Assert.areEqual('Failed', log.Status__c);
    Assert.areEqual(500, log.HTTP_Status_Code__c);
    Assert.areEqual(
      'GitHub request failed (HTTP 500): GitHub is temporarily unavailable. Try again later. GitHub says: Server Error',
      log.Error_Message__c
    );
  }

  @IsTest
  static void missingConfigurationMarksCaseFailed() {
    GitHubIssueQueueable.settings = null;
    Case c = getCase();

    Test.startTest();
    System.enqueueJob(new GitHubIssueQueueable(c.Id, 'corr-789'));
    Test.stopTest();

    Assert.areEqual('Failed', getCase().Engineering_Sync_Status__c);
    Integration_Log__c log = getLog();
    Assert.areEqual('Failed', log.Status__c);
    Assert.isNull(log.HTTP_Status_Code__c, 'No HTTP response was received');
    Assert.isTrue(log.Error_Message__c.contains('not configured'));
  }

  @IsTest
  static void buildIssueHandlesMissingDescription() {
    Case c = new Case(Subject = 'No details', Priority = 'Low');
    GitHubApiService.CreateIssueRequest issue = GitHubIssueQueueable.buildIssue(
      c
    );
    Assert.isTrue(issue.body.contains('_No description provided._'));
  }
}
