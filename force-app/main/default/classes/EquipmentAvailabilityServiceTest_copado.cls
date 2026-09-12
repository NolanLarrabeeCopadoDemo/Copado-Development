@IsTest
private class EquipmentAvailabilityServiceTest_copado {

    @TestSetup
    static void setupData() {
        Equipment__c availableEquipment = LogisticsTestFactory.buildEquipment(
            new Map<String, Object>{ 'Truck_ID__c' => 'TRK-AVAIL-01', 'Operational_Status__c' => 'Available' }
        );
        Equipment__c maintenanceEquipment = LogisticsTestFactory.buildEquipment(
            new Map<String, Object>{ 'Truck_ID__c' => 'TRK-MAINT-01', 'Operational_Status__c' => 'In_Maintenance' }
        );
        Equipment__c retiredEquipment = LogisticsTestFactory.buildEquipment(
            new Map<String, Object>{ 'Truck_ID__c' => 'TRK-RETIRE-01', 'Operational_Status__c' => 'Retired' }
        );
        insert new List<Equipment__c>{ availableEquipment, maintenanceEquipment, retiredEquipment };

        List<Equipment__c> bulkEquipment = new List<Equipment__c>();
        for (Integer i = 0; i < 20; i++) {
            bulkEquipment.add(LogisticsTestFactory.buildEquipment(
                new Map<String, Object>{ 'Truck_ID__c' => 'TRK-BULK-' + i, 'Operational_Status__c' => 'Available' }
            ));
        }
        insert bulkEquipment;

        List<Shipment__c> shipments = new List<Shipment__c>();
        shipments.add(LogisticsTestFactory.buildShipment(
            new Map<String, Object>{ 'Status__c' => 'Scheduled', 'Equipment__c' => availableEquipment.Id }
        ));
        shipments.add(LogisticsTestFactory.buildShipment(
            new Map<String, Object>{ 'Status__c' => 'Scheduled', 'Equipment__c' => availableEquipment.Id }
        ));
        shipments.add(LogisticsTestFactory.buildShipment(
            new Map<String, Object>{ 'Status__c' => 'Scheduled', 'Equipment__c' => availableEquipment.Id }
        ));
        shipments.add(LogisticsTestFactory.buildShipment(
            new Map<String, Object>{ 'Status__c' => 'In Transit', 'Equipment__c' => maintenanceEquipment.Id }
        ));
        shipments.add(LogisticsTestFactory.buildShipment(
            new Map<String, Object>{ 'Status__c' => 'In Transit', 'Equipment__c' => retiredEquipment.Id }
        ));
        shipments.add(LogisticsTestFactory.buildShipment(
            new Map<String, Object>{ 'Status__c' => 'Draft', 'Equipment__c' => null }
        ));
        for (Equipment__c equipment : bulkEquipment) {
            shipments.add(LogisticsTestFactory.buildShipment(
                new Map<String, Object>{ 'Status__c' => 'Scheduled', 'Equipment__c' => equipment.Id }
            ));
        }
        insert shipments;
    }

    @IsTest
    static void testInTransitSetsEquipmentInTransit() {
        Equipment__c equipment = [SELECT Id FROM Equipment__c WHERE Truck_ID__c = 'TRK-AVAIL-01' LIMIT 1];
        Shipment__c shipment = [SELECT Id, Status__c FROM Shipment__c WHERE Equipment__c = :equipment.Id ORDER BY CreatedDate LIMIT 1];

        Test.startTest();
        shipment.Status__c = 'In Transit';
        update shipment;
        Test.stopTest();

        Equipment__c updatedEquipment = [SELECT Operational_Status__c FROM Equipment__c WHERE Id = :equipment.Id];
        System.assertEquals('In_Transit', updatedEquipment.Operational_Status__c, 'Equipment should move to In_Transit');
    }

    @IsTest
    static void testDeliveredSetsEquipmentAvailable() {
        Equipment__c equipment = [SELECT Id FROM Equipment__c WHERE Truck_ID__c = 'TRK-AVAIL-01' LIMIT 1];
        List<Shipment__c> equipmentShipments = [SELECT Id, Status__c FROM Shipment__c WHERE Equipment__c = :equipment.Id ORDER BY CreatedDate];
        Shipment__c shipment = equipmentShipments[0];
        shipment.Status__c = 'In Transit';
        update shipment;

        Test.startTest();
        shipment.Status__c = 'Delivered';
        update shipment;
        Test.stopTest();

        Equipment__c updatedEquipment = [SELECT Operational_Status__c FROM Equipment__c WHERE Id = :equipment.Id];
        System.assertEquals('Available', updatedEquipment.Operational_Status__c, 'Equipment should return to Available on Delivered');
    }

    @IsTest
    static void testCancelledSetsEquipmentAvailable() {
        Equipment__c equipment = [SELECT Id FROM Equipment__c WHERE Truck_ID__c = 'TRK-AVAIL-01' LIMIT 1];
        List<Shipment__c> equipmentShipments = [SELECT Id, Status__c FROM Shipment__c WHERE Equipment__c = :equipment.Id ORDER BY CreatedDate];
        Shipment__c shipment = equipmentShipments[1];
        shipment.Status__c = 'In Transit';
        update shipment;

        Test.startTest();
        shipment.Status__c = 'Cancelled';
        update shipment;
        Test.stopTest();

        Equipment__c updatedEquipment = [SELECT Operational_Status__c FROM Equipment__c WHERE Id = :equipment.Id];
        System.assertEquals('Available', updatedEquipment.Operational_Status__c, 'Equipment should return to Available on Cancelled');
    }

    @IsTest
    static void testMaintenanceGuardSkipsUpdate() {
        Equipment__c equipment = [SELECT Id FROM Equipment__c WHERE Truck_ID__c = 'TRK-MAINT-01' LIMIT 1];
        Shipment__c shipment = [SELECT Id, Status__c FROM Shipment__c WHERE Equipment__c = :equipment.Id LIMIT 1];

        Test.startTest();
        shipment.Status__c = 'Delivered';
        update shipment;
        Test.stopTest();

        Equipment__c updatedEquipment = [SELECT Operational_Status__c FROM Equipment__c WHERE Id = :equipment.Id];
        System.assertEquals('In_Maintenance', updatedEquipment.Operational_Status__c, 'Equipment in maintenance should not be updated');
    }

    @IsTest
    static void testRetiredGuardSkipsUpdate() {
        Equipment__c equipment = [SELECT Id FROM Equipment__c WHERE Truck_ID__c = 'TRK-RETIRE-01' LIMIT 1];
        Shipment__c shipment = [SELECT Id, Status__c FROM Shipment__c WHERE Equipment__c = :equipment.Id LIMIT 1];

        Test.startTest();
        shipment.Status__c = 'Cancelled';
        update shipment;
        Test.stopTest();

        Equipment__c updatedEquipment = [SELECT Operational_Status__c FROM Equipment__c WHERE Id = :equipment.Id];
        System.assertEquals('Retired', updatedEquipment.Operational_Status__c, 'Retired equipment should not be updated');
    }

    @IsTest
    static void testNullEquipmentGuardDoesNotThrow() {
        Shipment__c shipment = [SELECT Id, Status__c, Equipment__c FROM Shipment__c WHERE Equipment__c = null LIMIT 1];

        Test.startTest();
        shipment.Status__c = 'Cancelled';
        update shipment;
        Test.stopTest();

        Shipment__c updatedShipment = [SELECT Status__c, Equipment__c FROM Shipment__c WHERE Id = :shipment.Id];
        System.assertEquals('Cancelled', updatedShipment.Status__c, 'Shipment with no equipment should still update without error');
        System.assertEquals(null, updatedShipment.Equipment__c, 'Equipment should remain null');
    }

    @IsTest
    static void testBulkUpdateHandledSafely() {
        List<Shipment__c> bulkShipments = [
            SELECT Id, Status__c, Equipment__c
            FROM Shipment__c
            WHERE Equipment__c IN (SELECT Id FROM Equipment__c WHERE Truck_ID__c LIKE 'TRK-BULK-%')
        ];
        System.assertEquals(20, bulkShipments.size(), 'Expected 20 bulk shipments to be set up');

        Test.startTest();
        for (Shipment__c shipment : bulkShipments) {
            shipment.Status__c = 'In Transit';
        }
        update bulkShipments;
        Test.stopTest();

        List<Equipment__c> updatedEquipment = [
            SELECT Operational_Status__c
            FROM Equipment__c
            WHERE Truck_ID__c LIKE 'TRK-BULK-%'
        ];
        for (Equipment__c equipment : updatedEquipment) {
            System.assertEquals('In_Transit', equipment.Operational_Status__c, 'All bulk equipment should transition to In_Transit');
        }
    }

    @IsTest
    static void testServiceHandlesNullAndEmptyInputGracefully() {
        Test.startTest();
        EquipmentAvailabilityService_copado.updateEquipmentAvailability(null);
        EquipmentAvailabilityService_copado.updateEquipmentAvailability(new List<Shipment__c>());
        Test.stopTest();
    }

    @IsTest
    static void testServiceReturnsEarlyWhenNoEquipmentIdsPresent() {
        Shipment__c shipmentWithoutEquipment = new Shipment__c(Status__c = 'In Transit', Equipment__c = null);

        Test.startTest();
        EquipmentAvailabilityService_copado.updateEquipmentAvailability(
            new List<Shipment__c>{ shipmentWithoutEquipment }
        );
        Test.stopTest();
    }

    @IsTest
    static void testServiceSkipsNullEquipmentWithinMixedList() {
        Equipment__c equipment = [SELECT Id FROM Equipment__c WHERE Truck_ID__c = 'TRK-AVAIL-01' LIMIT 1];
        Shipment__c shipmentWithoutEquipment = new Shipment__c(Status__c = 'In Transit', Equipment__c = null);
        Shipment__c shipmentWithEquipment = new Shipment__c(Status__c = 'In Transit', Equipment__c = equipment.Id);

        Test.startTest();
        EquipmentAvailabilityService_copado.updateEquipmentAvailability(
            new List<Shipment__c>{ shipmentWithoutEquipment, shipmentWithEquipment }
        );
        Test.stopTest();

        Equipment__c updatedEquipment = [SELECT Operational_Status__c FROM Equipment__c WHERE Id = :equipment.Id];
        System.assertEquals('In_Transit', updatedEquipment.Operational_Status__c, 'Valid shipment in mixed list should still update its equipment');
    }

    @IsTest
    static void testServiceSkipsShipmentStatusNotInTransitionMap() {
        Equipment__c equipment = [SELECT Id, Operational_Status__c FROM Equipment__c WHERE Truck_ID__c = 'TRK-AVAIL-01' LIMIT 1];
        Shipment__c shipmentWithUnmappedStatus = new Shipment__c(Status__c = 'Scheduled', Equipment__c = equipment.Id);

        Test.startTest();
        EquipmentAvailabilityService_copado.updateEquipmentAvailability(
            new List<Shipment__c>{ shipmentWithUnmappedStatus }
        );
        Test.stopTest();

        Equipment__c unchangedEquipment = [SELECT Operational_Status__c FROM Equipment__c WHERE Id = :equipment.Id];
        System.assertEquals(equipment.Operational_Status__c, unchangedEquipment.Operational_Status__c, 'Unmapped shipment status should not change equipment status');
    }

    @IsTest
    static void testServiceSkipsEquipmentAlreadyAtTargetStatus() {
        Equipment__c equipment = [SELECT Id FROM Equipment__c WHERE Truck_ID__c = 'TRK-AVAIL-01' LIMIT 1];
        Shipment__c shipmentAlreadyAvailable = new Shipment__c(Status__c = 'Delivered', Equipment__c = equipment.Id);

        Test.startTest();
        EquipmentAvailabilityService_copado.updateEquipmentAvailability(
            new List<Shipment__c>{ shipmentAlreadyAvailable }
        );
        Test.stopTest();

        Equipment__c unchangedEquipment = [SELECT Operational_Status__c FROM Equipment__c WHERE Id = :equipment.Id];
        System.assertEquals('Available', unchangedEquipment.Operational_Status__c, 'Equipment already Available should remain unchanged');
    }
}