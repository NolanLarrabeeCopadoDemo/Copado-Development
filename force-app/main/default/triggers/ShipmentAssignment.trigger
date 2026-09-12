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

    // ShipmentAssignmentService.validateAssignments returns a Map<Id, String> keyed by
    // Shipment__c Id. Before insert, new records have no Id yet, so each shipment is
    // validated with its own single-element list to keep per-record results distinct
    // while all SOQL stays outside this loop (no DML/SOQL in loop).
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