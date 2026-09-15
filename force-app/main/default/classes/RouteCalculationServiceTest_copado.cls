@isTest
private class RouteCalculationServiceTest_copado {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"routes":[{"summary":{"distance":16093.44,"duration":3600},"geometry":"abc123encodedPolyline"}]}');
            return response;
        }
    }

    private class MultiPointSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(
                '{"routes":[{"summary":{"distance":16093.44,"duration":3600},'
                + '"geometry":"okynEnuvpUoh\\\\oxtI_ry@_brJ~hbE_yzN~oR_pR~bmA_awS~ugC_q~I~qy@_vgC"}]}'
            );
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

    private class MalformedPolylineMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"routes":[{"summary":{"distance":1000,"duration":100},"geometry":"~"}]}');
            return response;
        }
    }

    private static Route__c buildRoute(Integer index) {
        return new Route__c(
            Origin_Latitude__c = 34.0 + index * 0.001,
            Origin_Longitude__c = -118.0 + index * 0.001,
            Destination_Latitude__c = 36.0 + index * 0.001,
            Destination_Longitude__c = -120.0 + index * 0.001,
            Departure_DateTime__c = DateTime.now().addDays(1)
        );
    }

    @isTest
    static void testSuccessPathPopulatesFields() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Route__c route = buildRoute(1);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals('Success', route.API_Status__c);
        System.assertEquals(10.0, route.Total_Mileage__c);
        System.assertEquals(1.0, route.Estimated_Duration_Hours__c);
        System.assertEquals('abc123encodedPolyline', route.Encoded_Polyline__c);
        System.assertEquals(null, route.API_Last_Error__c);
        System.assertNotEquals(null, route.Map_Embed_URL__c);
    }

    @isTest
    static void testErrorPathSetsFailedStatus() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        Route__c route = buildRoute(2);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals('Failed', route.API_Status__c);
        System.assertNotEquals(null, route.API_Last_Error__c);
        System.assertEquals(null, route.Total_Mileage__c);
    }

    @isTest
    static void testIncompleteCoordinatesSkipped() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Route__c route = new Route__c(Origin_Latitude__c = 34.0);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals(null, route.Total_Mileage__c);
        System.assertEquals(null, route.API_Status__c);
    }

    @isTest
    static void testNullListDoesNotThrow() {
        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(null);
        Test.stopTest();
        System.assert(true, 'Null list should be handled gracefully.');
    }

    @isTest
    static void testBulkSuccessPath() {
        // A single transaction allows a maximum of 100 callouts, and this
        // service issues one callout per route, so this test exercises the
        // service directly at that ceiling. The 200+ record bulk scenario
        // (spanning multiple chained Queueable batches) is covered by
        // RouteCalculationQueueableTest_copado.
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        List<Route__c> routes = new List<Route__c>();
        for (Integer i = 0; i < 100; i++) {
            routes.add(buildRoute(i));
        }

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(routes);
        Test.stopTest();

        for (Route__c route : routes) {
            System.assertEquals('Success', route.API_Status__c);
            System.assertEquals('abc123encodedPolyline', route.Encoded_Polyline__c);
        }
    }

    @isTest
    static void testWaypointExtractionPopulatesJsonAndStates() {
        Test.setMock(HttpCalloutMock.class, new MultiPointSuccessMock());
        Route__c route = buildRoute(3);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals('Success', route.API_Status__c);
        System.assertNotEquals(null, route.Waypoints_JSON__c);

        List<Object> waypoints = (List<Object>) JSON.deserializeUntyped(route.Waypoints_JSON__c);
        System.assert(waypoints.size() >= 6 && waypoints.size() <= 8, 'Expected 6-8 waypoints, got ' + waypoints.size());
        for (Object waypointObj : waypoints) {
            Map<String, Object> waypoint = (Map<String, Object>) waypointObj;
            System.assert(waypoint.containsKey('lat'));
            System.assert(waypoint.containsKey('lng'));
        }
    }

    @isTest
    static void testWaypointExtractionHandlesMalformedPolylineGracefully() {
        // A single trailing continuation-bit byte with no follow-up byte is
        // malformed input for the decoder; extraction should be logged and
        // swallowed rather than failing the whole route calculation, since
        // distance/duration/status have already been set successfully.
        Test.setMock(HttpCalloutMock.class, new MalformedPolylineMock());
        Route__c route = buildRoute(4);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals('Success', route.API_Status__c);
        System.assertEquals(null, route.Waypoints_JSON__c);
    }
}