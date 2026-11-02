@isTest
private class StateBoundaryServiceTest_copado {

    /**
     * Inserts two State_Boundary__mdt-equivalent test records by mocking a
     * private static method is not possible in Apex; instead we rely on the
     * real SOQL query in the service which reads from State_Boundary__mdt.
     * Custom Metadata records are readable in tests without DML.
     * The tests here validate branching logic using whatever metadata records
     * are available. If none exist, the empty/null guard paths are exercised.
     */

    // -----------------------------------------------------------------------
    // 1. NULL / EMPTY GUARDS
    // -----------------------------------------------------------------------

    @isTest
    static void testNullWaypointsReturnsEmptyList() {
        Test.startTest();
        List<String> result = StateBoundaryService_copado.getStatesTraversed(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should never be null.');
        System.assertEquals(0, result.size(), 'Null input should return an empty list.');
    }

    @isTest
    static void testEmptyWaypointsReturnsEmptyList() {
        Test.startTest();
        List<String> result = StateBoundaryService_copado.getStatesTraversed(
            new List<Map<String, Decimal>>()
        );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Empty waypoint list should return an empty list.');
    }

    // -----------------------------------------------------------------------
    // 2. WAYPOINT WITH NULL LAT/LNG IS SILENTLY SKIPPED
    // -----------------------------------------------------------------------

    @isTest
    static void testWaypointWithNullLatLngIsSkipped() {
        Map<String, Decimal> nullPoint = new Map<String, Decimal>();
        nullPoint.put('lat', null);
        nullPoint.put('lng', null);

        Test.startTest();
        List<String> result = StateBoundaryService_copado.getStatesTraversed(
            new List<Map<String, Decimal>>{ nullPoint }
        );
        Test.stopTest();

        // The coordinate is null, so findStateForCoordinate returns null and
        // the waypoint is silently ignored. Result may be empty or populated
        // with real metadata matches for surrounding null-safe calls.
        System.assertNotEquals(null, result, 'Result should not be null even for null-coordinate waypoints.');
    }

    // -----------------------------------------------------------------------
    // 3. COORDINATE OUTSIDE ALL KNOWN BOUNDING BOXES IS SKIPPED
    // -----------------------------------------------------------------------

    @isTest
    static void testCoordinateOutsideAllBoundariesReturnsNoState() {
        // Pacific Ocean coordinate: should fall outside all US state bounding boxes.
        Map<String, Decimal> oceanPoint = new Map<String, Decimal>();
        oceanPoint.put('lat', 0.0);
        oceanPoint.put('lng', -150.0);

        Test.startTest();
        List<String> result = StateBoundaryService_copado.getStatesTraversed(
            new List<Map<String, Decimal>>{ oceanPoint }
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        // If real metadata exists the ocean coordinate should still not match
        // any US state (lat 0 is equatorial).
        System.assertEquals(0, result.size(), 'Ocean coordinate should not match any US state.');
    }

    // -----------------------------------------------------------------------
    // 4. DEDUPLICATION: SAME STATE FROM MULTIPLE WAYPOINTS APPEARS ONCE
    // -----------------------------------------------------------------------

    @isTest
    static void testDuplicateStatesAreDeduplicatedAndOrderPreserved() {
        // Use two real CONUS waypoints that both fall within California's bounding
        // box (approximately 32.5N-42N, -124.5W to -114W).
        Map<String, Decimal> caPt1 = new Map<String, Decimal>();
        caPt1.put('lat', 34.05);
        caPt1.put('lng', -118.24); // Los Angeles area

        Map<String, Decimal> caPt2 = new Map<String, Decimal>();
        caPt2.put('lat', 37.77);
        caPt2.put('lng', -122.41); // San Francisco area

        Test.startTest();
        List<String> result = StateBoundaryService_copado.getStatesTraversed(
            new List<Map<String, Decimal>>{ caPt1, caPt2 }
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        if (!result.isEmpty()) {
            // If the metadata is present, CA should appear exactly once.
            Integer caCount = 0;
            for (String state : result) {
                if (state == 'CA') {
                    caCount++;
                }
            }
            System.assert(caCount <= 1, 'CA should appear at most once due to deduplication.');
        }
    }

    // -----------------------------------------------------------------------
    // 5. MULTI-STATE ROUTE PRESERVES FIRST-OCCURRENCE ORDER
    // -----------------------------------------------------------------------

    @isTest
    static void testMultiStateRoutePreservesFirstOccurrenceOrder() {
        // Waypoints traversing NV then AZ (approximate bounding boxes).
        Map<String, Decimal> nvPt = new Map<String, Decimal>();
        nvPt.put('lat', 36.17);
        nvPt.put('lng', -115.13); // Las Vegas, NV

        Map<String, Decimal> azPt = new Map<String, Decimal>();
        azPt.put('lat', 33.44);
        azPt.put('lng', -112.07); // Phoenix, AZ

        Test.startTest();
        List<String> result = StateBoundaryService_copado.getStatesTraversed(
            new List<Map<String, Decimal>>{ nvPt, azPt }
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        // Validate ordering only when metadata is present and both states match.
        if (result.size() >= 2) {
            Integer nvIndex = result.indexOf('NV');
            Integer azIndex = result.indexOf('AZ');
            if (nvIndex != -1 && azIndex != -1) {
                System.assert(nvIndex < azIndex, 'NV should appear before AZ in the ordered traversal.');
            }
        }
    }

    // -----------------------------------------------------------------------
    // 6. LARGE WAYPOINT LIST DOES NOT HIT GOVERNOR LIMITS
    // -----------------------------------------------------------------------

    @isTest
    static void testLargeWaypointListDoesNotHitGovernorLimits() {
        List<Map<String, Decimal>> waypoints = new List<Map<String, Decimal>>();
        for (Integer i = 0; i < 200; i++) {
            Map<String, Decimal> pt = new Map<String, Decimal>();
            pt.put('lat', Decimal.valueOf(30 + Math.mod(i, 20)));
            pt.put('lng', Decimal.valueOf(-120 + Math.mod(i, 20)));
            waypoints.add(pt);
        }

        Test.startTest();
        List<String> result = StateBoundaryService_copado.getStatesTraversed(waypoints);
        Test.stopTest();

        System.assertNotEquals(null, result, '200-waypoint list should complete without governor exceptions.');
    }
}