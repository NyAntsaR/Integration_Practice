Case c = [
    SELECT Id, CaseNumber
    FROM Case
    WHERE Subject = 'Test GitHub Integration — End-to-End'
    ORDER BY CreatedDate DESC
    LIMIT 1
];

Id jobId = CaseEscalationService.escalateToEngineering(c.Id);

System.debug('Case: ' + c.CaseNumber);
System.debug('Queueable Job ID: ' + jobId);