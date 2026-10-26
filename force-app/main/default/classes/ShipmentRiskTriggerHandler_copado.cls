/**
 * @description Before-save handler for Shipment risk scoring. Bulk-queries Route and Equipment, scores,
 * and never blocks a save.
 */
public with sharing class ShipmentRiskTriggerHandler_copado {
    @TestVisible private static Boolean skipScoring = false;
    @TestVisible private static Boolean forceFailure = false;

    /**
     * @description Scores the shipments being saved. Failures are logged and swallowed.
     * @param shipments Trigger.new
     */
    public static void handleBeforeSave(List<Shipment__c> shipments) {
        if (skipScoring || shipments == null || shipments.isEmpty()) {
            return;
        }
        try {
            if (forceFailure) {
                throw new IllegalArgumentException('Forced scoring failure');
            }
            Set<Id> routeIds = new Set<Id>();
            Set<Id> equipmentIds = new Set<Id>();
            for (Shipment__c sh : shipments) {
                if (sh.Route__c != null) {
                    routeIds.add(sh.Route__c);
                }
                if (sh.Equipment__c != null) {
                    equipmentIds.add(sh.Equipment__c);
                }
            }
            ShipmentRiskScoringService_copado.scoreShipments(shipments, loadRoutes(routeIds), loadEquipment(equipmentIds));
        } catch (Exception ex) {
            Logger.error('ShipmentRiskTriggerHandler_copado.handleBeforeSave', ex);
        }
    }

    /**
     * @description Bulk-queries routes.
     * @param ids Route Ids
     * @return Routes keyed by Id
     */
    public static Map<Id, Route__c> loadRoutes(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new Map<Id, Route__c>();
        }
        return new Map<Id, Route__c>([SELECT Id, Weather_Severity__c FROM Route__c WHERE Id IN :ids WITH USER_MODE]);
    }

    /**
     * @description Bulk-queries equipment.
     * @param ids Equipment Ids
     * @return Equipment keyed by Id
     */
    public static Map<Id, Equipment__c> loadEquipment(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new Map<Id, Equipment__c>();
        }
        return new Map<Id, Equipment__c>([SELECT Id, Payload_Capacity_lbs__c FROM Equipment__c WHERE Id IN :ids WITH USER_MODE]);
    }
}