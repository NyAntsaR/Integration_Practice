
Case c = [
    SELECT Id, CaseNumber
    FROM Case
    WHERE Subject = 'GitHub Integration - Operation Tracking Test'
    ORDER BY CreatedDate DESC
    LIMIT 1
];

try {
    Id jobId = CaseEscalationService.escalateToEngineering(c.Id);

    System.debug('UNEXPECTED: Job created: ' + jobId);

} catch (CaseEscalationService.CaseEscalationException e) {

    System.debug('EXPECTED: Duplicate escalation blocked.');
    System.debug('Reason: ' + e.getMessage());
}
