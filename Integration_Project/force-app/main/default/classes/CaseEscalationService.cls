/**
 * Escalates a Case to Engineering by creating a GitHub Issue asynchronously.
 * Enforces the escalation rules, marks the Case as Pending, and enqueues GitHubIssueQueueable.
 */
public with sharing class CaseEscalationService {
  @TestVisible
  private static final String STATUS_PENDING = 'Pending';
  @TestVisible
  private static final String STATUS_PROCESSING = 'Processing';

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

    // ...and can edit it.
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

    // 2. Only one GitHub Issue per Case.
    if (
      String.isNotBlank(c.GitHub_Issue_ID__c) ||
      c.GitHub_Issue_Number__c != null ||
      String.isNotBlank(c.GitHub_Issue_URL__c)
    ) {
      throw new CaseEscalationException(
        'This Case has already been escalated to a GitHub Issue.'
      );
    }

    // 3. No duplicate submissions while one is in flight.
    if (
      c.Engineering_Sync_Status__c == STATUS_PENDING ||
      c.Engineering_Sync_Status__c == STATUS_PROCESSING
    ) {
      throw new CaseEscalationException(
        'An escalation for this Case is already in progress.'
      );
    }

    // 4. Mark the Case as Pending.
    c.Engineering_Sync_Status__c = STATUS_PENDING;
    update as user c;

    // 5. Submit the integration job. The correlation ID ties the job's logs together.
    String correlationId = UUID.randomUUID().toString();
    return System.enqueueJob(new GitHubIssueQueueable(caseId, correlationId));
  }

  public class CaseEscalationException extends Exception {
  }
}
