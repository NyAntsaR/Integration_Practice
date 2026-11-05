/**
 * Creates a GitHub Issue for an escalated Case, writes the result back to the Case,
 * and records the attempt in Integration_Log__c. Enqueued by CaseEscalationService.
 */
public with sharing class GitHubIssueQueueable implements Queueable, Database.AllowsCallouts {
  // Repository to create issues in. Tests can replace it with an in-memory record.
  @TestVisible
  private static GitHub_Integration_Setting__mdt settings = GitHub_Integration_Setting__mdt.getInstance(
    'Default'
  );

  private static final Integer MAX_ERROR_LENGTH = 5000;

  private final Id caseId;
  private final String correlationId;

  public GitHubIssueQueueable(Id caseId, String correlationId) {
    this.caseId = caseId;
    this.correlationId = correlationId;
  }

  public void execute(QueueableContext context) {
    Case c = [
      SELECT Id, CaseNumber, Subject, Description, Priority
      FROM Case
      WHERE Id = :caseId
      WITH USER_MODE
    ];

    Integration_Log__c log = new Integration_Log__c(
      Case__c = caseId,
      Operation__c = 'Create Issue',
      Correlation_ID__c = correlationId,
      Attempt_Count__c = 1,
      Last_Attempt_At__c = System.now()
    );

    Case result = new Case(Id = caseId);

    // The callout must happen before any DML in this transaction.
    try {
      if (settings == null) {
        throw new GitHubApiService.GitHubApiException(
          'GitHub repository is not configured. Add a "Default" GitHub Integration Setting record.'
        );
      }

      GitHubApiService.IssueResponse issue = GitHubApiService.createIssue(
        settings.Repository_Owner__c,
        settings.Repository_Name__c,
        buildIssue(c)
      );

      result.GitHub_Issue_ID__c = String.valueOf(issue.id);
      result.GitHub_Issue_Number__c = issue.issueNumber;
      result.GitHub_Issue_URL__c = issue.htmlUrl;
      result.Engineering_Status__c = 'Open';
      result.Engineering_Sync_Status__c = 'Success';
      result.Last_Engineering_Sync__c = System.now();

      log.Status__c = 'Success';
      log.HTTP_Status_Code__c = 201;
    } catch (Exception e) {
      result.Engineering_Sync_Status__c = 'Failed';

      log.Status__c = 'Failed';
      if (e instanceof GitHubApiService.GitHubApiException) {
        log.HTTP_Status_Code__c = ((GitHubApiService.GitHubApiException) e)
          .statusCode;
      }
      log.Error_Message__c = e.getMessage().abbreviate(MAX_ERROR_LENGTH);
    }

    update as user result;
    insert as user log;
  }

  @TestVisible
  private static GitHubApiService.CreateIssueRequest buildIssue(Case c) {
    GitHubApiService.CreateIssueRequest issue = new GitHubApiService.CreateIssueRequest();
    issue.title = '[Case ' + c.CaseNumber + '] ' + c.Subject;
    issue.body =
      '**Salesforce Case:** ' +
      c.CaseNumber +
      '\n' +
      '**Priority:** ' +
      c.Priority +
      '\n\n' +
      (String.isBlank(c.Description)
        ? '_No description provided._'
        : c.Description);
    return issue;
  }
}
