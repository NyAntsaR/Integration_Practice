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

  // Simulates a timeout or network failure: no HTTP response is received.
  private class UnreachableMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      throw new CalloutException('Read timed out');
    }
  }

  @TestSetup
  static void setup() {
    Case c = new Case(
      Subject = 'Subscription activation fails',
      Description = 'Steps to reproduce...',
      Status = 'New',
      Origin = 'Web',
      Priority = 'High',
      Engineering_Sync_Status__c = 'Pending'
    );
    insert c;

    insert new Integration_Operation__c(
      Case__c = c.Id,
      Idempotency_Key__c = 'GITHUB_CREATE:test:' + c.Id,
      Status__c = 'Pending',
      Operation_Type__c = 'Create GitHub Issue',
      Attempt_Count__c = 0,
      Correlation_ID__c = 'corr-123'
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

  private static Integration_Operation__c getOperation() {
    return [
      SELECT
        Id,
        Status__c,
        Attempt_Count__c,
        External_Issue_ID__c,
        Last_HTTP_Status__c,
        Last_Error__c,
        Lease_Owner__c,
        Lease_Expires_At__c
      FROM Integration_Operation__c
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

  private static final String LEASE = 'lease-job-1';

  // Puts the operation in the state step 1 leaves it in.
  private static void claimOperation() {
    Integration_Operation__c op = getOperation();
    op.Status__c = 'Processing';
    op.Lease_Owner__c = LEASE;
    op.Lease_Expires_At__c = System.now().addMinutes(10);
    update op;
  }

  // Runs step 2 (the GitHub call) as the job holding the lease.
  private static void runJob() {
    claimOperation();
    Test.startTest();
    System.enqueueJob(new GitHubIssueQueueable(getOperation().Id, LEASE));
    Test.stopTest();
  }

  private static void assertLeaseReleased() {
    Integration_Operation__c op = getOperation();
    Assert.isNull(op.Lease_Owner__c);
    Assert.isNull(op.Lease_Expires_At__c);
  }

  @IsTest
  static void successUpdatesCaseOperationAndLog() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);
    useTestRepository();
    Case c = getCase();

    runJob();

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

    Integration_Operation__c op = getOperation();
    Assert.areEqual('Success', op.Status__c);
    Assert.areEqual('1001', op.External_Issue_ID__c);
    Assert.areEqual(201, op.Last_HTTP_Status__c);
    Assert.areEqual(1, op.Attempt_Count__c);
    Assert.isNull(op.Last_Error__c);
    assertLeaseReleased();

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
  static void attemptCountIncrementsFromPreviousValue() {
    Test.setMock(HttpCalloutMock.class, new MockResponse(201, ISSUE_BODY));
    useTestRepository();
    Integration_Operation__c op = getOperation();
    op.Attempt_Count__c = 2;
    update op;

    runJob();

    Assert.areEqual(3, getOperation().Attempt_Count__c);
    Assert.areEqual(3, getLog().Attempt_Count__c);
  }

  @IsTest
  static void httpErrorRequiresReconciliationAndRecordsStatusCode() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockResponse(500, '{"message":"Server Error"}')
    );
    useTestRepository();

    runJob();

    String expectedError = 'GitHub request failed (HTTP 500): GitHub is temporarily unavailable. Try again later. GitHub says: Server Error';

    Case c = getCase();
    Assert.areEqual('Failed', c.Engineering_Sync_Status__c);
    Assert.isNull(c.GitHub_Issue_Number__c);
    Assert.isNull(
      c.Last_Engineering_Sync__c,
      'Only successful syncs update Last Engineering Sync'
    );

    Integration_Operation__c op = getOperation();
    Assert.areEqual('Reconciliation Required', op.Status__c);
    Assert.areEqual(500, op.Last_HTTP_Status__c);
    Assert.areEqual(expectedError, op.Last_Error__c);
    Assert.isNull(op.External_Issue_ID__c);

    Integration_Log__c log = getLog();
    Assert.areEqual('Failed', log.Status__c);
    Assert.areEqual(500, log.HTTP_Status_Code__c);
    Assert.areEqual(expectedError, log.Error_Message__c);
    assertLeaseReleased();
  }

  @IsTest
  static void clientErrorFailsBecauseNoIssueWasCreated() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockResponse(422, '{"message":"Validation Failed"}')
    );
    useTestRepository();

    runJob();

    Integration_Operation__c op = getOperation();
    Assert.areEqual('Failed', op.Status__c, '4xx means GitHub rejected it');
    Assert.areEqual(422, op.Last_HTTP_Status__c);
    Assert.areEqual('Failed', getCase().Engineering_Sync_Status__c);
    Assert.areEqual(422, getLog().HTTP_Status_Code__c);
    assertLeaseReleased();
  }

  @IsTest
  static void outcomeForErrorClassifiesStatusCodes() {
    Assert.areEqual('Failed', GitHubIssueQueueable.outcomeForError(401));
    Assert.areEqual('Failed', GitHubIssueQueueable.outcomeForError(404));
    Assert.areEqual('Failed', GitHubIssueQueueable.outcomeForError(429));
    Assert.areEqual(
      'Reconciliation Required',
      GitHubIssueQueueable.outcomeForError(502)
    );
    Assert.areEqual(
      'Reconciliation Required',
      GitHubIssueQueueable.outcomeForError(null)
    );
  }

  @IsTest
  static void unreachableGitHubRequiresReconciliationWithoutStatusCode() {
    Test.setMock(HttpCalloutMock.class, new UnreachableMock());
    useTestRepository();

    runJob();

    Integration_Operation__c op = getOperation();
    Assert.areEqual('Reconciliation Required', op.Status__c);
    Assert.isNull(op.Last_HTTP_Status__c, 'No HTTP response was received');
    Assert.isTrue(op.Last_Error__c.startsWith('Could not reach GitHub'));
    Assert.areEqual('Failed', getCase().Engineering_Sync_Status__c);
    Assert.isNull(getLog().HTTP_Status_Code__c);
  }

  @IsTest
  static void missingConfigurationFailsWithoutCallout() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);
    GitHubIssueQueueable.settings = null;

    runJob();

    Assert.isNull(mock.lastRequest, 'GitHub must not be called');
    Assert.areEqual('Failed', getCase().Engineering_Sync_Status__c);

    Integration_Operation__c op = getOperation();
    Assert.areEqual('Failed', op.Status__c);
    Assert.isTrue(op.Last_Error__c.contains('not configured'));

    Integration_Log__c log = getLog();
    Assert.areEqual('Failed', log.Status__c);
    Assert.isNull(log.HTTP_Status_Code__c, 'No HTTP response was received');
    Assert.isTrue(log.Error_Message__c.contains('not configured'));
  }

  @IsTest
  static void claimStepTakesLeaseWithoutCallingGitHub() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);
    useTestRepository();

    Test.startTest();
    Id jobId = System.enqueueJob(new GitHubIssueQueueable(getOperation().Id));
    Test.stopTest();

    Assert.isNull(mock.lastRequest, 'The claim step never calls GitHub');
    Integration_Operation__c op = getOperation();
    Assert.areEqual('Processing', op.Status__c);
    Assert.areEqual(jobId, (Id) op.Lease_Owner__c);
    Assert.isTrue(op.Lease_Expires_At__c > System.now());
    Assert.areEqual(0, op.Attempt_Count__c);
    Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
  }

  @IsTest
  static void claimStepSkipsNonPendingOperation() {
    Integration_Operation__c op = getOperation();
    op.Status__c = 'Failed';
    update op;

    Test.startTest();
    System.enqueueJob(new GitHubIssueQueueable(op.Id));
    Test.stopTest();

    op = getOperation();
    Assert.areEqual('Failed', op.Status__c);
    Assert.isNull(op.Lease_Owner__c);
  }

  @IsTest
  static void callStepWithoutLeaseIsSkipped() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);
    useTestRepository();
    claimOperation();

    Test.startTest();
    System.enqueueJob(
      new GitHubIssueQueueable(getOperation().Id, 'another-job')
    );
    Test.stopTest();

    Assert.isNull(mock.lastRequest, 'GitHub must not be called');
    Integration_Operation__c op = getOperation();
    Assert.areEqual('Processing', op.Status__c);
    Assert.areEqual(LEASE, op.Lease_Owner__c, 'Lease is untouched');
    Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
  }

  @IsTest
  static void callStepSkipsOperationThatIsNotProcessing() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);
    useTestRepository();

    Test.startTest();
    System.enqueueJob(new GitHubIssueQueueable(getOperation().Id, LEASE));
    Test.stopTest();

    Assert.isNull(mock.lastRequest, 'GitHub must not be called');
    Assert.areEqual('Pending', getOperation().Status__c);
  }

  @IsTest
  static void linkedCaseRequiresReconciliationWithoutCallout() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);
    useTestRepository();
    Case c = getCase();
    c.GitHub_Issue_Number__c = 7;
    update c;

    runJob();

    Assert.isNull(mock.lastRequest, 'GitHub must not be called');
    Integration_Operation__c op = getOperation();
    Assert.areEqual('Reconciliation Required', op.Status__c);
    Assert.isTrue(
      op.Last_Error__c.startsWith('An external issue reference already exists.')
    );
    Assert.areEqual(
      'Failed',
      getCase().Engineering_Sync_Status__c,
      'Case must not stay Pending'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
    assertLeaseReleased();
  }

  @IsTest
  static void operationWithExternalIssueIdRequiresReconciliation() {
    MockResponse mock = new MockResponse(201, ISSUE_BODY);
    Test.setMock(HttpCalloutMock.class, mock);
    useTestRepository();
    Integration_Operation__c op = getOperation();
    op.External_Issue_ID__c = '1001';
    update op;

    runJob();

    Assert.isNull(mock.lastRequest, 'GitHub must not be called');
    Assert.areEqual('Reconciliation Required', getOperation().Status__c);
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
