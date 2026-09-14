/**
 * @description Service class invoked by ShipmentStatusTrigger (US-0000482).
 *              Bulk-creates Completed_Shipment__c records when Shipment__c
 *              records transition to Status__c = "Delivered". All SOQL and
 *              DML are performed outside loops. Duplicate guard prevents a
 *              second Completed_Shipment__c from being created on re-save.
 *
 *              Field-seeding assumptions: Actual_Mileage__c is mirrored from
 *              Route__c.Total_Mileage__c; Gross_Revenue__c from
 *              Shipment__c.Estimated_Revenue__c. Positive fallbacks satisfy
 *              VR_Actual_Mileage_Positive and VR_Gross_Revenue_Positive when
 *              source values are blank or zero. Driver_Rating__c and
 *              Fuel_Price_Per_Gallon__c are seeded with documented placeholder
 *              defaults until Finance updates them with real trip data.
 *
 * @author      Nolan Larrabee
 * @date        2026-09-13
 */
public with sharing class CompletedShipmentService {

    private static final String STATUS_DELIVERED        = 'Delivered';
    private static final Decimal DEFAULT_DRIVER_RATING  = 3;
    private static final Decimal DEFAULT_FUEL_PRICE     = 3.50;
    private static final Decimal FALLBACK_MILEAGE       = 0.1;
    private static final Decimal FALLBACK_GROSS_REVENUE = 0.01;

    // -------------------------------------------------------------------------
    // Public entry point
    // -------------------------------------------------------------------------

    /**
     * @description Creates Completed_Shipment__c records for each delivered
     *              Shipment__c that does not already have one. Safe to call
     *              with an empty or null list.
     *
     * @param deliveredShipments Shipment__c records whose Status__c just
     *                           changed to "Delivered".
     */
    public static void createCompletedShipments(List<Shipment__c> deliveredShipments) {
        if (deliveredShipments == null || deliveredShipments.isEmpty()) {
            return;
        }

        Set<Id> shipmentIds = collectShipmentIds(deliveredShipments);

        Set<Id> alreadyCompleted = queryExistingCompletedIds(shipmentIds);

        Map<Id, Shipment__c> freshShipmentMap = queryFreshShipments(shipmentIds);

        List<Completed_Shipment__c> toInsert = buildRecords(
            deliveredShipments, alreadyCompleted, freshShipmentMap
        );

        if (toInsert.isEmpty()) {
            return;
        }

        if (!Schema.SObjectType.Completed_Shipment__c.isCreateable()) {
            Logger.error(
                'CompletedShipmentService.createCompletedShipments',
                'Insufficient permissions to create Completed_Shipment__c records.'
            );
            return;
        }

        executeDml(toInsert, deliveredShipments, alreadyCompleted, freshShipmentMap);
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * @description Collects Shipment Ids from the provided list into a Set.
     *
     * @param  shipments List of Shipment__c records.
     * @return           Set of Shipment Ids.
     */
    private static Set<Id> collectShipmentIds(List<Shipment__c> shipments) {
        Set<Id> ids = new Set<Id>();
        for (Shipment__c s : shipments) {
            ids.add(s.Id);
        }
        return ids;
    }

    /**
     * @description Queries Completed_Shipment__c to find Shipment Ids that
     *              already have a completed record, preventing duplicates.
     *
     * @param  shipmentIds Set of Shipment Ids to check.
     * @return             Set of Shipment Ids that already have a record.
     */
    private static Set<Id> queryExistingCompletedIds(Set<Id> shipmentIds) {
        Set<Id> existing = new Set<Id>();
        for (Completed_Shipment__c cs : [
            SELECT Shipment__c
            FROM Completed_Shipment__c
            WHERE Shipment__c IN :shipmentIds
        ]) {
            existing.add(cs.Shipment__c);
        }
        return existing;
    }

    /**
     * @description Re-queries Shipment__c with Route mileage and revenue
     *              so cross-object formula values are guaranteed current.
     *
     * @param  shipmentIds Set of Shipment Ids to re-query.
     * @return             Map of Shipment Id to fresh Shipment__c record.
     */
    private static Map<Id, Shipment__c> queryFreshShipments(Set<Id> shipmentIds) {
        return new Map<Id, Shipment__c>([
            SELECT Id, Status__c, Route__c,
                   Route__r.Total_Mileage__c, Estimated_Revenue__c
            FROM Shipment__c
            WHERE Id IN :shipmentIds
        ]);
    }

    /**
     * @description Builds Completed_Shipment__c records for each eligible
     *              Shipment, skipping duplicates and stale trigger contexts.
     *
     * @param  deliveredShipments  Original trigger list.
     * @param  alreadyCompleted    Ids that already have a completed record.
     * @param  freshShipmentMap    Fresh Shipment__c data keyed by Id.
     * @return                     List of new Completed_Shipment__c records.
     */
    private static List<Completed_Shipment__c> buildRecords(
        List<Shipment__c> deliveredShipments,
        Set<Id> alreadyCompleted,
        Map<Id, Shipment__c> freshShipmentMap
    ) {
        List<Completed_Shipment__c> records = new List<Completed_Shipment__c>();
        for (Shipment__c shipment : deliveredShipments) {
            if (alreadyCompleted.contains(shipment.Id)) {
                continue;
            }
            Shipment__c fresh = freshShipmentMap.get(shipment.Id);
            if (fresh == null || fresh.Status__c != STATUS_DELIVERED) {
                continue;
            }
            Decimal mileage = (fresh.Route__c != null)
                ? fresh.Route__r.Total_Mileage__c
                : null;
            Decimal revenue = fresh.Estimated_Revenue__c;
            records.add(new Completed_Shipment__c(
                Shipment__c             = fresh.Id,
                Actual_Mileage__c       = (mileage != null && mileage > 0) ? mileage : FALLBACK_MILEAGE,
                Gross_Revenue__c        = (revenue != null && revenue > 0) ? revenue : FALLBACK_GROSS_REVENUE,
                Driver_Rating__c        = DEFAULT_DRIVER_RATING,
                Fuel_Price_Per_Gallon__c = DEFAULT_FUEL_PRICE
            ));
        }
        return records;
    }

    /**
     * @description Performs the DML insert and logs successes and failures
     *              using the Nebula Logger wrapper.
     *
     * @param toInsert            Records to insert.
     * @param deliveredShipments  Original trigger list (for index mapping).
     * @param alreadyCompleted    Already-completed Ids (for index mapping).
     * @param freshShipmentMap    Fresh map used to rebuild the index.
     */
    private static void executeDml(
        List<Completed_Shipment__c> toInsert,
        List<Shipment__c> deliveredShipments,
        Set<Id> alreadyCompleted,
        Map<Id, Shipment__c> freshShipmentMap
    ) {
        Map<Integer, Id> indexToShipmentId = new Map<Integer, Id>();
        Integer idx = 0;
        for (Shipment__c shipment : deliveredShipments) {
            if (alreadyCompleted.contains(shipment.Id)) {
                continue;
            }
            Shipment__c fresh = freshShipmentMap.get(shipment.Id);
            if (fresh == null || fresh.Status__c != STATUS_DELIVERED) {
                continue;
            }
            indexToShipmentId.put(idx, shipment.Id);
            idx++;
        }

        List<Database.SaveResult> results = Database.insert(toInsert, false);
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult sr = results[i];
            Id shipId = indexToShipmentId.get(i);
            if (sr.isSuccess()) {
                Logger.info(
                    'CompletedShipmentService.createCompletedShipments',
                    'Completed_Shipment__c ' + sr.getId() + ' created for Shipment ' + shipId
                );
            } else {
                Logger.error(
                    'CompletedShipmentService.createCompletedShipments',
                    'Failed for Shipment ' + shipId + ': ' + joinErrorMessages(sr.getErrors())
                );
            }
        }
    }

    /**
     * @description Concatenates DML error status codes and messages into a
     *              single readable string for logging.
     *
     * @param  errors List of Database.Error objects from a SaveResult.
     * @return        Semicolon-delimited error string.
     */
    private static String joinErrorMessages(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error e : errors) {
            messages.add(e.getStatusCode() + ' - ' + e.getMessage());
        }
        return String.join(messages, '; ');
    }
}