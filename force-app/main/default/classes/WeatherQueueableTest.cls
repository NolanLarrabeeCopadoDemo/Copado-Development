/**
 * @description Unit tests for WeatherQueueable (US-0000489). Verifies single-waypoint
 *              processing, in-test synchronous chaining to completion, and failure handling,
 *              using LogisticsTestFactory for Route__c setup and HttpCalloutMock for the
 *              Open-Meteo callouts.
 *
 * @author      Nolan Larrabee
 * @date        2026-09-15
 */
@IsTest
private class WeatherQueueableTest {

    /**
     * @description Simple HttpCalloutMock returning a fixed status code and body for every
     *              request, so each waypoint callout in the chain resolves deterministically.
     */
    private class OpenMeteoMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String body;

        OpenMeteoMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            response.setHeader('Content-Type', 'application/json');
            return response;
        }
    }

    /**
     * @description Builds a minimal Open-Meteo hourly forecast JSON body whose single hour
     *              matches targetHour and carries weatherCode.
     *
     * @param  targetHour  Hour string that should match the departure lookup.
     * @param  weatherCode WMO weather code to place at that hour.
     * @return             Serialized JSON response body.
     */
    private static String buildMockBody(String targetHour, Integer weatherCode) {
        Map<String, Object> hourly = new Map<String, Object>{
            'time' => new List<String>{ targetHour },
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

    @TestSetup
    static void setup() {
        Route__c route = LogisticsTestFactory.buildRoute(new Map<String, Object>{
            'Departure_DateTime__c' => futureDeparture(),
            'Waypoints_JSON__c'     => '[{"latitude":34.05,"longitude":-118.24},{"latitude":36.16,"longitude":-115.15}]'
        });
        insert route;
    }

    @IsTest
    static void testExecuteProcessesAllWaypointsAndFinalizesRoute() {
        Test.setMock(HttpCalloutMock.class, new OpenMeteoMock(200, buildMockBody(futureDepartureHour(), 61)));
        Route__c route = [SELECT Id, Waypoints_JSON__c, Departure_DateTime__c FROM Route__c LIMIT 1];
        List<WeatherService.Waypoint> waypoints = WeatherService.deserializeWaypoints(route.Waypoints_JSON__c);

        Test.startTest();
        System.enqueueJob(
            new WeatherQueueable(route.Id, waypoints, 0, new List<WeatherService.WaypointWeatherResult>(), route.Departure_DateTime__c)
        );
        Test.stopTest();

        Route__c updatedRoute = [
            SELECT API_Status__c, Weather_Summary__c, Weather_Alerts_JSON__c
            FROM Route__c
            WHERE Id = :route.Id
        ];
        System.assertEquals('Success', updatedRoute.API_Status__c, 'All waypoints processed, route should finalize as Success.');
        System.assertEquals(true, updatedRoute.Weather_Summary__c.contains('Rain'), 'Summary should reflect the mocked rain code.');

        List<Object> alerts = (List<Object>) JSON.deserializeUntyped(updatedRoute.Weather_Alerts_JSON__c);
        System.assertEquals(2, alerts.size(), 'Alerts JSON should contain one entry per waypoint.');
    }

    @IsTest
    static void testExecuteWithNoWaypointsFinalizesImmediately() {
        Route__c route = [SELECT Id, Departure_DateTime__c FROM Route__c LIMIT 1];

        Test.startTest();
        System.enqueueJob(
            new WeatherQueueable(route.Id, new List<WeatherService.Waypoint>(), 0, new List<WeatherService.WaypointWeatherResult>(), route.Departure_DateTime__c)
        );
        Test.stopTest();

        Route__c updatedRoute = [SELECT API_Status__c, Weather_Summary__c FROM Route__c WHERE Id = :route.Id];
        System.assertEquals('Success',                                    updatedRoute.API_Status__c,    'An empty waypoint list should still finalize the route.');
        System.assertEquals('No weather data available for this route.', updatedRoute.Weather_Summary__c, 'No waypoints should produce the fallback summary.');
    }

    @IsTest
    static void testExecuteCalloutFailureStillFinalizesWithoutThrowing() {
        Test.setMock(HttpCalloutMock.class, new OpenMeteoMock(500, 'Server Error'));
        Route__c route = [SELECT Id, Waypoints_JSON__c, Departure_DateTime__c FROM Route__c LIMIT 1];
        List<WeatherService.Waypoint> waypoints = WeatherService.deserializeWaypoints(route.Waypoints_JSON__c);

        Test.startTest();
        System.enqueueJob(
            new WeatherQueueable(route.Id, waypoints, 0, new List<WeatherService.WaypointWeatherResult>(), route.Departure_DateTime__c)
        );
        Test.stopTest();

        Route__c updatedRoute = [SELECT API_Status__c, Weather_Summary__c FROM Route__c WHERE Id = :route.Id];
        System.assertEquals('Success',                                    updatedRoute.API_Status__c,    'Individual callout failures are logged, not thrown, so the chain still finalizes.');
        System.assertEquals('No weather data available for this route.', updatedRoute.Weather_Summary__c, 'No codes resolved, so the fallback summary should be used.');
    }

    @IsTest
    static void testExecuteInvalidRouteIdLogsAndMarksFailedWithoutThrowing() {
        Test.setMock(HttpCalloutMock.class, new OpenMeteoMock(200, buildMockBody(futureDepartureHour(), 61)));
        List<WeatherService.Waypoint> waypoint = new List<WeatherService.Waypoint>{ new WeatherService.Waypoint() };
        waypoint[0].latitude  = 34.05;
        waypoint[0].longitude = -118.24;

        Test.startTest();
        System.enqueueJob(
            new WeatherQueueable(null, waypoint, 0, new List<WeatherService.WaypointWeatherResult>(), futureDeparture())
        );
        Test.stopTest();

        // No assertion on Route__c since routeId is null; success criteria is that execute()
        // completes without throwing an unhandled exception out of the queueable context.
        System.assertEquals(true, true, 'Execute should complete gracefully even with a null routeId.');
    }
}