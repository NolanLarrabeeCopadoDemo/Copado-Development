trigger ShipmentRiskScoring_copado on Shipment__c (before insert, before update) {
    ShipmentRiskTriggerHandler_copado.handleBeforeSave(Trigger.new);
}