/**
 * Creates follow-up Tasks for Opportunities. Called from OpportunityTriggerHandler (after update).
 */
public with sharing class OpportunityTaskService {
    @TestVisible
    private static final String FOLLOW_UP_SUBJECT = 'Follow up on Closed Won opportunity';
    @TestVisible
    private static final Integer FOLLOW_UP_DAYS = 7;

    /**
     * Creates one follow-up Task per Opportunity whose stage just changed to Closed Won.
     * Bulk-safe: a single DML insert for the whole trigger batch.
     */
    public static void createFollowUpTasks(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Task> tasks = new List<Task>();
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap != null ? oldMap.get(opp.Id) : null;
            if (opp.IsWon && (oldOpp == null || !oldOpp.IsWon)) {
                tasks.add(buildFollowUpTask(opp));
            }
        }

        if (!tasks.isEmpty()) {
            insert tasks;
        }
    }

    private static Task buildFollowUpTask(Opportunity opp) {
        return new Task(
            WhatId = opp.Id,
            OwnerId = opp.OwnerId,
            Subject = FOLLOW_UP_SUBJECT,
            Description = 'Opportunity "' + opp.Name + '" was marked Closed Won. Follow up with the customer.',
            ActivityDate = Date.today().addDays(FOLLOW_UP_DAYS),
            Priority = 'High',
            Status = 'Not Started'
        );
    }
}
