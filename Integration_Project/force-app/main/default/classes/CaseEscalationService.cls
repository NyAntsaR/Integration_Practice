/**
 * Escalates a Case to Engineering by creating a GitHub Issue asynchronously.
 * Enforces the escalation rules, records (or retries) an Integration_Operation__c,
 * marks the Case as Pending, and enqueues GitHubIssueQueueable.
 */
public with sharing class CaseEscalationService {
  @TestVisible
  private static final String STATUS_PENDING = 'Pending';

  //Integration_Operation__c.Status__c values
  @TestVisible
  private static final String OP_PENDING = 'Pending';
  @TestVisible
  private static final String OP_FAILED = 'Failed';
  @TestVisible
  private static final String OP_SUCCESS = 'Success';
  @TestVisible
  private static final String OP_RECONCILIATION_REQUIRED = 'Reconciliation Required';

  public class CaseEscalationException extends Exception {
  }

  /**
   * Validates the Case and submits the GitHub Issue job. Returns the queueable job Id.
   */
  public static Id escalateToEngineering(Id caseId) {
    if (caseId == null) {
      throw new CaseEscalationException('A Case Id is required.');
    }

    // 1. Case exists and the user can see it (USER_MODE enforces sharing and field access).
    //    FOR UPDATE locks the row so two simultaneous clicks can't both submit.
    List<Case> cases = [
      SELECT
        Id,
        GitHub_Issue_ID__c,
        GitHub_Issue_Number__c,
        GitHub_Issue_URL__c,
        Engineering_Sync_Status__c
      FROM Case
      WHERE Id = :caseId
      WITH USER_MODE
      LIMIT 1
      FOR UPDATE
    ];

    if (cases.isEmpty()) {
      throw new CaseEscalationException(
        'Case not found, or you do not have access to it.'
      );
    }

    Case c = cases[0];

    //Verify that the caller can edit this case
    UserRecordAccess access = [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :caseId
    ];
    if (!access.HasEditAccess) {
      throw new CaseEscalationException(
        'You do not have permission to edit this Case.'
      );
    }

    //Do not create a second issue for an already-linked case
    if (
      String.isNotBlank(c.GitHub_Issue_ID__c) ||
      c.GitHub_Issue_Number__c != null ||
      String.isNotBlank(c.GitHub_Issue_URL__c)
    ) {
      throw new CaseEscalationException(
        'This Case has already been escalated to a GitHub Issue.'
      );
    }

    String idempotencyKey =
      'GITHUB_CREATE:' +
      UserInfo.getOrganizationId() +
      ':' +
      caseId;

    //Look for an existing logical operation. The idempotency key is unique,
    //so a Case has at most one operation, which is reused on retry.
    List<Integration_Operation__c> existingOps = [
      SELECT Id, Status__c
      FROM Integration_Operation__c
      WHERE Idempotency_Key__c = :idempotencyKey
      LIMIT 1
      FOR UPDATE
    ];

    Integration_Operation__c operation;
    if (existingOps.isEmpty()) {
      //Persist the operation before scheduling asynchronous processing.
      operation = new Integration_Operation__c(
        Case__c = caseId,
        Idempotency_Key__c = idempotencyKey,
        Status__c = OP_PENDING,
        Operation_Type__c = 'Create GitHub Issue',
        Attempt_Count__c = 0,
        Correlation_ID__c = UUID.randomUUID().toString()
      );
      insert operation;
    } else {
      operation = existingOps[0];
      assertRetryable(operation.Status__c);

      //A failed operation is retried: reset it to Pending and keep its
      //Correlation ID and Attempt Count so all attempts stay linked.
      operation.Status__c = OP_PENDING;
      operation.Last_Error__c = null;
      operation.Last_HTTP_Status__c = null;
      operation.Lease_Owner__c = null;
      operation.Lease_Expires_At__c = null;
      update operation;
    }

    update as user new Case(
      Id = caseId,
      Engineering_Sync_Status__c = STATUS_PENDING
    );

    return System.enqueueJob(new GitHubIssueQueueable(operation.Id));
  }

  //Only a Failed operation can be retried. Every other status is either
  //still running, finished, or needs a person to check GitHub first.
  private static void assertRetryable(String status) {
    if (status == OP_FAILED) {
      return;
    }
    if (status == OP_SUCCESS) {
      throw new CaseEscalationException(
        'This Case has already been escalated to a GitHub Issue.'
      );
    }
    if (status == OP_RECONCILIATION_REQUIRED) {
      throw new CaseEscalationException(
        'A previous escalation may have created a GitHub Issue. ' +
        'Check GitHub and reconcile this Case before retrying.'
      );
    }
    throw new CaseEscalationException(
      'An escalation for this Case is already in progress. ' +
        'Current status: ' +
        status
    );
  }
}
