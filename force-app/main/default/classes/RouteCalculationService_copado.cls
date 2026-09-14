/**
 * Service class responsible for calling the OpenRouteService directions API and
 * populating Route__c records with the resulting distance, duration, and encoded
 * polyline geometry.
 *
 * NOTE (US-0000485 known gap): Nebula Logger is not installed in this org, so
 * INFO/ERROR logging calls specified in the technical spec are intentionally
 * omitted here. TODO: wire up Nebula Logger (or an equivalent) once the package
 * is installed, using Route__c.Id as the log context as specified.
 */
public with sharing class RouteCalculationService_copado {

    @TestVisible
    private static final String CALLOUT_ENDPOINT = 'callout:OpenRouteService/v2/directions/driving-car';

    private static final Decimal METERS_PER_MILE = 1609.344;
    private static final Decimal SECONDS_PER_HOUR = 3600;

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
    }

    private static void handleError(Route__c route, String errorMessage) {
        route.API_Status__c = 'Failed';
        String safeMessage = String.isBlank(errorMessage) ? 'Unknown error calling OpenRouteService.' : errorMessage;
        route.API_Last_Error__c = safeMessage.length() > 32768 ? safeMessage.substring(0, 32768) : safeMessage;
    }
}