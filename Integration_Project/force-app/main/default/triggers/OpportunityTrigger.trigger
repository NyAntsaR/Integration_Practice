trigger OpportunityTrigger on Opportunity(after update) {
    OpportunityTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
}
