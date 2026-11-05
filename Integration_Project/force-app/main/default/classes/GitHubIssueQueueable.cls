/**
 * Creates a GitHub Issue for an escalated Case, writes the result back to the Case,
 * and records the attempt on Integration_Operation__c and Integration_Log__c.
 * Enqueued by CaseEscalationService.
 *
 * Runs in two steps, because Apex cannot save a record and then make a callout
 * in the same transaction:
 *   1. Claim: moves the operation from Pending to Processing and takes a lease
 *      (Lease_Owner__c = this job's Id), then enqueues step 2. No callout.
 *   2. Call: only the job holding that lease calls GitHub, then saves the
 *      result and releases the lease.
 */
public with sharing class GitHubIssueQueueable implements Queueable, Database.AllowsCallouts {
  // Repository to create issues in. Tests can replace it with an in-memory record.
  @TestVisible
  private static GitHub_Integration_Setting__mdt settings = GitHub_Integration_Setting__mdt.getInstance(
    'Default'
  );

  // Apex tests cannot chain queueable jobs, so tests run step 2 directly.
  @TestVisible
  private static Boolean chainCallStep = !Test.isRunningTest();

  @TestVisible
  private static final Integer LEASE_MINUTES = 10;
  private static final Integer MAX_ERROR_LENGTH = 5000;

  @TestVisible
  private static final String OP_PENDING = 'Pending';
  @TestVisible
  private static final String OP_PROCESSING = 'Processing';
  @TestVisible
  private static final String OP_SUCCESS = 'Success';
  @TestVisible
  private static final String OP_FAILED = 'Failed';
  @TestVisible
  private static final String OP_RECONCILIATION_REQUIRED = 'Reconciliation Required';

  private final Id operationId;
  // Null for the claim step; the claim job's Id for the call step.
  private final String leaseToken;

  public GitHubIssueQueueable(Id operationId) {
    this(operationId, null);
  }

  @TestVisible
  private GitHubIssueQueueable(Id operationId, String leaseToken) {
    this.operationId = operationId;
    this.leaseToken = leaseToken;
  }

  public void execute(QueueableContext context) {
    if (leaseToken == null) {
      claim(context.getJobId());
    } else {
      callGitHub();
    }
  }

  // Step 1: claim the operation. Only a Pending operation can be claimed, and
  // FOR UPDATE stops two jobs from claiming the same operation at once.
  private void claim(Id jobId) {
    Integration_Operation__c operation = [
      SELECT Id, Status__c
      FROM Integration_Operation__c
      WHERE Id = :operationId
      LIMIT 1
      FOR UPDATE
    ];
    if (operation.Status__c != OP_PENDING) {
      return;
    }

    operation.Status__c = OP_PROCESSING;
    operation.Lease_Owner__c = String.valueOf(jobId);
    operation.Lease_Expires_At__c = System.now().addMinutes(LEASE_MINUTES);
    update operation;

    if (chainCallStep) {
      System.enqueueJob(
        new GitHubIssueQueueable(operationId, operation.Lease_Owner__c)
      );
    }
  }

  // Step 2: call GitHub. No DML happens before the callout.
  private void callGitHub() {
    Integration_Operation__c operation = [
      SELECT
        Id,
        Case__c,
        Status__c,
        Attempt_Count__c,
        Correlation_ID__c,
        External_Issue_ID__c,
        Lease_Owner__c
      FROM Integration_Operation__c
      WHERE Id = :operationId
      LIMIT 1
    ];

    // Only the job holding this operation's lease may call GitHub.
    if (
      operation.Status__c != OP_PROCESSING ||
      operation.Lease_Owner__c != leaseToken
    ) {
      return;
    }

    Case c = [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Description,
        Priority,
        GitHub_Issue_ID__c,
        GitHub_Issue_Number__c,
        GitHub_Issue_URL__c,
        Engineering_Status__c,
        Engineering_Sync_Status__c
      FROM Case
      WHERE Id = :operation.Case__c
      LIMIT 1
    ];

    Case caseUpdate = new Case(Id = operation.Case__c);
    releaseLease(operation);

    // Never intentionally create an issue for a linked Case.
    if (
      String.isNotBlank(c.GitHub_Issue_ID__c) ||
      c.GitHub_Issue_Number__c != null ||
      String.isNotBlank(c.GitHub_Issue_URL__c) ||
      String.isNotBlank(operation.External_Issue_ID__c)
    ) {
      operation.Status__c = OP_RECONCILIATION_REQUIRED;
      operation.Last_Error__c =
        'An external issue reference already exists. ' +
        'Verify the Case and GitHub before processing.';
      // Don't leave the Case waiting on an escalation that won't run.
      if (
        c.Engineering_Sync_Status__c == 'Pending' ||
        c.Engineering_Sync_Status__c == 'Processing'
      ) {
        caseUpdate.Engineering_Sync_Status__c = 'Failed';
      }
      persistResults(caseUpdate, operation, null);
      return;
    }

    Integer attemptNumber = operation.Attempt_Count__c == null
      ? 1
      : operation.Attempt_Count__c.intValue() + 1;
    operation.Attempt_Count__c = attemptNumber;
    operation.Last_Error__c = null;
    operation.Last_HTTP_Status__c = null;

    Integration_Log__c log = new Integration_Log__c(
      Case__c = operation.Case__c,
      Operation__c = 'Create Issue',
      Correlation_ID__c = operation.Correlation_ID__c,
      Attempt_Count__c = attemptNumber,
      Last_Attempt_At__c = System.now()
    );

    // Validate configuration before calling GitHub. Nothing was sent, so the
    // operation can safely be retried once the setting is fixed.
    if (
      settings == null ||
      String.isBlank(settings.Repository_Owner__c) ||
      String.isBlank(settings.Repository_Name__c)
    ) {
      recordFailure(
        operation,
        caseUpdate,
        log,
        OP_FAILED,
        'GitHub repository is not configured. Add a "Default" GitHub Integration Setting record.',
        null
      );
      persistResults(caseUpdate, operation, log);
      return;
    }

    try {
      GitHubApiService.IssueResponse issue = GitHubApiService.createIssue(
        settings.Repository_Owner__c,
        settings.Repository_Name__c,
        buildIssue(c)
      );

      // GitHub returned HTTP 201
      caseUpdate.GitHub_Issue_ID__c = String.valueOf(issue.id);
      caseUpdate.GitHub_Issue_Number__c = issue.issueNumber;
      caseUpdate.GitHub_Issue_URL__c = issue.htmlUrl;
      caseUpdate.Engineering_Status__c = 'Open';
      caseUpdate.Engineering_Sync_Status__c = 'Success';
      caseUpdate.Last_Engineering_Sync__c = System.now();

      operation.External_Issue_ID__c = String.valueOf(issue.id);
      operation.Last_HTTP_Status__c = 201;
      operation.Status__c = OP_SUCCESS;

      log.Status__c = 'Success';
      log.HTTP_Status_Code__c = 201;
    } catch (Exception e) {
      Integer statusCode = e instanceof GitHubApiService.GitHubApiException
        ? ((GitHubApiService.GitHubApiException) e).statusCode
        : null;
      recordFailure(
        operation,
        caseUpdate,
        log,
        outcomeForError(statusCode),
        e.getMessage(),
        statusCode
      );
    }

    // Save Salesforce results after the callout.
    persistResults(caseUpdate, operation, log);
  }

  // A 4xx answer means GitHub rejected the request, so no issue was created
  // and the operation can be retried. With no answer (timeout), a 5xx, or an
  // unreadable success response, GitHub may have created the issue, so a
  // person must check before retrying.
  @TestVisible
  private static String outcomeForError(Integer statusCode) {
    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return OP_FAILED;
    }
    return OP_RECONCILIATION_REQUIRED;
  }

  private static void recordFailure(
    Integration_Operation__c operation,
    Case caseUpdate,
    Integration_Log__c log,
    String operationStatus,
    String message,
    Integer statusCode
  ) {
    String error = message.abbreviate(MAX_ERROR_LENGTH);
    operation.Status__c = operationStatus;
    operation.Last_Error__c = error;
    operation.Last_HTTP_Status__c = statusCode;
    caseUpdate.Engineering_Sync_Status__c = 'Failed';
    log.Status__c = 'Failed';
    log.Error_Message__c = error;
    log.HTTP_Status_Code__c = statusCode;
  }

  private static void releaseLease(Integration_Operation__c operation) {
    operation.Lease_Owner__c = null;
    operation.Lease_Expires_At__c = null;
  }

  private static void persistResults(
    Case caseUpdate,
    Integration_Operation__c operation,
    Integration_Log__c log
  ) {
    update caseUpdate;
    update operation;
    if (log != null) {
      insert log;
    }
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
