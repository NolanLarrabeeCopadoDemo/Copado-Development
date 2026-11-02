/**
 * @description After-update trigger on Shipment__c (US-0000482).
 *              Detects status transitions to "Delivered" and delegates all
 *              business logic to CompletedShipmentService. No logic lives
 *              inside the trigger body beyond delegation.
 *
 * @author      Nolan Larrabee
 * @date        2026-09-13
 */
trigger ShipmentStatusTrigger on Shipment__c (after update) {
    List<Shipment__c> deliveredShipments = new List<Shipment__c>();
    for (Shipment__c shipment : Trigger.new) {
        Shipment__c oldShipment = Trigger.oldMap.get(shipment.Id);
        if (shipment.Status__c == 'Delivered' && oldShipment.Status__c != 'Delivered') {
            deliveredShipments.add(shipment);
        }
    }
    CompletedShipmentService.createCompletedShipments(deliveredShipments);
}