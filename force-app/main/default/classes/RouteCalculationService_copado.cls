/**
 * Service class responsible for calling the OpenRouteService directions API and
 * populating Route__c records with the resulting distance, duration, encoded
 * polyline geometry, sampled waypoints, traversed states, and a map embed URL
 * (US-0000485, US-0000486).
 *
 * NOTE: Nebula Logger is not installed in this org (documented gap from
 * US-0000485). INFO/ERROR logging around waypoint extraction uses the org's
 * existing lightweight `Logger` utility (a System.debug wrapper) as the closest
 * available substitute until Nebula Logger is installed.
 */
public with sharing class RouteCalculationService_copado {

    @TestVisible
    private static final String CALLOUT_ENDPOINT = 'callout:OpenRouteService/v2/directions/driving-car';

    private static final Decimal METERS_PER_MILE = 1609.344;
    private static final Decimal SECONDS_PER_HOUR = 3600;
    private static final Integer TARGET_WAYPOINT_DIVISOR = 6;
    private static final Integer MIN_WAYPOINTS = 6;
    private static final Integer MAX_WAYPOINTS = 8;
    private static final String MAP_EMBED_URL_TEMPLATE =
        'https://www.google.com/maps/dir/?api=1&origin={0},{1}&destination={2},{3}';

    /** Thrown when the OpenRouteService response cannot be parsed as expected. */
    public class RouteCalculationException extends Exception {}

    /**
     * Calculates distance/duration/polyline for every route in the list that has
     * complete origin and destination coordinates. Records without complete
     * coordinates are left untouched. Results are written onto the in-memory
     * sObjects only; callers are responsible for persisting the changes.
     */
    public static void calculateAndPopulate(List<Route__c> routes) {
        if (routes == null) {
            return;
        }
        for (Route__c route : routes) {
            if (hasCompleteCoordinates(route)) {
                calculateSingleRoute(route);
            }
        }
    }

    private static Boolean hasCompleteCoordinates(Route__c route) {
        return route.Origin_Latitude__c != null
            && route.Origin_Longitude__c != null
            && route.Destination_Latitude__c != null
            && route.Destination_Longitude__c != null;
    }

    private static void calculateSingleRoute(Route__c route) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(CALLOUT_ENDPOINT);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(buildRequestBody(route));
        request.setTimeout(30000);

        Http http = new Http();
        try {
            HttpResponse response = http.send(request);
            if (response.getStatusCode() == 200) {
                parseResponse(route, response.getBody());
                route.API_Status__c = 'Success';
                route.API_Last_Error__c = null;
                route.Map_Embed_URL__c = buildMapEmbedUrl(route);
            } else {
                handleError(route, 'HTTP ' + response.getStatusCode() + ': ' + response.getBody());
            }
        } catch (Exception ex) {
            handleError(route, ex.getMessage());
        }
    }

    private static String buildRequestBody(Route__c route) {
        List<List<Decimal>> coordinates = new List<List<Decimal>>();
        coordinates.add(new List<Decimal>{ route.Origin_Longitude__c, route.Origin_Latitude__c });
        coordinates.add(new List<Decimal>{ route.Destination_Longitude__c, route.Destination_Latitude__c });

        Map<String, Object> body = new Map<String, Object>();
        body.put('coordinates', coordinates);
        return JSON.serialize(body);
    }

    private static void parseResponse(Route__c route, String jsonBody) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        List<Object> routesList = (List<Object>) parsed.get('routes');
        if (routesList == null || routesList.isEmpty()) {
            throw new RouteCalculationException('OpenRouteService response contained no routes.');
        }

        Map<String, Object> firstRoute = (Map<String, Object>) routesList[0];
        Map<String, Object> summary = (Map<String, Object>) firstRoute.get('summary');
        if (summary == null) {
            throw new RouteCalculationException('OpenRouteService response missing summary data.');
        }

        Decimal distanceMeters = summary.get('distance') != null
            ? Decimal.valueOf(String.valueOf(summary.get('distance')))
            : 0;
        Decimal durationSeconds = summary.get('duration') != null
            ? Decimal.valueOf(String.valueOf(summary.get('duration')))
            : 0;
        String geometry = (String) firstRoute.get('geometry');

        route.Total_Mileage__c = (distanceMeters / METERS_PER_MILE).setScale(1, System.RoundingMode.HALF_UP);
        route.Estimated_Duration_Hours__c = (durationSeconds / SECONDS_PER_HOUR).setScale(2, System.RoundingMode.HALF_UP);
        route.Encoded_Polyline__c = geometry;

        extractWaypointsAndStates(route, geometry);
    }

    /**
     * Decodes the encoded polyline, samples 6-8 evenly distributed waypoints,
     * serializes them onto Route__c.Waypoints_JSON__c, and derives the
     * deduplicated, route-ordered list of traversed states onto
     * Route__c.States_Traversed__c. Decode failures are logged and swallowed so
     * that a waypoint extraction problem does not fail the whole route
     * calculation, since distance/duration have already been parsed.
     */
    private static void extractWaypointsAndStates(Route__c route, String geometry) {
        try {
            List<Map<String, Decimal>> decodedPoints = PolylineDecoderUtil_copado.decode(geometry);
            if (decodedPoints.isEmpty()) {
                return;
            }

            List<Map<String, Decimal>> sampledWaypoints = sampleWaypoints(decodedPoints);
            route.Waypoints_JSON__c = JSON.serialize(sampledWaypoints);

            List<String> statesTraversed = StateBoundaryService_copado.getStatesTraversed(sampledWaypoints);
            route.States_Traversed__c = String.join(statesTraversed, ', ');

            Logger.info(String.valueOf(route.Id), 'Waypoints extracted successfully: ' + sampledWaypoints.size() + ' points.');
        } catch (Exception ex) {
            Logger.error(String.valueOf(route.Id), ex);
        }
    }

    /**
     * Samples evenly distributed waypoints from the full decoded point list.
     * Step interval is totalPoints / TARGET_WAYPOINT_DIVISOR; points are taken
     * at each interval index, the final point is always included, and the
     * result is padded or trimmed to guarantee 6-8 points regardless of the
     * total decoded point count.
     */
    private static List<Map<String, Decimal>> sampleWaypoints(List<Map<String, Decimal>> allPoints) {
        List<Map<String, Decimal>> sampled = new List<Map<String, Decimal>>();
        Integer totalPoints = allPoints.size();
        Integer step = Math.max(1, totalPoints / TARGET_WAYPOINT_DIVISOR);
        Integer lastIndex = totalPoints - 1;
        Integer lastSampledIndex = -1;

        for (Integer index = 0; index < totalPoints; index += step) {
            sampled.add(allPoints[index]);
            lastSampledIndex = index;
        }

        if (lastSampledIndex != lastIndex) {
            sampled.add(allPoints[lastIndex]);
        }

        Map<String, Decimal> lastPoint = allPoints[lastIndex];
        while (sampled.size() < MIN_WAYPOINTS) {
            sampled.add(lastPoint);
        }
        while (sampled.size() > MAX_WAYPOINTS) {
            sampled.remove(sampled.size() - 2);
        }

        return sampled;
    }

    private static String buildMapEmbedUrl(Route__c route) {
        return String.format(
            MAP_EMBED_URL_TEMPLATE,
            new List<String>{
                String.valueOf(route.Origin_Latitude__c),
                String.valueOf(route.Origin_Longitude__c),
                String.valueOf(route.Destination_Latitude__c),
                String.valueOf(route.Destination_Longitude__c)
            }
        );
    }

    private static void handleError(Route__c route, String errorMessage) {
        route.API_Status__c = 'Failed';
        String safeMessage = String.isBlank(errorMessage) ? 'Unknown error calling OpenRouteService.' : errorMessage;
        route.API_Last_Error__c = safeMessage.length() > 32768 ? safeMessage.substring(0, 32768) : safeMessage;
    }
}