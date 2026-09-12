/**
 * Covers ShipmentAssignmentService validation logic as invoked via the ShipmentAssignment
 * trigger: positive assignment, weight exceeded, volume exceeded, cargo type incompatibility,
 * and bulk mixed-result scenarios.
 */
@IsTest
private class ShipmentAssignmentServiceTest {

    @IsTest
    static void testPositiveAssignment_NoErrors() {
        Equipment__c equipment = LogisticsTestFactory.buildEquipment(new Map<String, Object>{
            'Payload_Capacity_lbs__c' => 20000,
            'Cargo_Capacity_Lbs__c' => 2000
        });
        insert equipment;

        Shipment__c shipment = LogisticsTestFactory.buildShipment(new Map<String, Object>{
            'Cargo_Weight_lbs__c' => 5000,
            'Cargo_Volume_Cu_Ft__c' => 500,
            'Cargo_Type__c' => 'General Freight',
            'Equipment__c' => equipment.Id,
            'Status__c' => 'Draft'
        });

        Test.startTest();
        insert shipment;
        Test.stopTest();

        Shipment__c inserted = [SELECT Id, Equipment__c FROM Shipment__c WHERE Id = :shipment.Id];
        System.assertEquals(equipment.Id, inserted.Equipment__c, 'Shipment should be assigned to equipment.');
    }

    @IsTest
    static void testWeightExceeded_BlocksAssignment() {
        Equipment__c equipment = LogisticsTestFactory.buildEquipment(new Map<String, Object>{
            'Payload_Capacity_lbs__c' => 1000,
            'Cargo_Capacity_Lbs__c' => 2000
        });
        insert equipment;

        Shipment__c shipment = LogisticsTestFactory.buildShipment(new Map<String, Object>{
            'Cargo_Weight_lbs__c' => 5000,
            'Cargo_Volume_Cu_Ft__c' => 100,
            'Cargo_Type__c' => 'General Freight',
            'Equipment__c' => equipment.Id,
            'Status__c' => 'Draft'
        });

        Test.startTest();
        Database.SaveResult result = Database.insert(shipment, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Insert should fail when cargo weight exceeds payload capacity.');
        System.assert(
            result.getErrors()[0].getMessage().contains('exceeds equipment payload capacity'),
            'Error message should reference payload capacity.'
        );
    }

    @IsTest
    static void testVolumeExceeded_BlocksAssignment() {
        Equipment__c equipment = LogisticsTestFactory.buildEquipment(new Map<String, Object>{
            'Payload_Capacity_lbs__c' => 20000,
            'Cargo_Capacity_Lbs__c' => 100
        });
        insert equipment;

        Shipment__c shipment = LogisticsTestFactory.buildShipment(new Map<String, Object>{
            'Cargo_Weight_lbs__c' => 500,
            'Cargo_Volume_Cu_Ft__c' => 5000,
            'Cargo_Type__c' => 'General Freight',
            'Equipment__c' => equipment.Id,
            'Status__c' => 'Draft'
        });

        Test.startTest();
        Database.SaveResult result = Database.insert(shipment, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Insert should fail when cargo volume exceeds cargo capacity.');
        System.assert(
            result.getErrors()[0].getMessage().contains('exceeds equipment cargo capacity'),
            'Error message should reference cargo capacity.'
        );
    }

    @IsTest
    static void testCargoTypeIncompatible_BlocksAssignment() {
        Equipment__c equipment = LogisticsTestFactory.buildEquipment(new Map<String, Object>{
            'Payload_Capacity_lbs__c' => 20000,
            'Cargo_Capacity_Lbs__c' => 2000,
            'Refrigeration_Capable__c' => false
        });
        insert equipment;

        Shipment__c shipment = LogisticsTestFactory.buildShipment(new Map<String, Object>{
            'Cargo_Weight_lbs__c' => 500,
            'Cargo_Volume_Cu_Ft__c' => 100,
            'Cargo_Type__c' => 'Refrigerated',
            'Equipment__c' => equipment.Id,
            'Status__c' => 'Draft'
        });

        Test.startTest();
        Database.SaveResult result = Database.insert(shipment, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Insert should fail when equipment is not refrigeration capable.');
        System.assert(
            result.getErrors()[0].getMessage().contains('not certified to carry cargo type'),
            'Error message should reference cargo type certification.'
        );
    }

    @IsTest
    static void testNoEquipmentAssigned_SkipsValidation() {
        Shipment__c shipment = LogisticsTestFactory.buildShipment(new Map<String, Object>{
            'Cargo_Weight_lbs__c' => 999999,
            'Cargo_Volume_Cu_Ft__c' => 999999,
            'Status__c' => 'Draft',
            'Equipment__c' => null
        });

        Test.startTest();
        insert shipment;
        Test.stopTest();

        Shipment__c inserted = [SELECT Id, Equipment__c FROM Shipment__c WHERE Id = :shipment.Id];
        System.assertEquals(null, inserted.Equipment__c, 'Shipment without equipment should insert without validation.');
    }

    @IsTest
    static void testCancelledStatus_SkipsValidation() {
        // Weight/volume intentionally kept within the org's standing VR_Cargo_Fits_Truck
        // validation rule threshold so this test isolates the trigger's own cancelled-status
        // bypass rather than the pre-existing field-level validation rule.
        Equipment__c equipment = LogisticsTestFactory.buildEquipment(new Map<String, Object>{
            'Payload_Capacity_lbs__c' => 100,
            'Cargo_Capacity_Lbs__c' => 50
        });
        insert equipment;

        Shipment__c shipment = LogisticsTestFactory.buildShipment(new Map<String, Object>{
            'Cargo_Weight_lbs__c' => 90,
            'Cargo_Volume_Cu_Ft__c' => 999999,
            'Cargo_Type__c' => 'General Freight',
            'Equipment__c' => equipment.Id,
            'Status__c' => 'Cancelled'
        });

        Test.startTest();
        insert shipment;
        Test.stopTest();

        Shipment__c inserted = [SELECT Id, Equipment__c FROM Shipment__c WHERE Id = :shipment.Id];
        System.assertEquals(equipment.Id, inserted.Equipment__c, 'Cancelled shipments should skip capacity validation.');
    }

    @IsTest
    static void testBulkScenarios_MixedResults() {
        Equipment__c goodEquipment = LogisticsTestFactory.buildEquipment(new Map<String, Object>{
            'Payload_Capacity_lbs__c' => 20000,
            'Cargo_Capacity_Lbs__c' => 2000
        });
        Equipment__c smallEquipment = LogisticsTestFactory.buildEquipment(new Map<String, Object>{
            'Payload_Capacity_lbs__c' => 500,
            'Cargo_Capacity_Lbs__c' => 50
        });
        insert new List<Equipment__c>{ goodEquipment, smallEquipment };

        List<Shipment__c> shipments = new List<Shipment__c>();
        for (Integer i = 0; i < 5; i++) {
            shipments.add(LogisticsTestFactory.buildShipment(new Map<String, Object>{
                'Cargo_Weight_lbs__c' => 5000,
                'Cargo_Volume_Cu_Ft__c' => 500,
                'Cargo_Type__c' => 'General Freight',
                'Equipment__c' => goodEquipment.Id,
                'Status__c' => 'Draft'
            }));
        }
        for (Integer i = 0; i < 3; i++) {
            shipments.add(LogisticsTestFactory.buildShipment(new Map<String, Object>{
                'Cargo_Weight_lbs__c' => 5000,
                'Cargo_Volume_Cu_Ft__c' => 500,
                'Cargo_Type__c' => 'General Freight',
                'Equipment__c' => smallEquipment.Id,
                'Status__c' => 'Draft'
            }));
        }

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(shipments, false);
        Test.stopTest();

        Integer successCount = 0;
        Integer failureCount = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                successCount++;
            } else {
                failureCount++;
            }
        }
        System.assertEquals(5, successCount, 'Shipments assigned to well-sized equipment should succeed.');
        System.assertEquals(3, failureCount, 'Shipments assigned to undersized equipment should fail.');
    }
}