@isTest
private class RouteCalculationQueueableTest_copado {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"routes":[{"summary":{"distance":16093.44,"duration":3600},"geometry":"abc123encodedPolyline"}]}');
            return response;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setBody('{"error":"Internal Server Error"}');
            return response;
        }
    }

    private static Route__c buildRoute(Integer index) {
        return new Route__c(
            Origin_Latitude__c = 34.0 + (Math.mod(index, 50) * 0.001),
            Origin_Longitude__c = -118.0 + (Math.mod(index, 50) * 0.001),
            Destination_Latitude__c = 36.0 + (Math.mod(index, 50) * 0.001),
            Destination_Longitude__c = -120.0 + (Math.mod(index, 50) * 0.001),
            Departure_DateTime__c = DateTime.now().addDays(1)
        );
    }

    @isTest
    static void testTriggerEnqueuesAndQueueableUpdatesOnInsertSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Route__c route = buildRoute(1);

        Test.startTest();
        insert route;
        Test.stopTest();

        Route__c result = [SELECT Total_Mileage__c, Estimated_Duration_Hours__c, Encoded_Polyline__c, API_Status__c
                            FROM Route__c WHERE Id = :route.Id];
        System.assertEquals('Success', result.API_Status__c);
        System.assertEquals(10.0, result.Total_Mileage__c);
        System.assertEquals('abc123encodedPolyline', result.Encoded_Polyline__c);
    }

    @isTest
    static void testTriggerEnqueuesOnUpdateWhenCoordinatesChange() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Route__c route = buildRoute(2);
        insert route;

        route.Destination_Latitude__c = 40.0;
        route.Destination_Longitude__c = -100.0;

        Test.startTest();
        update route;
        Test.stopTest();

        Route__c result = [SELECT Total_Mileage__c, API_Status__c FROM Route__c WHERE Id = :route.Id];
        System.assertEquals('Success', result.API_Status__c);
        System.assertEquals(10.0, result.Total_Mileage__c);
    }

    @isTest
    static void testQueueableHandlesApiErrorGracefully() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        Route__c route = buildRoute(3);

        Test.startTest();
        insert route;
        Test.stopTest();

        Route__c result = [SELECT API_Status__c, API_Last_Error__c, Total_Mileage__c FROM Route__c WHERE Id = :route.Id];
        System.assertEquals('Failed', result.API_Status__c);
        System.assertNotEquals(null, result.API_Last_Error__c);
        System.assertEquals(null, result.Total_Mileage__c);
    }

    @isTest
    static void testQueueableDirectInvocationWithEmptySet() {
        Test.startTest();
        new RouteCalculationQueueable_copado(new Set<Id>()).execute(null);
        new RouteCalculationQueueable_copado(null).execute(null);
        Test.stopTest();
        System.assert(true, 'Empty/null Id sets should be handled gracefully.');
    }

    @isTest
    static void testBulkInsertOfTwoHundredRoutesEnqueuesOnceAndProcessesFirstBatch() {
        // Apex test contexts do not support chained Queueable jobs beyond one
        // level (System.AsyncException: Maximum stack depth has been reached),
        // so this test verifies the trigger enqueues exactly once per
        // transaction and the first MAX_ROUTES_PER_RUN records are processed.
        // The chaining of remaining records into a follow-up job is exercised
        // in production via System.enqueueJob and is skipped only in tests.
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        List<Route__c> routes = new List<Route__c>();
        for (Integer i = 0; i < 200; i++) {
            routes.add(buildRoute(i));
        }

        Test.startTest();
        insert routes;
        System.assertEquals(1, Limits.getQueueableJobs(), 'Trigger should enqueue exactly one Queueable job per transaction.');
        Test.stopTest();

        List<Route__c> results = [SELECT API_Status__c, Total_Mileage__c FROM Route__c WHERE Id IN :routes];
        System.assertEquals(200, results.size());

        Integer successCount = 0;
        for (Route__c result : results) {
            if (result.API_Status__c == 'Success') {
                successCount++;
            }
        }
        System.assertEquals(
            RouteCalculationQueueable_copado.MAX_ROUTES_PER_RUN,
            successCount,
            'Exactly one batch worth of routes should be processed within the test-context job run.'
        );
    }
}