public with sharing class OpportunityTriggerHandler {
    public OpportunityTriggerHandler(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {      
        List<Opportunity> opportinitiesToUpdate = new List<Opportunity>();
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (opp.StageName == 'Closed Won' && oldOpp.StageName != 'Closed Won'){
                opportinitiesToUpdate.add(opp);
            }
        }

        if (!opportunitiesToUpdate.isEmpty()){
            OpportunityTaskService.createFollowUpTasks(newList, oldMap);
        }
    }
}