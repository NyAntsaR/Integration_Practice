@IsTest
private class OpportunityTaskServiceTest {
    @TestSetup
    static void setup() {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opps.add(new Opportunity(Name = 'Test Opp ' + i, StageName = 'Prospecting', CloseDate = Date.today().addDays(30)));
        }
        insert opps;
    }

    @IsTest
    static void createsTaskWhenOpportunityIsClosedWon() {
        List<Opportunity> opps = [SELECT Id FROM Opportunity];
        for (Opportunity opp : opps) {
            opp.StageName = 'Closed Won';
        }

        Test.startTest();
        update opps;
        Test.stopTest();

        List<Task> tasks = [SELECT WhatId, Subject, ActivityDate FROM Task];
        Assert.areEqual(opps.size(), tasks.size(), 'One follow-up task per Closed Won opportunity');
        Assert.areEqual(OpportunityTaskService.FOLLOW_UP_SUBJECT, tasks[0].Subject);
        Assert.areEqual(Date.today().addDays(OpportunityTaskService.FOLLOW_UP_DAYS), tasks[0].ActivityDate);
    }

    @IsTest
    static void doesNotCreateTaskForOtherStageChanges() {
        List<Opportunity> opps = [SELECT Id FROM Opportunity];
        for (Opportunity opp : opps) {
            opp.StageName = 'Qualification';
        }

        Test.startTest();
        update opps;
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Task], 'No tasks for non-won stage changes');
    }

    @IsTest
    static void doesNotCreateDuplicateTaskWhenAlreadyWon() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.StageName = 'Closed Won';
        update opp;

        Test.startTest();
        opp.Description = 'Edited after close';
        update opp;
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id], 'Task only created on the transition to won');
    }
}
