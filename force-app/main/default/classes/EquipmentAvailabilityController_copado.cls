/**
 * @description Provides read access to Equipment__c fleet availability data for the
 * equipment-availability-copado Lightning web component. Enforces CRUD/FLS via
 * WITH SECURITY_ENFORCED and explicit object/field accessibility checks.
 */
public with sharing class EquipmentAvailabilityController_copado {

    /**
     * @description Wire-enabled method returning all accessible Equipment__c records
     * with the fields required by the fleet availability grid.
     * @return List of Equipment__c records the running user can access.
     */
    @AuraEnabled(cacheable=true)
    public static List<Equipment__c> getEquipmentAvailability() {
        if (!Schema.sObjectType.Equipment__c.isAccessible()) {
            throw new AuraHandledException('You do not have access to view fleet equipment availability.');
        }

        try {
            return [
                SELECT Id, Truck_ID__c, Truck_Size_Class__c, Operational_Status__c,
                       Payload_Capacity_lbs__c, Cargo_Volume_Cu_Ft__c,
                       Active_Shipment__c, Active_Shipment__r.Name
                FROM Equipment__c
                WITH SECURITY_ENFORCED
                ORDER BY Truck_ID__c ASC
            ];
        } catch (System.QueryException queryException) {
            throw new AuraHandledException('You do not have access to view fleet equipment availability.');
        }
    }
}