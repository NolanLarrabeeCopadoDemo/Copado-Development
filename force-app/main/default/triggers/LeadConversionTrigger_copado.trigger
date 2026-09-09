trigger LeadConversionTrigger_copado on Lead (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            LeadConversionTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            LeadConversionTriggerHandler.handleBeforeUpdate(Trigger.new);
        }
    }
}