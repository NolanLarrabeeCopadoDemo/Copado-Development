/**
 * @description Provides read access to Equipment__c fleet availability data for the
 * equipment-availability-copado Lightning web component. Enforces CRUD/FLS via
 * WITH SECURITY_ENFORCED and explicit object/field accessibility checks.
 *
 * Design note on Active_Shipment__c:
 *   This field is a self-referencing placeholder lookup on Equipment__c
 *   (relationshipName: Active_Shipment_Placeholder). Because the relationship
 *   resolves to the same SObject, the parent record Name is retrieved via a
 *   secondary query keyed on the populated Id values rather than inline SOQL
 *   traversal, which is unsupported until the field is repointed to Shipment__c.
 *   The method returns a wrapper so the LWC can render the active-shipment name
 *   without additional callouts.
 */
public with sharing class EquipmentAvailabilityController_copado {

    /**
     * @description Wrapper exposing Equipment__c data plus the resolved
     * active-shipment display name for the fleet availability grid.
     */
    public class EquipmentWrapper {
        @AuraEnabled public Equipment__c equipment { get; set; }
        @AuraEnabled public String activeShipmentName { get; set; }

        public EquipmentWrapper(Equipment__c equip, String shipName) {
            this.equipment        = equip;
            this.activeShipmentName = shipName;
        }
    }

    /**
     * @description Wire-enabled method returning all accessible Equipment__c records
     * as EquipmentWrapper instances, each including a resolved active-shipment name.
     * CRUD/FLS enforced via isAccessible() guard and WITH SECURITY_ENFORCED SOQL.
     * @return List<EquipmentWrapper> visible to the running user.
     */
    @AuraEnabled(cacheable=true)
    public static List<EquipmentWrapper> getEquipmentAvailability() {
        if (!Schema.sObjectType.Equipment__c.isAccessible()) {
            throw new AuraHandledException(
                'You do not have access to view fleet equipment availability.'
            );
        }

        List<Equipment__c> equipmentRecords;
        try {
            equipmentRecords = [
                SELECT Id, Truck_ID__c, Truck_Size_Class__c, Operational_Status__c,
                       Payload_Capacity_lbs__c, Cargo_Volume_Cu_Ft__c,
                       Active_Shipment__c
                FROM Equipment__c
                WITH SECURITY_ENFORCED
                ORDER BY Truck_ID__c ASC
            ];
        } catch (System.QueryException queryException) {
            throw new AuraHandledException(
                'You do not have access to view fleet equipment availability.'
            );
        }

        // Collect referenced Equipment Ids for the active-shipment name lookup
        Set<Id> activeShipmentIds = new Set<Id>();
        for (Equipment__c eq : equipmentRecords) {
            if (eq.Active_Shipment__c != null) {
                activeShipmentIds.add(eq.Active_Shipment__c);
            }
        }

        // Secondary query for placeholder names — no relationship traversal needed
        Map<Id, String> shipmentNameById = new Map<Id, String>();
        if (!activeShipmentIds.isEmpty() && Schema.sObjectType.Equipment__c.isAccessible()) {
            for (Equipment__c ref : [
                SELECT Id, Truck_ID__c
                FROM Equipment__c
                WHERE Id IN :activeShipmentIds
                WITH SECURITY_ENFORCED
            ]) {
                shipmentNameById.put(ref.Id, ref.Truck_ID__c);
            }
        }

        // Build wrappers
        List<EquipmentWrapper> results = new List<EquipmentWrapper>();
        for (Equipment__c eq : equipmentRecords) {
            String shipName = eq.Active_Shipment__c != null
                ? shipmentNameById.get(eq.Active_Shipment__c)
                : null;
            results.add(new EquipmentWrapper(eq, shipName));
        }

        return results;
    }
}