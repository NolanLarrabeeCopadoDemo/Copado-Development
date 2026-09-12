/**
 * Service class invoked by the shipment-status-copado trigger (US-0000482).
 * Bulk-creates Completed_Shipment__c records when Shipment__c records transition
 * to Status__c = 'Delivered'. All SOQL and DML are performed outside loops.
 *
 * Field seeding assumptions (no dedicated source fields exist on Shipment__c/Route__c
 * for driver rating or fuel price, and Completed_Shipment__c enforces "must be positive"
 * validation rules on several fields): Actual_Mileage__c and Gross_Revenue__c are mirrored
 * from the parent Route__c.Total_Mileage__c and Shipment__c.Estimated_Revenue__c
 * respectively, re-queried fresh (rather than trusting trigger-context formula values) so
 * cross-object formulas are guaranteed current; a minimal positive fallback is used when a
 * Shipment has no Route or a zero/blank Estimated Revenue, since VR_Actual_Mileage_Positive
 * and VR_Gross_Revenue_Positive block blank/zero values. Driver_Rating__c and
 * Fuel_Price_Per_Gallon__c are seeded with documented placeholder defaults so newly created
 * records satisfy VR_Driver_Rating_Range and VR_Fuel_Price_Positive until Finance updates
 * them with real trip data. RecordTypeId is intentionally left unset; Completed_Shipment__c
 * uses whatever record type the current user's profile defaults to.
 */
public with sharing class CompletedShipmentService {

    private static final String STATUS_DELIVERED = 'Delivered';
    private static final Decimal DEFAULT_DRIVER_RATING = 3;
    private static final Decimal DEFAULT_FUEL_PRICE_PER_GALLON = 3.50;
    private static final Decimal FALLBACK_MILEAGE = 0.1;
    private static final Decimal FALLBACK_GROSS_REVENUE = 0.01;

    public static void createCompletedShipments(List<Shipment__c> deliveredShipments) {
        if (deliveredShipments == null || deliveredShipments.isEmpty()) {
            return;
        }

        Set<Id> shipmentIds = new Set<Id>();
        for (Shipment__c shipment : deliveredShipments) {
            shipmentIds.add(shipment.Id);
        }

        Set<Id> shipmentIdsWithCompletedRecord = new Set<Id>();
        for (Completed_Shipment__c existing : [
            SELECT Shipment__c
            FROM Completed_Shipment__c
            WHERE Shipment__c IN :shipmentIds
        ]) {
            shipmentIdsWithCompletedRecord.add(existing.Shipment__c);
        }

        Map<Id, Shipment__c> shipmentIdToFreshShipment = new Map<Id, Shipment__c>([
            SELECT Id, Status__c, Route__c, Route__r.Total_Mileage__c, Estimated_Revenue__c
            FROM Shipment__c
            WHERE Id IN :shipmentIds
        ]);

        List<Completed_Shipment__c> completedShipmentsToInsert = new List<Completed_Shipment__c>();
        Map<Integer, Id> insertIndexToShipmentId = new Map<Integer, Id>();

        for (Shipment__c shipment : deliveredShipments) {
            if (shipmentIdsWithCompletedRecord.contains(shipment.Id)) {
                continue;
            }
            Shipment__c freshShipment = shipmentIdToFreshShipment.get(shipment.Id);
            if (freshShipment == null || freshShipment.Status__c != STATUS_DELIVERED) {
                continue;
            }

            Decimal mileage = freshShipment.Route__c != null ? freshShipment.Route__r.Total_Mileage__c : null;
            Decimal grossRevenue = freshShipment.Estimated_Revenue__c;

            Completed_Shipment__c completedShipment = new Completed_Shipment__c(
                Shipment__c = freshShipment.Id,
                Actual_Mileage__c = (mileage != null && mileage > 0) ? mileage : FALLBACK_MILEAGE,
                Gross_Revenue__c = (grossRevenue != null && grossRevenue > 0) ? grossRevenue : FALLBACK_GROSS_REVENUE,
                Driver_Rating__c = DEFAULT_DRIVER_RATING,
                Fuel_Price_Per_Gallon__c = DEFAULT_FUEL_PRICE_PER_GALLON
            );

            insertIndexToShipmentId.put(completedShipmentsToInsert.size(), freshShipment.Id);
            completedShipmentsToInsert.add(completedShipment);
        }

        if (completedShipmentsToInsert.isEmpty()) {
            return;
        }

        List<Database.SaveResult> saveResults = Database.insert(completedShipmentsToInsert, false);
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult result = saveResults[i];
            Id relatedShipmentId = insertIndexToShipmentId.get(i);
            if (result.isSuccess()) {
                Logger.info(
                    'CompletedShipmentService.createCompletedShipments',
                    'Completed_Shipment__c ' + result.getId() + ' created for Shipment ' + relatedShipmentId
                );
            } else {
                String errorMessages = joinErrorMessages(result.getErrors());
                Logger.error(
                    'CompletedShipmentService.createCompletedShipments',
                    'Failed to create Completed_Shipment__c for Shipment ' + relatedShipmentId + ': ' + errorMessages
                );
            }
        }
    }

    private static String joinErrorMessages(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error dmlError : errors) {
            messages.add(dmlError.getStatusCode() + ' - ' + dmlError.getMessage());
        }
        return String.join(messages, '; ');
    }
}