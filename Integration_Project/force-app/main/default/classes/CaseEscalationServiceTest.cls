@IsTest
private class CaseEscalationServiceTest {
  private static final String ISSUE_BODY = '{"id":1001,"number":42,"html_url":"https://github.com/octocat/test-repo/issues/42","state":"open","title":"t"}';

  private class MockResponse implements HttpCalloutMock {
    private Integer statusCode;
    private String body;

    MockResponse(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest req) {
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
      Status = 'New',
      Origin = 'Web'
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
        Engineering_Sync_Status__c,
        GitHub_Issue_Number__c,
        GitHub_Issue_ID__c,
        GitHub_Issue_URL__c
      FROM Case
      LIMIT 1
    ];
  }

  private static String expectedKey(Id caseId) {
    return 'GITHUB_CREATE:' + UserInfo.getOrganizationId() + ':' + caseId;
  }

  private static void assertEscalationFails(Id caseId, String expectedMessage) {
    try {
      CaseEscalationService.escalateToEngineering(caseId);
      Assert.fail('Expected CaseEscalationException');
    } catch (CaseEscalationService.CaseEscalationException e) {
      Assert.areEqual(expectedMessage, e.getMessage());
    }
  }

  @IsTest
  static void escalateCreatesOperationMarksPendingAndEnqueuesJob() {
    Test.setMock(HttpCalloutMock.class, new MockResponse(201, ISSUE_BODY));
    useTestRepository();
    Case c = getCase();

    Test.startTest();
    Id jobId = CaseEscalationService.escalateToEngineering(c.Id);

    // Before the queueable runs: the operation is recorded and the Case is Pending.
    Integration_Operation__c op = [
      SELECT
        Case__c,
        Idempotency_Key__c,
        Status__c,
        Operation_Type__c,
        Attempt_Count__c,
        Correlation_ID__c
      FROM Integration_Operation__c
    ];
    Assert.areEqual(c.Id, op.Case__c);
    Assert.areEqual(expectedKey(c.Id), op.Idempotency_Key__c);
    Assert.areEqual('Pending', op.Status__c);
    Assert.areEqual('Create GitHub Issue', op.Operation_Type__c);
    Assert.areEqual(0, op.Attempt_Count__c);
    Assert.isTrue(String.isNotBlank(op.Correlation_ID__c));
    Assert.areEqual(
      CaseEscalationService.STATUS_PENDING,
      getCase().Engineering_Sync_Status__c
    );
    Test.stopTest();

    // The first queueable step ran: it claims the operation. (Apex tests
    // can't chain jobs, so the GitHub call step is covered in
    // GitHubIssueQueueableTest.)
    Assert.isNotNull(jobId);
    op = [SELECT Status__c, Lease_Owner__c FROM Integration_Operation__c];
    Assert.areEqual('Processing', op.Status__c);
    Assert.areEqual(jobId, (Id) op.Lease_Owner__c);
  }

  private static Integration_Operation__c insertOperation(
    Id caseId,
    String status
  ) {
    Integration_Operation__c op = new Integration_Operation__c(
      Case__c = caseId,
      Idempotency_Key__c = expectedKey(caseId),
      Status__c = status,
      Operation_Type__c = 'Create GitHub Issue',
      Attempt_Count__c = 2,
      Correlation_ID__c = 'corr-original',
      Last_Error__c = 'GitHub request failed (HTTP 404)',
      Last_HTTP_Status__c = 404
    );
    insert op;
    return op;
  }

  @IsTest
  static void failedOperationIsRetried() {
    Case c = getCase();
    c.Engineering_Sync_Status__c = 'Failed';
    update c;
    Integration_Operation__c original = insertOperation(c.Id, 'Failed');

    Test.startTest();
    Id jobId = CaseEscalationService.escalateToEngineering(c.Id);
    Integration_Operation__c op = [
      SELECT
        Id,
        Status__c,
        Attempt_Count__c,
        Correlation_ID__c,
        Last_Error__c,
        Last_HTTP_Status__c
      FROM Integration_Operation__c
    ];
    Assert.areEqual(original.Id, op.Id, 'The same operation is reused');
    Assert.areEqual('Pending', op.Status__c);
    Assert.areEqual(2, op.Attempt_Count__c, 'Attempt history is kept');
    Assert.areEqual('corr-original', op.Correlation_ID__c);
    Assert.isNull(op.Last_Error__c);
    Assert.isNull(op.Last_HTTP_Status__c);
    Assert.areEqual('Pending', getCase().Engineering_Sync_Status__c);
    Test.stopTest();

    Assert.isNotNull(jobId);
    Assert.areEqual(
      'Processing',
      [SELECT Status__c FROM Integration_Operation__c].Status__c
    );
  }

  @IsTest
  static void reconciliationRequiredBlocksRetry() {
    Case c = getCase();
    insertOperation(c.Id, 'Reconciliation Required');
    assertEscalationFails(
      c.Id,
      'A previous escalation may have created a GitHub Issue. Check GitHub and reconcile this Case before retrying.'
    );
  }

  @IsTest
  static void successfulOperationBlocksRetry() {
    Case c = getCase();
    insertOperation(c.Id, 'Success');
    assertEscalationFails(
      c.Id,
      'This Case has already been escalated to a GitHub Issue.'
    );
  }

  @IsTest
  static void nullCaseIdThrows() {
    assertEscalationFails(null, 'A Case Id is required.');
  }

  @IsTest
  static void missingCaseThrows() {
    Case c = getCase();
    delete c;
    assertEscalationFails(
      c.Id,
      'Case not found, or you do not have access to it.'
    );
  }

  @IsTest
  static void existingGitHubIssueThrows() {
    Case c = getCase();
    c.GitHub_Issue_Number__c = 7;
    update c;
    assertEscalationFails(
      c.Id,
      'This Case has already been escalated to a GitHub Issue.'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM Integration_Operation__c]);
  }

  @IsTest
  static void existingGitHubIssueIdThrows() {
    Case c = getCase();
    c.GitHub_Issue_ID__c = '1001';
    update c;
    assertEscalationFails(
      c.Id,
      'This Case has already been escalated to a GitHub Issue.'
    );
  }

  @IsTest
  static void existingOperationBlocksDuplicateEscalation() {
    Case c = getCase();
    insertOperation(c.Id, 'Processing');

    assertEscalationFails(
      c.Id,
      'An escalation for this Case is already in progress. Current status: Processing'
    );
    Assert.areEqual(1, [SELECT COUNT() FROM Integration_Operation__c]);
  }

  @IsTest
  static void secondEscalationIsBlocked() {
    Test.setMock(HttpCalloutMock.class, new MockResponse(201, ISSUE_BODY));
    useTestRepository();
    Case c = getCase();

    Test.startTest();
    CaseEscalationService.escalateToEngineering(c.Id);
    assertEscalationFails(
      c.Id,
      'An escalation for this Case is already in progress. Current status: Pending'
    );
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM Integration_Operation__c]);
  }
}
