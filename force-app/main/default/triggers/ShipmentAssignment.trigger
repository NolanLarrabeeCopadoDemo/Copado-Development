/**
 * Enforces shipment-to-equipment capacity and cargo-type compatibility before a Shipment__c
 * record is saved. Bulk-queries Equipment__c once for the trigger set, then delegates the
 * per-record validation decision to ShipmentAssignmentService.
 */
trigger ShipmentAssignment on Shipment__c (before insert, before update) {

    Set<Id> equipmentIds = new Set<Id>();
    for (Shipment__c shipment : Trigger.new) {
        if (shipment.Equipment__c != null) {
            equipmentIds.add(shipment.Equipment__c);
        }
    }

    Map<Id, Equipment__c> equipmentById = equipmentIds.isEmpty()
        ? new Map<Id, Equipment__c>()
        : new Map<Id, Equipment__c>([
            SELECT Id, Payload_Capacity_lbs__c, Cargo_Capacity_Lbs__c,
                   Refrigeration_Capable__c, Hazmat_Certified__c
            FROM Equipment__c
            WHERE Id IN :equipmentIds
        ]);

    for (Shipment__c shipment : Trigger.new) {
        Map<Id, String> errorsByShipmentId = ShipmentAssignmentService.validateAssignments(
            new List<Shipment__c>{ shipment },
            equipmentById
        );
        String errorMessage = errorsByShipmentId.get(shipment.Id);
        if (String.isNotBlank(errorMessage)) {
            shipment.addError(errorMessage);
        }
    }
}