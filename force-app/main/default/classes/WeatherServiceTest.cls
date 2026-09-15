/**
 * @description Unit tests for WeatherService (US-0000488 / US-0000489). Uses LogisticsTestFactory
 *              for Route__c test data and HttpCalloutMock to simulate Open-Meteo responses,
 *              covering the happy path, callout failure handling, and aggregation helpers.
 *
 *              testStartProcessingHappyPathEnqueuesJob uses System.runAs() with a user who
 *              holds the US_0000488_Access permission set so the FLS guard inside
 *              WeatherService.startProcessing (line 115) evaluates to true and does not throw.
 *
 * @author      Nolan Larrabee
 * @date        2026-09-15
 */
@IsTest
private class WeatherServiceTest {

    // =========================================================================
    // Inner mock
    // =========================================================================

    /**
     * @description Simple HttpCalloutMock returning a fixed status code and body for every
     *              request, regardless of endpoint, so each waypoint callout in a test can be
     *              deterministically satisfied.
     */
    private class OpenMeteoMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String  body;

        OpenMeteoMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body       = body;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            response.setHeader('Content-Type', 'application/json');
            return response;
        }
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * @description Builds a minimal, well-formed Open-Meteo hourly forecast JSON body whose
     *              single hour matches targetHour and carries weatherCode.
     *
     * @param  targetHour  Hour string matching the departure, e.g. '2026-09-16T10:00'.
     * @param  weatherCode WMO weather code to place at that hour.
     * @return             Serialized JSON response body.
     */
    private static String buildMockBody(String targetHour, Integer weatherCode) {
        Map<String, Object> hourly = new Map<String, Object>{
            'time'        => new List<String>{ targetHour },
            'weathercode' => new List<Integer>{ weatherCode }
        };
        Map<String, Object> body = new Map<String, Object>{ 'hourly' => hourly };
        return JSON.serialize(body);
    }

    /**
     * @description Returns a departure DateTime 2 hours from now, always in the future,
     *              satisfying the Route__c VR_Departure_In_Future validation rule.
     *
     * @return Future DateTime safe for test inserts.
     */
    private static DateTime futureDeparture() {
        return DateTime.now().addHours(2);
    }

    /**
     * @description Returns a formatted hour string matching futureDeparture() for use in
     *              mock body construction, e.g. '2026-09-16T12:00'.
     *
     * @return Hour string in 'yyyy-MM-dd\'T\'HH:00' format.
     */
    private static String futureDepartureHour() {
        return DateTime.now().addHours(2).formatGmt('yyyy-MM-dd\'T\'HH:00');
    }

    /**
     * @description Creates a Standard User, inserts a PermissionSetAssignment for
     *              US_0000488_Access, and returns the user ready for System.runAs().
     *              This ensures that the FLS guard inside WeatherService.startProcessing
     *              evaluates Route__c and Waypoints_JSON__c as accessible.
     *
     * @return User with US_0000488_Access assigned.
     */
    private static User createPermissionedUser() {
        Profile stdProfile = [
            SELECT Id
            FROM   Profile
            WHERE  Name = 'Standard User'
            LIMIT  1
        ];

        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User testUser = new User(
            FirstName         = 'Weather',
            LastName          = 'Tester',
            Email             = 'weather.tester.' + uniqueSuffix + '@example.com.invalid',
            Username          = 'weather.tester.' + uniqueSuffix + '@test.example.com.invalid',
            Alias             = 'wtest',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = stdProfile.Id
        );
        insert testUser;

        PermissionSet ps = [
            SELECT Id
            FROM   PermissionSet
            WHERE  Name = 'US_0000488_Access'
            LIMIT  1
        ];
        insert new PermissionSetAssignment(
            AssigneeId      = testUser.Id,
            PermissionSetId = ps.Id
        );

        return testUser;
    }

    // =========================================================================
    // Test setup
    // =========================================================================

    @TestSetup
    static void setup() {
        Route__c route = LogisticsTestFactory.buildRoute(new Map<String, Object>{
            'Departure_DateTime__c' => futureDeparture(),
            'Waypoints_JSON__c'     => '[{"latitude":34.05,"longitude":-118.24},{"latitude":36.16,"longitude":-115.15}]'
        });
        insert route;
    }

    // =========================================================================
    // deserializeWaypoints
    // =========================================================================

    @IsTest
    static void testDeserializeWaypointsHappyPath() {
        List<WeatherService.Waypoint> waypoints = WeatherService.deserializeWaypoints(
            '[{"latitude":34.05,"longitude":-118.24}]'
        );
        System.assertEquals(1, waypoints.size(), 'Expected exactly one waypoint parsed.');
        System.assertEquals(34.05, waypoints[0].latitude, 'Latitude should match input JSON.');
    }

    @IsTest
    static void testDeserializeWaypointsBlankReturnsEmptyList() {
        List<WeatherService.Waypoint> waypoints = WeatherService.deserializeWaypoints(null);
        System.assertEquals(0, waypoints.size(), 'Blank JSON should yield an empty list, not an error.');
    }

    @IsTest
    static void testDeserializeWaypointsInvalidJsonThrows() {
        Boolean threw = false;
        try {
            WeatherService.deserializeWaypoints('not-json');
        } catch (WeatherService.WeatherServiceException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Invalid JSON should raise WeatherServiceException.');
    }

    // =========================================================================
    // buildWaypointRequest
    // =========================================================================

    @IsTest
    static void testBuildWaypointRequestSetsEndpointAndMethod() {
        WeatherService.Waypoint waypoint = new WeatherService.Waypoint();
        waypoint.latitude  = 34.05;
        waypoint.longitude = -118.24;

        HttpRequest request = WeatherService.buildWaypointRequest(waypoint);
        System.assertEquals('GET', request.getMethod(), 'Weather lookups should use GET.');
        System.assertEquals(true, request.getEndpoint().startsWith(WeatherService.API_BASE_URL), 'Endpoint should target Open-Meteo.');
        System.assertEquals(true, request.getEndpoint().contains('latitude=34.05'), 'Endpoint should include latitude.');
    }

    // =========================================================================
    // processWaypoint
    // =========================================================================

    @IsTest
    static void testProcessWaypointHappyPathParsesMatchingHour() {
        String targetHour = futureDepartureHour();
        Test.setMock(HttpCalloutMock.class, new OpenMeteoMock(200, buildMockBody(targetHour, 61)));

        WeatherService.Waypoint waypoint = new WeatherService.Waypoint();
        waypoint.latitude  = 34.05;
        waypoint.longitude = -118.24;
        DateTime departure = futureDeparture();

        Test.startTest();
        WeatherService.WaypointWeatherResult resultData = WeatherService.processWaypoint(waypoint, departure);
        Test.stopTest();

        System.assertEquals(61,         resultData.weatherCode, 'Weather code should be parsed from the matching hour.');
        System.assertEquals(targetHour, resultData.matchedHour, 'Matched hour should equal the target hour.');
    }

    @IsTest
    static void testProcessWaypointNonOkStatusLogsAndReturnsNullCode() {
        Test.setMock(HttpCalloutMock.class, new OpenMeteoMock(500, 'Server Error'));

        WeatherService.Waypoint waypoint = new WeatherService.Waypoint();
        waypoint.latitude  = 34.05;
        waypoint.longitude = -118.24;

        Test.startTest();
        WeatherService.WaypointWeatherResult resultData = WeatherService.processWaypoint(waypoint, futureDeparture());
        Test.stopTest();

        System.assertEquals(null, resultData.weatherCode, 'A failed callout should not set a weather code.');
    }

    @IsTest
    static void testProcessWaypointMissingHourlyDataLogsAndReturnsNullCode() {
        Test.setMock(HttpCalloutMock.class, new OpenMeteoMock(200, '{"latitude":34.05}'));

        WeatherService.Waypoint waypoint = new WeatherService.Waypoint();
        waypoint.latitude  = 34.05;
        waypoint.longitude = -118.24;

        Test.startTest();
        WeatherService.WaypointWeatherResult resultData = WeatherService.processWaypoint(waypoint, futureDeparture());
        Test.stopTest();

        System.assertEquals(null, resultData.weatherCode, 'Missing hourly data should not set a weather code.');
    }

    // =========================================================================
    // aggregateSummary / aggregateSeverity
    // =========================================================================

    @IsTest
    static void testAggregateSummaryAndSeverityAcrossCodes() {
        List<Integer> codes = new List<Integer>{ 0, 61, 96 };
        String summary  = WeatherService.aggregateSummary(codes);
        String severity = WeatherService.aggregateSeverity(codes);

        System.assertEquals(true, summary.contains('Clear sky'), 'Summary should include clear sky description.');
        System.assertEquals(true, summary.contains('Rain'),      'Summary should include rain description.');
        System.assertEquals('Extreme', severity, 'Highest-ranked code (96) should drive severity to Extreme.');
    }

    @IsTest
    static void testAggregateSummaryEmptyListReturnsFallback() {
        String summary = WeatherService.aggregateSummary(new List<Integer>());
        System.assertEquals('No weather data available for this route.', summary, 'Empty codes should return fallback summary.');
    }

    @IsTest
    static void testAggregateSeverityUnknownCodeReturnsUnknown() {
        String severity = WeatherService.aggregateSeverity(new List<Integer>{ 9999 });
        System.assertEquals('Unknown', severity, 'Unmapped codes should aggregate to Unknown severity.');
    }

    // =========================================================================
    // finalizeRoute
    // =========================================================================

    @IsTest
    static void testFinalizeRouteUpdatesRouteFields() {
        Route__c route = [SELECT Id FROM Route__c LIMIT 1];

        WeatherService.WaypointWeatherResult resultData = new WeatherService.WaypointWeatherResult();
        resultData.latitude    = 34.05;
        resultData.longitude   = -118.24;
        resultData.weatherCode = 61;
        resultData.matchedHour = futureDepartureHour();

        Test.startTest();
        WeatherService.finalizeRoute(route.Id, new List<WeatherService.WaypointWeatherResult>{ resultData });
        Test.stopTest();

        Route__c updatedRoute = [
            SELECT Weather_Summary__c, Weather_Alerts_JSON__c, Weather_Severity__c,
                   API_Status__c, Weather_Checked_DateTime__c
            FROM   Route__c
            WHERE  Id = :route.Id
        ];
        System.assertEquals('Success', updatedRoute.API_Status__c,                       'Route should be marked Success after finalize.');
        System.assertEquals(true,      updatedRoute.Weather_Summary__c.contains('Rain'), 'Summary should reflect the rain code.');
        System.assertNotEquals(null,   updatedRoute.Weather_Alerts_JSON__c,              'Alerts JSON should be populated.');
        System.assertNotEquals(null,   updatedRoute.Weather_Checked_DateTime__c,         'Checked timestamp should be populated.');
    }

    // =========================================================================
    // markRouteInProgress / markRouteFailed
    // =========================================================================

    @IsTest
    static void testMarkRouteInProgressAndFailedUpdateStatus() {
        Route__c route = [SELECT Id FROM Route__c LIMIT 1];

        Test.startTest();
        WeatherService.markRouteInProgress(route.Id);
        WeatherService.markRouteFailed(route.Id, 'Simulated failure');
        Test.stopTest();

        Route__c updatedRoute = [SELECT API_Status__c, API_Last_Error__c FROM Route__c WHERE Id = :route.Id];
        System.assertEquals('Failed',            updatedRoute.API_Status__c,    'Route should be marked Failed.');
        System.assertEquals('Simulated failure', updatedRoute.API_Last_Error__c, 'Error message should be persisted.');
    }

    // =========================================================================
    // startProcessing
    // =========================================================================

    /**
     * @description Happy path: verifies startProcessing enqueues a WeatherQueueable job and
     *              the chain completes marking the route Success.
     *
     *              Runs inside System.runAs(permissionedUser) so the FLS guard inside
     *              WeatherService.startProcessing evaluates Route__c.Waypoints_JSON__c
     *              as accessible and does not raise WeatherServiceException.
     */
    @IsTest
    static void testStartProcessingHappyPathEnqueuesJob() {
        // Arrange
        User permissionedUser = createPermissionedUser();
        Test.setMock(HttpCalloutMock.class, new OpenMeteoMock(200, buildMockBody(futureDepartureHour(), 61)));
        Route__c route = [SELECT Id FROM Route__c LIMIT 1];

        // Act — run as a user who holds US_0000488_Access so FLS checks pass
        Id jobId;
        System.runAs(permissionedUser) {
            Test.startTest();
            jobId = WeatherService.startProcessing(route.Id);
            Test.stopTest();
        }

        // Assert
        System.assertNotEquals(null, jobId, 'A Queueable job Id should be returned.');
        Route__c updatedRoute = [SELECT API_Status__c FROM Route__c WHERE Id = :route.Id];
        System.assertEquals('Success', updatedRoute.API_Status__c, 'Chain should complete and mark the route Success.');
    }

    @IsTest
    static void testStartProcessingNullRouteIdThrows() {
        Boolean threw = false;
        try {
            WeatherService.startProcessing(null);
        } catch (WeatherService.WeatherServiceException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'A null routeId should raise WeatherServiceException.');
    }

    @IsTest
    static void testStartProcessingNoWaypointsMarksFailed() {
        Route__c route = LogisticsTestFactory.buildRoute(new Map<String, Object>{
            'Departure_DateTime__c' => futureDeparture(),
            'Waypoints_JSON__c'     => '[]'
        });
        insert route;

        Boolean threw = false;
        Test.startTest();
        try {
            WeatherService.startProcessing(route.Id);
        } catch (WeatherService.WeatherServiceException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Empty waypoints should raise WeatherServiceException.');
        Route__c updatedRoute = [SELECT API_Status__c FROM Route__c WHERE Id = :route.Id];
        System.assertEquals('Failed', updatedRoute.API_Status__c, 'Route should be marked Failed when no waypoints exist.');
    }
}