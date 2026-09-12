/**
 * Test coverage for CompletedShipmentService and the shipment-status-copado trigger
 * (US-0000482). Targets 90% coverage of CompletedShipmentService.
 */
@isTest
private class CompletedShipmentServiceTest {

    @isTest
    static void testStatusChangeToDeliveredCreatesCompletedShipment() {
        Route__c route = LogisticsTestFactory.createRoute(500);
        Shipment__c shipment = LogisticsTestFactory.createShipment(route.Id);

        Test.startTest();
        shipment.Status__c = 'Delivered';
        update shipment;
        Test.stopTest();

        List<Completed_Shipment__c> completedShipments = [
            SELECT Id, Shipment__c, Actual_Mileage__c
            FROM Completed_Shipment__c
            WHERE Shipment__c = :shipment.Id
        ];
        System.assertEquals(1, completedShipments.size(), 'Expected exactly one Completed_Shipment__c to be created.');
        System.assertEquals(500, completedShipments[0].Actual_Mileage__c, 'Mileage should be seeded from the Route.');
    }

    @isTest
    static void testOtherStatusTransitionsDoNotCreateCompletedShipment() {
        Route__c route = LogisticsTestFactory.createRoute(500);
        Shipment__c shipment = LogisticsTestFactory.createShipment(route.Id);

        Test.startTest();
        shipment.Status__c = 'Scheduled';
        update shipment;
        Test.stopTest();

        List<Completed_Shipment__c> completedShipments = [
            SELECT Id
            FROM Completed_Shipment__c
            WHERE Shipment__c = :shipment.Id
        ];
        System.assertEquals(0, completedShipments.size(), 'No Completed_Shipment__c should be created for non-Delivered transitions.');
    }

    @isTest
    static void testDuplicatePreventionOnResave() {
        Route__c route = LogisticsTestFactory.createRoute(500);
        Shipment__c shipment = LogisticsTestFactory.createShipment(route.Id);

        Test.startTest();
        shipment.Status__c = 'Delivered';
        update shipment;

        shipment.Status__c = 'Scheduled';
        update shipment;
        shipment.Status__c = 'Delivered';
        update shipment;
        Test.stopTest();

        List<Completed_Shipment__c> completedShipments = [
            SELECT Id
            FROM Completed_Shipment__c
            WHERE Shipment__c = :shipment.Id
        ];
        System.assertEquals(1, completedShipments.size(), 'Re-saving to Delivered must not create a duplicate Completed_Shipment__c.');
    }

    @isTest
    static void testBulkDeliveryCreatesCompletedShipmentsForAll() {
        Route__c route = LogisticsTestFactory.createRoute(750);
        List<Shipment__c> shipments = LogisticsTestFactory.createShipments(200, route.Id);

        Test.startTest();
        for (Shipment__c shipment : shipments) {
            shipment.Status__c = 'Delivered';
        }
        update shipments;
        Test.stopTest();

        List<Completed_Shipment__c> completedShipments = [
            SELECT Id, Shipment__c
            FROM Completed_Shipment__c
            WHERE Shipment__c IN :shipments
        ];
        System.assertEquals(shipments.size(), completedShipments.size(), 'Every delivered shipment in the batch should produce one Completed_Shipment__c.');
    }

    @isTest
    static void testRouteMileageSeedingWhenNoRoute() {
        Shipment__c shipment = new Shipment__c(
            Status__c = 'Draft',
            Freight_Rate_Per_Mile__c = 2.5
        );
        insert shipment;

        Test.startTest();
        shipment.Status__c = 'Delivered';
        update shipment;
        Test.stopTest();

        List<Completed_Shipment__c> completedShipments = [
            SELECT Id, Actual_Mileage__c
            FROM Completed_Shipment__c
            WHERE Shipment__c = :shipment.Id
        ];
        System.assertEquals(1, completedShipments.size(), 'Completed_Shipment__c should still be created when there is no Route.');
        System.assert(completedShipments[0].Actual_Mileage__c > 0, 'A positive fallback mileage should be seeded when the Shipment has no Route (VR_Actual_Mileage_Positive requires > 0).');
    }

    @isTest
    static void testLoggerUtilityMethods() {
        Test.startTest();
        Logger.info('CompletedShipmentServiceTest', 'Sample info message.');
        Logger.info('CompletedShipmentServiceTest', null);
        Logger.error('CompletedShipmentServiceTest', 'Sample error message.');
        Logger.error('CompletedShipmentServiceTest', new DmlException('Sample DML failure.'));
        Logger.error(null, (String) null);
        Test.stopTest();
    }
}