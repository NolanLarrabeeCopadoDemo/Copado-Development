trigger ShipmentStatusTrigger on Shipment__c (after update) {
    List<Shipment__c> deliveredShipments = new List<Shipment__c>();

    for (Shipment__c shipment : Trigger.new) {
        Shipment__c oldShipment = Trigger.oldMap.get(shipment.Id);
        if (shipment.Status__c == 'Delivered' && oldShipment.Status__c != 'Delivered') {
            deliveredShipments.add(shipment);
        }
    }

    if (!deliveredShipments.isEmpty()) {
        CompletedShipmentService.createCompletedShipments(deliveredShipments);
    }
}