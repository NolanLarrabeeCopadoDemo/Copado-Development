/**
 * @description Test coverage for CompletedShipmentService and ShipmentStatusTrigger
 *              (US-0000482). Targets 90%+ coverage of CompletedShipmentService
 *              across the following scenarios:
 *                - Status change to Delivered creates one Completed_Shipment__c.
 *                - Other status transitions do not create a record.
 *                - Duplicate prevention: re-saving to Delivered does not add a second record.
 *                - Bulk delivery: 200 shipments produce 200 completed records.
 *                - No-route fallback: positive mileage fallback satisfies VR.
 *                - Logger utility paths exercised without compile errors.
 *
 * @author      Nolan Larrabee
 * @date        2026-09-13
 */
@isTest
private class CompletedShipmentServiceTest {

    /**
     * @description Verifies that transitioning a Shipment to Delivered creates
     *              exactly one Completed_Shipment__c with mileage seeded from
     *              the parent Route.
     */
    @isTest
    static void testStatusChangeToDeliveredCreatesCompletedShipment() {
        Route__c route      = LogisticsTestFactory.createRoute(500);
        Shipment__c shipment = LogisticsTestFactory.createShipment(route.Id);

        Test.startTest();
        shipment.Status__c = 'Delivered';
        update shipment;
        Test.stopTest();

        List<Completed_Shipment__c> results = [
            SELECT Id, Shipment__c, Actual_Mileage__c
            FROM Completed_Shipment__c
            WHERE Shipment__c = :shipment.Id
        ];
        System.assertEquals(1, results.size(), 'Expected exactly one Completed_Shipment__c to be created.');
        System.assertEquals(500, results[0].Actual_Mileage__c, 'Mileage should be seeded from the Route.');
    }

    /**
     * @description Verifies that transitioning a Shipment to a status other
     *              than Delivered does not create a Completed_Shipment__c.
     */
    @isTest
    static void testOtherStatusTransitionsDoNotCreateCompletedShipment() {
        Route__c route      = LogisticsTestFactory.createRoute(500);
        Shipment__c shipment = LogisticsTestFactory.createShipment(route.Id);

        Test.startTest();
        shipment.Status__c = 'Scheduled';
        update shipment;
        Test.stopTest();

        List<Completed_Shipment__c> results = [
            SELECT Id
            FROM Completed_Shipment__c
            WHERE Shipment__c = :shipment.Id
        ];
        System.assertEquals(0, results.size(), 'No Completed_Shipment__c should be created for non-Delivered transitions.');
    }

    /**
     * @description Verifies the duplicate guard: re-saving a Shipment to
     *              Delivered after it was already delivered must not create
     *              a second Completed_Shipment__c.
     */
    @isTest
    static void testDuplicatePreventionOnResave() {
        Route__c route      = LogisticsTestFactory.createRoute(500);
        Shipment__c shipment = LogisticsTestFactory.createShipment(route.Id);

        Test.startTest();
        shipment.Status__c = 'Delivered';
        update shipment;

        shipment.Status__c = 'Scheduled';
        update shipment;
        shipment.Status__c = 'Delivered';
        update shipment;
        Test.stopTest();

        List<Completed_Shipment__c> results = [
            SELECT Id
            FROM Completed_Shipment__c
            WHERE Shipment__c = :shipment.Id
        ];
        System.assertEquals(1, results.size(), 'Re-saving to Delivered must not create a duplicate Completed_Shipment__c.');
    }

    /**
     * @description Verifies bulk processing: 200 shipments delivered in a single
     *              DML statement each produce exactly one Completed_Shipment__c.
     */
    @isTest
    static void testBulkDeliveryCreatesCompletedShipmentsForAll() {
        Route__c route               = LogisticsTestFactory.createRoute(750);
        List<Shipment__c> shipments  = LogisticsTestFactory.createShipments(200, route.Id);

        Test.startTest();
        for (Shipment__c s : shipments) {
            s.Status__c = 'Delivered';
        }
        update shipments;
        Test.stopTest();

        List<Completed_Shipment__c> results = [
            SELECT Id, Shipment__c
            FROM Completed_Shipment__c
            WHERE Shipment__c IN :shipments
        ];
        System.assertEquals(shipments.size(), results.size(), 'Every delivered shipment in the batch should produce one Completed_Shipment__c.');
    }

    /**
     * @description Verifies that when a Shipment has no Route, the service
     *              still creates a Completed_Shipment__c using the positive
     *              fallback mileage value to satisfy VR_Actual_Mileage_Positive.
     */
    @isTest
    static void testRouteMileageSeedingWhenNoRoute() {
        Shipment__c shipment = new Shipment__c(
            Status__c              = 'Draft',
            Freight_Rate_Per_Mile__c = 2.5
        );
        insert shipment;

        Test.startTest();
        shipment.Status__c = 'Delivered';
        update shipment;
        Test.stopTest();

        List<Completed_Shipment__c> results = [
            SELECT Id, Actual_Mileage__c
            FROM Completed_Shipment__c
            WHERE Shipment__c = :shipment.Id
        ];
        System.assertEquals(1, results.size(), 'Completed_Shipment__c should still be created when there is no Route.');
        System.assert(results[0].Actual_Mileage__c > 0, 'A positive fallback mileage must be seeded when the Shipment has no Route.');
    }

    /**
     * @description Exercises all Logger overloads to ensure the utility
     *              compiles and executes without errors. Verifies the call
     *              completes without throwing an unhandled exception.
     */
    @isTest
    static void testLoggerUtilityMethods() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            Logger.info('CompletedShipmentServiceTest', 'Sample info message.');
            Logger.info('CompletedShipmentServiceTest', null);
            Logger.error('CompletedShipmentServiceTest', 'Sample error message.');
            Logger.error('CompletedShipmentServiceTest', new DmlException('Sample DML failure.'));
            Logger.error(null, (String) null);
        } catch (Exception ex) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assertEquals(false, exceptionThrown, 'Logger utility methods should not throw any unhandled exceptions.');
    }
}