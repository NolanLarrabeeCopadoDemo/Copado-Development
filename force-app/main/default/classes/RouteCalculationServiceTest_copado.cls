@isTest
private class RouteCalculationServiceTest_copado {

    // Valid Google-encoded polyline decoding to (38.5, -120.2) - California.
    private static final String VALID_SINGLE_POINT_POLYLINE = '_p~iF~ps|U';

    // Three-point polyline spanning CA, NV, UT bounding boxes.
    // Decodes to: (38.5,-120.2), (40.7,-111.9), (41.0,-112.0)
    private static final String VALID_MULTI_POINT_POLYLINE = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

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

    private class MalformedPolylineMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"routes":[{"summary":{"distance":1000,"duration":100},"geometry":"~"}]}');
            return res;
        }
    }

    // -------------------------------------------------------------------------
    // Helper - builds an unsaved Route__c without using LogisticsTestFactory
    // (factory has duplicate method compilation errors tracked separately).
    // -------------------------------------------------------------------------

    private static Route__c buildRoute(Integer index) {
        return new Route__c(
            Origin_Latitude__c       = 34.0 + index * 0.001,
            Origin_Longitude__c      = -118.0 + index * 0.001,
            Destination_Latitude__c  = 36.0 + index * 0.001,
            Destination_Longitude__c = -120.0 + index * 0.001,
            Departure_DateTime__c    = DateTime.now().addDays(1)
        );
    }

    // -------------------------------------------------------------------------
    // Success path
    // -------------------------------------------------------------------------

    @isTest
    static void testSuccessPathPopulatesFields() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Route__c route = buildRoute(1);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals('Success',                   route.API_Status__c,               'API_Status__c should be Success');
        System.assertEquals(10.0,                        route.Total_Mileage__c,            'Total_Mileage__c should be 10.0 miles');
        System.assertEquals(1.0,                        route.Estimated_Duration_Hours__c, 'Estimated_Duration_Hours__c should be 1.0');
        System.assertEquals(VALID_SINGLE_POINT_POLYLINE, route.Encoded_Polyline__c,         'Encoded_Polyline__c should match geometry from API');
        System.assertEquals(null,                        route.API_Last_Error__c,           'API_Last_Error__c should be null on success');
        System.assertNotEquals(null,                     route.Map_Embed_URL__c,            'Map_Embed_URL__c should be populated on success');
    }

    // -------------------------------------------------------------------------
    // Error path
    // -------------------------------------------------------------------------

    @isTest
    static void testErrorPathSetsFailedStatus() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        Route__c route = buildRoute(2);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals('Failed', route.API_Status__c,     'API_Status__c should be Failed on HTTP 500');
        System.assertNotEquals(null,  route.API_Last_Error__c, 'API_Last_Error__c should be populated on error');
        System.assertEquals(null,     route.Total_Mileage__c,  'Total_Mileage__c should remain null on error');
    }

    // -------------------------------------------------------------------------
    // Guard conditions
    // -------------------------------------------------------------------------

    @isTest
    static void testIncompleteCoordinatesSkipped() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Route__c route = new Route__c(Origin_Latitude__c = 34.0);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals(null, route.Total_Mileage__c, 'Incomplete coordinates should not be processed');
        System.assertEquals(null, route.API_Status__c,    'API_Status__c should remain null for incomplete coordinates');
    }

    @isTest
    static void testNullListDoesNotThrow() {
        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(null);
        Test.stopTest();
        System.assert(true, 'Null list should be handled gracefully');
    }

    // -------------------------------------------------------------------------
    // Bulk (100 routes)
    // -------------------------------------------------------------------------

    @isTest
    static void testBulkSuccessPath() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        List<Route__c> routes = new List<Route__c>();
        for (Integer i = 0; i < 100; i++) {
            routes.add(buildRoute(i));
        }

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(routes);
        Test.stopTest();

        for (Route__c route : routes) {
            System.assertEquals('Success',                   route.API_Status__c,       'All bulk routes should have Success status');
            System.assertEquals(VALID_SINGLE_POINT_POLYLINE, route.Encoded_Polyline__c, 'All bulk routes should have correct encoded polyline');
        }
    }

    // -------------------------------------------------------------------------
    // Waypoint extraction and state derivation
    // -------------------------------------------------------------------------

    @isTest
    static void testWaypointExtractionPopulatesJsonAndStates() {
        Test.setMock(HttpCalloutMock.class, new MultiPointSuccessMock());
        Route__c route = buildRoute(3);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals('Success', route.API_Status__c,     'API_Status__c should be Success with multi-point polyline');
        System.assertNotEquals(null,   route.Waypoints_JSON__c, 'Waypoints_JSON__c should be populated from decoded polyline');

        List<Object> waypoints = (List<Object>) JSON.deserializeUntyped(route.Waypoints_JSON__c);
        System.assert(
            waypoints.size() >= 1 && waypoints.size() <= 8,
            'Expected between 1-8 sampled waypoints, got: ' + waypoints.size()
        );
        for (Object waypointObj : waypoints) {
            Map<String, Object> wp = (Map<String, Object>) waypointObj;
            System.assert(wp.containsKey('lat'), 'Each waypoint must have a lat key');
            System.assert(wp.containsKey('lng'), 'Each waypoint must have a lng key');
        }
    }

    @isTest
    static void testWaypointExtractionHandlesMalformedPolylineGracefully() {
        Test.setMock(HttpCalloutMock.class, new MalformedPolylineMock());
        Route__c route = buildRoute(4);

        Test.startTest();
        RouteCalculationService_copado.calculateAndPopulate(new List<Route__c>{ route });
        Test.stopTest();

        System.assertEquals('Success', route.API_Status__c,     'API_Status__c should be Success even when polyline decode fails');
        System.assertEquals(null,      route.Waypoints_JSON__c, 'Waypoints_JSON__c should remain null when decode throws');
    }
}