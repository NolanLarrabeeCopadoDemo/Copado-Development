trigger project_milestone_trigger_copado on Project_Milestone__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            project_milestone_handler_copado.beforeSave(Trigger.new);
        }
    } else if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            project_milestone_handler_copado.afterSave(Trigger.new, Trigger.oldMap);
        }
    }
}