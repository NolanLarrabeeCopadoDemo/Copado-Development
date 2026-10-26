/**
 * @description Nightly batch that recalculates risk for open shipments. Batchable and Schedulable.
 * The risk fields are system-calculated, so the update runs in system mode after an explicit object
 * update (CRUD) check.
 */
public with sharing class ShipmentRiskScoringBatch_copado implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
    public static final Integer SCOPE_SIZE = 200;
    @TestVisible private static Boolean forceFailure = false;
    public Integer failureCount = 0;

    /**
     * @description Queries open shipments.
     * @param bc batch context
     * @return query locator
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Status__c, Cargo_Type__c, Cargo_Weight_lbs__c, Expected_Delivery_Date__c, Route__c, Equipment__c
            FROM Shipment__c
            WHERE Status__c != 'Delivered' AND Status__c != 'Cancelled'
            WITH USER_MODE
        ]);
    }

    /**
     * @description Scores a chunk and updates with partial success, logging per-record failures.
     * @param bc batch context
     * @param scope shipments
     */
    public void execute(Database.BatchableContext bc, List<Shipment__c> scope) {
        try {
            if (forceFailure || !Schema.sObjectType.Shipment__c.isUpdateable()) {
                throw new IllegalArgumentException('Shipment__c is not updateable or failure forced');
            }
            Set<Id> routeIds = new Set<Id>();
            Set<Id> equipmentIds = new Set<Id>();
            for (Shipment__c sh : scope) {
                if (sh.Route__c != null) {
                    routeIds.add(sh.Route__c);
                }
                if (sh.Equipment__c != null) {
                    equipmentIds.add(sh.Equipment__c);
                }
            }
            ShipmentRiskScoringService_copado.scoreShipments(
                scope,
                ShipmentRiskTriggerHandler_copado.loadRoutes(routeIds),
                ShipmentRiskTriggerHandler_copado.loadEquipment(equipmentIds)
            );
            List<Database.SaveResult> results = Database.update(scope, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    failureCount++;
                    Logger.error('ShipmentRiskScoringBatch_copado', 'Shipment ' + scope[i].Id + ' failed: ' + results[i].getErrors()[0].getMessage());
                }
            }
        } catch (Exception ex) {
            failureCount += scope.size();
            Logger.error('ShipmentRiskScoringBatch_copado.execute', ex);
        }
    }

    /**
     * @description Finish hook.
     * @param bc batch context
     */
    public void finish(Database.BatchableContext bc) {
        Logger.info('ShipmentRiskScoringBatch_copado', 'Completed with ' + failureCount + ' failure(s)');
    }

    /**
     * @description Schedulable entry point.
     * @param sc schedulable context
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ShipmentRiskScoringBatch_copado(), SCOPE_SIZE);
    }
}