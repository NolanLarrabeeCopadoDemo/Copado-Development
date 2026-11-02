public with sharing class EquipmentAvailabilityService_copado {

    private static final String SHIPMENT_STATUS_IN_TRANSIT = 'In Transit';
    private static final String SHIPMENT_STATUS_DELIVERED = 'Delivered';
    private static final String SHIPMENT_STATUS_CANCELLED = 'Cancelled';

    private static final String EQUIPMENT_STATUS_IN_TRANSIT = 'In_Transit';
    private static final String EQUIPMENT_STATUS_AVAILABLE = 'Available';
    private static final String EQUIPMENT_STATUS_MAINTENANCE = 'In_Maintenance';
    private static final String EQUIPMENT_STATUS_RETIRED = 'Retired';

    @TestVisible
    private static final Map<String, String> SHIPMENT_TO_EQUIPMENT_STATUS_MAP = new Map<String, String>{
        SHIPMENT_STATUS_IN_TRANSIT => EQUIPMENT_STATUS_IN_TRANSIT,
        SHIPMENT_STATUS_DELIVERED => EQUIPMENT_STATUS_AVAILABLE,
        SHIPMENT_STATUS_CANCELLED => EQUIPMENT_STATUS_AVAILABLE
    };

    private static final Set<String> GUARDED_EQUIPMENT_STATUSES = new Set<String>{
        EQUIPMENT_STATUS_MAINTENANCE,
        EQUIPMENT_STATUS_RETIRED
    };

    public static void updateEquipmentAvailability(List<Shipment__c> relevantShipments) {
        if (relevantShipments == null || relevantShipments.isEmpty()) {
            return;
        }

        Set<Id> equipmentIds = collectEquipmentIds(relevantShipments);
        if (equipmentIds.isEmpty()) {
            return;
        }

        Map<Id, Equipment__c> equipmentById = new Map<Id, Equipment__c>([
            SELECT Id, Operational_Status__c
            FROM Equipment__c
            WHERE Id IN :equipmentIds
        ]);

        List<Equipment__c> equipmentToUpdate = buildEquipmentUpdates(relevantShipments, equipmentById);
        if (equipmentToUpdate.isEmpty()) {
            return;
        }

        applyUpdates(equipmentToUpdate);
    }

    private static Set<Id> collectEquipmentIds(List<Shipment__c> relevantShipments) {
        Set<Id> equipmentIds = new Set<Id>();
        for (Shipment__c shipment : relevantShipments) {
            if (shipment.Equipment__c != null) {
                equipmentIds.add(shipment.Equipment__c);
            }
        }
        return equipmentIds;
    }

    private static List<Equipment__c> buildEquipmentUpdates(
        List<Shipment__c> relevantShipments,
        Map<Id, Equipment__c> equipmentById
    ) {
        Map<Id, Equipment__c> equipmentUpdatesById = new Map<Id, Equipment__c>();

        for (Shipment__c shipment : relevantShipments) {
            if (shipment.Equipment__c == null) {
                continue;
            }

            String targetStatus = SHIPMENT_TO_EQUIPMENT_STATUS_MAP.get(shipment.Status__c);
            if (targetStatus == null) {
                continue;
            }

            Equipment__c equipment = equipmentById.get(shipment.Equipment__c);
            if (equipment == null || GUARDED_EQUIPMENT_STATUSES.contains(equipment.Operational_Status__c)) {
                continue;
            }

            if (equipment.Operational_Status__c == targetStatus) {
                continue;
            }

            Logger.info(
                'EquipmentAvailabilityService_copado.updateEquipmentAvailability',
                'Equipment ' + equipment.Id + ' status transition: ' + equipment.Operational_Status__c + ' -> ' + targetStatus
            );

            equipmentUpdatesById.put(equipment.Id, new Equipment__c(Id = equipment.Id, Operational_Status__c = targetStatus));
        }

        return equipmentUpdatesById.values();
    }

    private static void applyUpdates(List<Equipment__c> equipmentToUpdate) {
        List<Database.SaveResult> saveResults = Database.update(equipmentToUpdate, false);
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult result = saveResults[i];
            if (!result.isSuccess()) {
                Logger.error(
                    'EquipmentAvailabilityService_copado.updateEquipmentAvailability',
                    'Failed to update Equipment ' + equipmentToUpdate[i].Id + ': ' + joinErrorMessages(result.getErrors())
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