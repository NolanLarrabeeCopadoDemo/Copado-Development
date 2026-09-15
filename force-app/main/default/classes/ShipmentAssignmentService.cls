public with sharing class ShipmentAssignmentService {

    @TestVisible
    private static final Map<String, Schema.SObjectField> CARGO_TYPE_COMPATIBILITY_MAP = new Map<String, Schema.SObjectField>{
        'Refrigerated' => Equipment__c.Refrigeration_Capable__c,
        'Hazmat' => Equipment__c.Hazmat_Certified__c
    };

    private static final String STATUS_CANCELLED = 'Cancelled';

    public static Map<Id, String> validateAssignments(List<Shipment__c> shipments, Map<Id, Equipment__c> equipmentById) {
        Map<Id, String> errorsByShipmentId = new Map<Id, String>();
        if (shipments == null) {
            return errorsByShipmentId;
        }

        Map<Id, Equipment__c> safeEquipmentById = equipmentById == null ? new Map<Id, Equipment__c>() : equipmentById;
        for (Shipment__c shipment : shipments) {
            errorsByShipmentId.put(shipment.Id, validateSingleAssignment(shipment, safeEquipmentById));
        }
        return errorsByShipmentId;
    }

    private static String validateSingleAssignment(Shipment__c shipment, Map<Id, Equipment__c> equipmentById) {
        if (shipment.Equipment__c == null || STATUS_CANCELLED.equals(shipment.Status__c)) {
            return '';
        }

        Equipment__c equipment = equipmentById.get(shipment.Equipment__c);
        if (equipment == null) {
            return '';
        }

        String failedRule = determineFailedRule(shipment, equipment);
        if (failedRule == null) {
            return '';
        }

        String errorMessage = buildErrorMessage(shipment, equipment, failedRule);
        logAssignmentFailure(shipment.Id, equipment.Id, failedRule, errorMessage);
        return errorMessage;
    }

    private static String determineFailedRule(Shipment__c shipment, Equipment__c equipment) {
        if (isWeightExceeded(shipment, equipment)) {
            return 'WEIGHT_EXCEEDS_PAYLOAD_CAPACITY';
        }
        if (isVolumeExceeded(shipment, equipment)) {
            return 'VOLUME_EXCEEDS_CARGO_CAPACITY';
        }
        if (isCargoTypeIncompatible(shipment, equipment)) {
            return 'CARGO_TYPE_INCOMPATIBLE';
        }
        return null;
    }

    private static Boolean isWeightExceeded(Shipment__c shipment, Equipment__c equipment) {
        return shipment.Cargo_Weight_lbs__c != null
            && equipment.Payload_Capacity_lbs__c != null
            && shipment.Cargo_Weight_lbs__c > equipment.Payload_Capacity_lbs__c;
    }

    private static Boolean isVolumeExceeded(Shipment__c shipment, Equipment__c equipment) {
        return shipment.Cargo_Volume_Cu_Ft__c != null
            && equipment.Cargo_Capacity_Lbs__c != null
            && shipment.Cargo_Volume_Cu_Ft__c > equipment.Cargo_Capacity_Lbs__c;
    }

    private static Boolean isCargoTypeIncompatible(Shipment__c shipment, Equipment__c equipment) {
        if (String.isBlank(shipment.Cargo_Type__c) || !CARGO_TYPE_COMPATIBILITY_MAP.containsKey(shipment.Cargo_Type__c)) {
            return false;
        }
        Schema.SObjectField requiredField = CARGO_TYPE_COMPATIBILITY_MAP.get(shipment.Cargo_Type__c);
        Boolean isCapable = (Boolean) equipment.get(requiredField);
        return isCapable != true;
    }

    private static String buildErrorMessage(Shipment__c shipment, Equipment__c equipment, String failedRule) {
        if (failedRule == 'WEIGHT_EXCEEDS_PAYLOAD_CAPACITY') {
            return 'Cargo weight (' + shipment.Cargo_Weight_lbs__c + ' lbs) exceeds equipment payload capacity ('
                + equipment.Payload_Capacity_lbs__c + ' lbs).';
        }
        if (failedRule == 'VOLUME_EXCEEDS_CARGO_CAPACITY') {
            return 'Cargo volume (' + shipment.Cargo_Volume_Cu_Ft__c + ' cu ft) exceeds equipment cargo capacity ('
                + equipment.Cargo_Capacity_Lbs__c + ').';
        }
        return 'Equipment is not certified to carry cargo type: ' + shipment.Cargo_Type__c + '.';
    }

    private static void logAssignmentFailure(Id shipmentId, Id equipmentId, String failedRule, String errorMessage) {
        String context = 'ShipmentAssignmentService';
        String detail = 'Shipment: ' + shipmentId + ' | Equipment: ' + equipmentId + ' | Rule: ' + failedRule + ' | ' + errorMessage;
        Logger.error(context, detail);
    }
}