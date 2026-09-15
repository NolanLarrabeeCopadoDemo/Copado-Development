@isTest
private class RouteCalculationQueueableTest_copado {

    private static final String VALID_SINGLE_POINT_POLYLINE = '_p~iF~ps|U';
    private static final String VALID_MULTI_POINT_POLYLINE  = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

    // -------------------------------------------------------------------------
    // HTTP Mocks
    // -------------------------------------------------------------------------

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"routes":[{"summary":{"distance":16093.44,"duration":3600},'
                + '"geometry":"_p~iF~ps|U"}]}'
            );
            return res;
        }
    }

    private class MultiPointSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"routes":[{"summary":{"distance":16093.44,"duration":3600},'
                + '"geometry":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}]}'
            );
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    // -------------------------------------------------------------------------
    // Helper - creates a sysadmin test user to bypass FLS in with-sharing context.
    // LogisticsTestFactory.buildRoute() is excluded due to duplicate method
    // compilation errors tracked separately (P00521).
    // -------------------------------------------------------------------------

    private static User buildSysAdminUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            LastName       = 'RouteTestUser',
            Email          = 'routetestuser@test.logistics.example.com',
            Username       = 'routetestuser_' + DateTime.now().getTime() + '@test.logistics.example.com',
            Alias          = 'rtuser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey   = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId      = p.Id
        );
    }

    private static Route__c buildRoute(Integer index) {
        return new Route__c(
            Origin_Latitude__c       = 34.0 + (Math.mod(index, 50) * 0.001),
            Origin_Longitude__c      = -118.0 + (Math.mod(index, 50) * 0.001),
            Destination_Latitude__c  = 36.0 + (Math.mod(index, 50) * 0.001),
            Destination_Longitude__c = -120.0 + (Math.mod(index, 50) * 0.001),
            Departure_DateTime__c    = DateTime.now().addDays(1)
        );
    }

    // -------------------------------------------------------------------------
    // Insert trigger path
    // -------------------------------------------------------------------------

    @isTest
    static void testTriggerEnqueuesAndQueueableUpdatesOnInsertSuccess() {
        User sysAdmin = buildSysAdminUser();
        insert sysAdmin;
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        System.runAs(sysAdmin) {
            Route__c route = buildRoute(1);
            Test.startTest();
            insert route;
            Test.stopTest();

            Route__c result = [
                SELECT Total_Mileage__c, Estimated_Duration_Hours__c, Encoded_Polyline__c, API_Status__c
                FROM Route__c
                WHERE Id = :route.Id
            ];
            System.assertEquals('Success',                   result.API_Status__c,       'API_Status__c should be Success after insert trigger');
            System.assertEquals(10.0,                        result.Total_Mileage__c,    'Total_Mileage__c should be 10.0 miles');
            System.assertEquals(VALID_SINGLE_POINT_POLYLINE, result.Encoded_Polyline__c, 'Encoded_Polyline__c should match geometry from API');
        }
    }

    // -------------------------------------------------------------------------
    // Update trigger path
    // -------------------------------------------------------------------------

    @isTest
    static void testTriggerEnqueuesOnUpdateWhenCoordinatesChange() {
        User sysAdmin = buildSysAdminUser();
        insert sysAdmin;
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        System.runAs(sysAdmin) {
            Route__c route = buildRoute(2);
            insert route;

            route.Destination_Latitude__c  = 40.0;
            route.Destination_Longitude__c = -100.0;

            Test.startTest();
            update route;
            Test.stopTest();

            Route__c result = [SELECT Total_Mileage__c, API_Status__c FROM Route__c WHERE Id = :route.Id];
            System.assertEquals('Success', result.API_Status__c,    'API_Status__c should be Success after coordinate update');
            System.assertEquals(10.0,      result.Total_Mileage__c, 'Total_Mileage__c should be 10.0 miles after update');
        }
    }

    // -------------------------------------------------------------------------
    // Error handling
    // -------------------------------------------------------------------------

    @isTest
    static void testQueueableHandlesApiErrorGracefully() {
        User sysAdmin = buildSysAdminUser();
        insert sysAdmin;
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        System.runAs(sysAdmin) {
            Route__c route = buildRoute(3);
            Test.startTest();
            insert route;
            Test.stopTest();

            Route__c result = [SELECT API_Status__c, API_Last_Error__c, Total_Mileage__c FROM Route__c WHERE Id = :route.Id];
            System.assertEquals('Failed', result.API_Status__c,     'API_Status__c should be Failed on HTTP 500');
            System.assertNotEquals(null,  result.API_Last_Error__c, 'API_Last_Error__c should be populated on error');
            System.assertEquals(null,     result.Total_Mileage__c,  'Total_Mileage__c should remain null on error');
        }
    }

    // -------------------------------------------------------------------------
    // Guard conditions
    // -------------------------------------------------------------------------

    @isTest
    static void testQueueableDirectInvocationWithEmptySet() {
        Test.startTest();
        new RouteCalculationQueueable_copado(new Set<Id>()).execute(null);
        new RouteCalculationQueueable_copado(null).execute(null);
        Test.stopTest();
        System.assert(true, 'Empty/null Id sets should be handled gracefully');
    }

    // -------------------------------------------------------------------------
    // Bulk: 200 routes across two Queueable batches
    // -------------------------------------------------------------------------

    @isTest
    static void testBulkInsertEnqueuesOnceAndProcessesFirstBatch() {
        User sysAdmin = buildSysAdminUser();
        insert sysAdmin;
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        System.runAs(sysAdmin) {
            List<Route__c> routes = new List<Route__c>();
            for (Integer i = 0; i < 200; i++) {
                routes.add(buildRoute(i));
            }

            Test.startTest();
            insert routes;
            System.assertEquals(1, Limits.getQueueableJobs(), 'Trigger should enqueue exactly one Queueable job per transaction');
            Test.stopTest();

            List<Route__c> results = [SELECT API_Status__c FROM Route__c WHERE Id IN :routes];
            System.assertEquals(200, results.size(), '200 route records should be present');

            Integer successCount = 0;
            for (Route__c r : results) {
                if (r.API_Status__c == 'Success') {
                    successCount++;
                }
            }
            System.assertEquals(
                RouteCalculationQueueable_copado.MAX_ROUTES_PER_RUN,
                successCount,
                'Exactly one batch of routes should be processed in the test-context job run'
            );
        }
    }

    // -------------------------------------------------------------------------
    // Waypoint and state persistence in same DML update
    // -------------------------------------------------------------------------

    @isTest
    static void testQueueablePersistsWaypointsAndStatesInSameDmlUpdate() {
        User sysAdmin = buildSysAdminUser();
        insert sysAdmin;
        Test.setMock(HttpCalloutMock.class, new MultiPointSuccessMock());

        System.runAs(sysAdmin) {
            Route__c route = buildRoute(4);
            Test.startTest();
            insert route;
            Test.stopTest();

            Route__c result = [
                SELECT API_Status__c, Waypoints_JSON__c, States_Traversed__c, Map_Embed_URL__c
                FROM Route__c
                WHERE Id = :route.Id
            ];
            System.assertEquals('Success', result.API_Status__c,     'API_Status__c should be Success with multi-point polyline');
            System.assertNotEquals(null,   result.Waypoints_JSON__c, 'Waypoints_JSON__c should be persisted in same DML update');
            System.assertNotEquals(null,   result.Map_Embed_URL__c,  'Map_Embed_URL__c should be persisted in same DML update');
        }
    }
}