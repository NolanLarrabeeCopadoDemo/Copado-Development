trigger EquipmentAvailability_copado on Shipment__c (after update) {
    Set<String> relevantStatuses = new Set<String>{ 'In Transit', 'Delivered', 'Cancelled' };
    List<Shipment__c> shipmentsRequiringEquipmentUpdate = new List<Shipment__c>();

    for (Shipment__c shipment : Trigger.new) {
        Shipment__c oldShipment = Trigger.oldMap.get(shipment.Id);
        Boolean statusChangedToRelevantValue = oldShipment.Status__c != shipment.Status__c
            && relevantStatuses.contains(shipment.Status__c);
        if (statusChangedToRelevantValue && shipment.Equipment__c != null) {
            shipmentsRequiringEquipmentUpdate.add(shipment);
        }
    }

    if (!shipmentsRequiringEquipmentUpdate.isEmpty()) {
        EquipmentAvailabilityService_copado.updateEquipmentAvailability(shipmentsRequiringEquipmentUpdate);
    }
}