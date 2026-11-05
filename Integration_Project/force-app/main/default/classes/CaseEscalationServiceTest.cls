@IsTest
private class CaseEscalationServiceTest {
  private static final String ISSUE_BODY = '{"id":1001,"number":42,"html_url":"https://github.com/NyAntsaR/repo/issues/42","state":"open","title":"t"}';

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
      Status = 'New',
      Origin = 'Web'
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

  private static void assertEscalationFails(Id caseId, String expectedMessage) {
    try {
      CaseEscalationService.escalateToEngineering(caseId);
      Assert.fail('Expected CaseEscalationException');
    } catch (CaseEscalationService.CaseEscalationException e) {
      Assert.areEqual(expectedMessage, e.getMessage());
    }
  }

  @IsTest
  static void escalateMarksCasePendingAndEnqueuesJob() {
    Test.setMock(HttpCalloutMock.class, new MockResponse(201, ISSUE_BODY));
    Case c = getCase();

    Test.startTest();
    Id jobId = CaseEscalationService.escalateToEngineering(c.Id);
    Assert.areEqual(
      CaseEscalationService.STATUS_PENDING,
      getCase().Engineering_Sync_Status__c
    );
    Test.stopTest();

    Assert.isNotNull(jobId);
    Assert.areEqual(
      'Success',
      getCase().Engineering_Sync_Status__c,
      'Queueable ran after stopTest'
    );
    Assert.areEqual(42, getCase().GitHub_Issue_Number__c);
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
  }

  @IsTest
  static void pendingEscalationThrows() {
    Case c = getCase();
    c.Engineering_Sync_Status__c = CaseEscalationService.STATUS_PENDING;
    update c;
    assertEscalationFails(
      c.Id,
      'An escalation for this Case is already in progress.'
    );
  }

  @IsTest
  static void processingEscalationThrows() {
    Case c = getCase();
    c.Engineering_Sync_Status__c = CaseEscalationService.STATUS_PROCESSING;
    update c;
    assertEscalationFails(
      c.Id,
      'An escalation for this Case is already in progress.'
    );
  }

  @IsTest
  static void failedEscalationCanBeRetried() {
    Test.setMock(HttpCalloutMock.class, new MockResponse(201, ISSUE_BODY));
    Case c = getCase();
    c.Engineering_Sync_Status__c = 'Failed';
    update c;

    Test.startTest();
    CaseEscalationService.escalateToEngineering(c.Id);
    Test.stopTest();

    Assert.areEqual('Success', getCase().Engineering_Sync_Status__c);
  }
}
