/**
 * @description Service class for US-0000488. Reads a Route__c's Waypoints_JSON__c field,
 *              deserializes the waypoint coordinates, builds and sends per-waypoint HTTP
 *              callouts to the Open-Meteo forecast API, parses the returned hourly arrays
 *              to find the WMO weather code for the planned departure hour, aggregates the
 *              codes across all waypoints into a single summary/severity, and persists the
 *              results back onto the Route__c record.
 *
 *              Waypoints_JSON__c is expected to contain a JSON array of objects shaped like
 *              [{"latitude":34.05,"longitude":-118.24}, ...]. Each element deserializes into
 *              the inner Waypoint class below.
 *
 * @author      Nolan Larrabee
 * @date        2026-09-14
 */
public with sharing class WeatherService {

    /** Open-Meteo forecast endpoint (allow-listed via the OpenMeteoAPI Remote Site Setting). */
    public static final String API_BASE_URL = 'https://api.open-meteo.com/v1/forecast';

    /** Callout timeout in milliseconds. */
    private static final Integer CALLOUT_TIMEOUT_MS = 15000;

    /** Lookup table mapping WMO weather-code ranges to a description and severity rank. */
    private static final List<WmoCodeRange> WMO_RANGES = buildWmoRanges();

    /** Severity rank (0-4) to Weather_Severity__c picklist label. */
    private static final Map<Integer, String> SEVERITY_LABELS = new Map<Integer, String>{
        0 => 'Low',
        1 => 'Moderate',
        2 => 'High',
        3 => 'Severe',
        4 => 'Extreme'
    };

    /**
     * @description Exception type raised for all WeatherService processing failures.
     */
    public class WeatherServiceException extends Exception {}

    /**
     * @description Deserialization target for a single entry of Waypoints_JSON__c.
     */
    public class Waypoint {
        public Decimal latitude;
        public Decimal longitude;
    }

    /**
     * @description Result of processing a single waypoint's weather lookup; also the shape
     *              persisted (as a JSON array) into Weather_Alerts_JSON__c.
     */
    public class WaypointWeatherResult {
        public Decimal latitude;
        public Decimal longitude;
        public Integer weatherCode;
        public String matchedHour;
    }

    /**
     * @description Internal lookup row mapping an inclusive WMO code range to a description
     *              and a numeric severity rank (higher is worse).
     */
    private class WmoCodeRange {
        Integer minCode;
        Integer maxCode;
        Integer severityRank;
        String description;
    }

    /**
     * @description Entry point that reads the Route__c, deserializes its waypoints, marks the
     *              route "In Progress", and enqueues the first WeatherQueueable to begin
     *              processing waypoints one at a time.
     *
     * @param  routeId Id of the Route__c to process.
     * @return         AsyncApexJob Id of the enqueued WeatherQueueable.
     */
    public static Id startProcessing(Id routeId) {
        if (routeId == null) {
            throw new WeatherServiceException('routeId is required to start weather processing.');
        }
        try {
            if (!Schema.sObjectType.Route__c.isAccessible()
                || !Schema.sObjectType.Route__c.fields.Waypoints_JSON__c.isAccessible()) {
                throw new WeatherServiceException('Insufficient access to read Route__c waypoint data.');
            }

            List<Route__c> routes = [
                SELECT Id, Waypoints_JSON__c, Departure_DateTime__c
                FROM Route__c
                WHERE Id = :routeId
                LIMIT 1
            ];
            if (routes.isEmpty()) {
                throw new WeatherServiceException('Route__c not found for Id: ' + routeId);
            }

            List<Waypoint> waypoints = deserializeWaypoints(routes[0].Waypoints_JSON__c);
            if (waypoints.isEmpty()) {
                throw new WeatherServiceException('Route__c has no waypoints to process: ' + routeId);
            }

            DateTime departureDateTime = routes[0].Departure_DateTime__c != null
                ? routes[0].Departure_DateTime__c
                : DateTime.now();

            markRouteInProgress(routeId);
            return System.enqueueJob(
                new WeatherQueueable(routeId, waypoints, 0, new List<WaypointWeatherResult>(), departureDateTime)
            );
        } catch (Exception ex) {
            Logger.error('WeatherService.startProcessing', ex);
            markRouteFailed(routeId, ex.getMessage());
            throw new WeatherServiceException('Unable to start weather processing: ' + ex.getMessage());
        }
    }

    /**
     * @description Deserializes the Waypoints_JSON__c JSON array into a list of Waypoint.
     *
     * @param  waypointsJson Raw JSON array string; blank returns an empty list.
     * @return               List of deserialized Waypoint instances.
     */
    public static List<Waypoint> deserializeWaypoints(String waypointsJson) {
        List<Waypoint> waypoints = new List<Waypoint>();
        if (String.isBlank(waypointsJson)) {
            return waypoints;
        }
        try {
            waypoints = (List<Waypoint>) JSON.deserialize(waypointsJson, List<Waypoint>.class);
        } catch (Exception ex) {
            Logger.error('WeatherService.deserializeWaypoints', ex);
            throw new WeatherServiceException('Unable to parse Waypoints_JSON__c: ' + ex.getMessage());
        }
        return waypoints;
    }

    /**
     * @description Builds the Open-Meteo HTTP GET request for a single waypoint's coordinates.
     *
     * @param  waypoint Waypoint containing latitude/longitude.
     * @return          Configured HttpRequest ready to send.
     */
    public static HttpRequest buildWaypointRequest(Waypoint waypoint) {
        String endpoint = API_BASE_URL
            + '?latitude=' + EncodingUtil.urlEncode(String.valueOf(waypoint.latitude), 'UTF-8')
            + '&longitude=' + EncodingUtil.urlEncode(String.valueOf(waypoint.longitude), 'UTF-8')
            + '&hourly=weathercode&timezone=UTC';

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setTimeout(CALLOUT_TIMEOUT_MS);
        return request;
    }

    /**
     * @description Sends the callout for a single waypoint and parses the hourly forecast to
     *              find the WMO weather code matching the planned departure hour. Callout or
     *              parsing failures are logged and result in a null weatherCode rather than a
     *              thrown exception, so a single bad waypoint does not abort the whole chain.
     *
     * @param  waypoint          Waypoint to look up.
     * @param  departureDateTime Planned departure DateTime used to select the matching hour.
     * @return                   WaypointWeatherResult with weatherCode populated when available.
     */
    public static WaypointWeatherResult processWaypoint(Waypoint waypoint, DateTime departureDateTime) {
        WaypointWeatherResult resultData = new WaypointWeatherResult();
        resultData.latitude = waypoint.latitude;
        resultData.longitude = waypoint.longitude;
        try {
            HttpRequest request = buildWaypointRequest(waypoint);
            Http http = new Http();
            HttpResponse response = http.send(request);
            if (response.getStatusCode() != 200) {
                throw new WeatherServiceException('Open-Meteo API returned status ' + response.getStatusCode());
            }
            parseHourlyWeather(response.getBody(), departureDateTime, resultData);
        } catch (Exception ex) {
            Logger.error('WeatherService.processWaypoint', ex);
        }
        return resultData;
    }

    /**
     * @description Parses the Open-Meteo response body's hourly.time / hourly.weathercode
     *              arrays and populates the matched hour and weather code onto resultData.
     *
     * @param  responseBody      Raw JSON response body from Open-Meteo.
     * @param  departureDateTime Planned departure DateTime used to select the matching hour.
     * @param  resultData        WaypointWeatherResult to populate in place.
     */
    private static void parseHourlyWeather(String responseBody, DateTime departureDateTime, WaypointWeatherResult resultData) {
        Map<String, Object> parsedBody = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> hourly = (Map<String, Object>) parsedBody.get('hourly');
        if (hourly == null) {
            throw new WeatherServiceException('Open-Meteo response missing hourly data.');
        }
        List<Object> hours = (List<Object>) hourly.get('time');
        List<Object> weatherCodes = (List<Object>) hourly.get('weathercode');
        if (hours == null || weatherCodes == null || hours.isEmpty() || weatherCodes.isEmpty()) {
            throw new WeatherServiceException('Open-Meteo response missing hourly time/weathercode arrays.');
        }

        String targetHour = departureDateTime.formatGmt('yyyy-MM-dd\'T\'HH:00');
        Integer matchIndex = hours.indexOf(targetHour);
        if (matchIndex < 0) {
            matchIndex = 0;
        }

        resultData.matchedHour = (String) hours.get(matchIndex);
        resultData.weatherCode = matchIndex < weatherCodes.size()
            ? Integer.valueOf((Object) weatherCodes.get(matchIndex))
            : null;
    }

    /**
     * @description Aggregates all per-waypoint results once the chain completes: builds the
     *              summary string and severity, serializes the alerts JSON, and updates the
     *              Route__c with the final Success state.
     *
     * @param  routeId Id of the Route__c being finalized.
     * @param  results Accumulated WaypointWeatherResult list, one per waypoint.
     */
    public static void finalizeRoute(Id routeId, List<WaypointWeatherResult> results) {
        try {
            if (!Schema.sObjectType.Route__c.isUpdateable()) {
                throw new WeatherServiceException('Insufficient access to update Route__c.');
            }
            List<Integer> codes = new List<Integer>();
            for (WaypointWeatherResult resultData : results) {
                if (resultData.weatherCode != null) {
                    codes.add(resultData.weatherCode);
                }
            }

            Route__c routeToUpdate = new Route__c(
                Id = routeId,
                Weather_Summary__c = aggregateSummary(codes),
                Weather_Alerts_JSON__c = JSON.serialize(results),
                Weather_Checked_DateTime__c = DateTime.now(),
                Weather_Severity__c = aggregateSeverity(codes),
                API_Status__c = 'Success',
                API_Last_Error__c = null
            );
            update routeToUpdate;
        } catch (Exception ex) {
            Logger.error('WeatherService.finalizeRoute', ex);
            markRouteFailed(routeId, ex.getMessage());
        }
    }

    /**
     * @description Aggregates a list of WMO weather codes into a single human-readable summary
     *              string, deduplicating repeated descriptions across waypoints.
     *
     * @param  codes WMO weather codes collected across all waypoints.
     * @return       Semicolon-separated summary, or a fallback message when no codes exist.
     */
    public static String aggregateSummary(List<Integer> codes) {
        if (codes == null || codes.isEmpty()) {
            return 'No weather data available for this route.';
        }
        Set<String> descriptions = new Set<String>();
        for (Integer code : codes) {
            descriptions.add(describeWmoCode(code));
        }
        List<String> sortedDescriptions = new List<String>(descriptions);
        sortedDescriptions.sort();
        return String.join(sortedDescriptions, '; ');
    }

    /**
     * @description Aggregates a list of WMO weather codes into the single worst-case
     *              Weather_Severity__c label across all waypoints.
     *
     * @param  codes WMO weather codes collected across all waypoints.
     * @return       Weather_Severity__c label; 'Unknown' when no codes could be ranked.
     */
    public static String aggregateSeverity(List<Integer> codes) {
        Integer maxRank = -1;
        if (codes != null) {
            for (Integer code : codes) {
                Integer rank = severityRank(code);
                if (rank > maxRank) {
                    maxRank = rank;
                }
            }
        }
        return SEVERITY_LABELS.containsKey(maxRank) ? SEVERITY_LABELS.get(maxRank) : 'Unknown';
    }

    /**
     * @description Marks the Route__c as actively being processed and clears any prior error.
     *
     * @param  routeId Id of the Route__c to update.
     */
    public static void markRouteInProgress(Id routeId) {
        try {
            if (!Schema.sObjectType.Route__c.isUpdateable()) {
                throw new WeatherServiceException('Insufficient access to update Route__c.');
            }
            update new Route__c(Id = routeId, API_Status__c = 'In Progress', API_Last_Error__c = null);
        } catch (Exception ex) {
            Logger.error('WeatherService.markRouteInProgress', ex);
        }
    }

    /**
     * @description Marks the Route__c as failed and records the error detail for support.
     *
     * @param  routeId      Id of the Route__c to update.
     * @param  errorMessage Error detail to persist to API_Last_Error__c.
     */
    public static void markRouteFailed(Id routeId, String errorMessage) {
        try {
            if (!Schema.sObjectType.Route__c.isUpdateable()) {
                throw new WeatherServiceException('Insufficient access to update Route__c.');
            }
            update new Route__c(
                Id = routeId,
                API_Status__c = 'Failed',
                API_Last_Error__c = errorMessage,
                Weather_Checked_DateTime__c = DateTime.now()
            );
        } catch (Exception ex) {
            Logger.error('WeatherService.markRouteFailed', ex);
        }
    }

    /**
     * @description Looks up the description/severity for a single WMO code.
     *
     * @param  code WMO weather code.
     * @return      Matching WmoCodeRange, or null when the code is unmapped.
     */
    private static WmoCodeRange findRange(Integer code) {
        if (code == null) {
            return null;
        }
        for (WmoCodeRange range : WMO_RANGES) {
            if (code >= range.minCode && code <= range.maxCode) {
                return range;
            }
        }
        return null;
    }

    /**
     * @description Human-readable description for a single WMO weather code.
     *
     * @param  code WMO weather code.
     * @return      Description, or an 'Unknown (code N)' fallback when unmapped.
     */
    private static String describeWmoCode(Integer code) {
        WmoCodeRange range = findRange(code);
        return range == null ? 'Unknown (code ' + code + ')' : range.description;
    }

    /**
     * @description Numeric severity rank (0=Low .. 4=Extreme) for a single WMO weather code.
     *
     * @param  code WMO weather code.
     * @return      Severity rank, or -1 when the code is unmapped.
     */
    private static Integer severityRank(Integer code) {
        WmoCodeRange range = findRange(code);
        return range == null ? -1 : range.severityRank;
    }

    /**
     * @description Builds the static WMO code range lookup table used by findRange.
     *
     * @return List of WmoCodeRange covering the standard WMO weather interpretation codes.
     */
    private static List<WmoCodeRange> buildWmoRanges() {
        List<WmoCodeRange> ranges = new List<WmoCodeRange>();
        ranges.add(makeRange(0, 0, 0, 'Clear sky'));
        ranges.add(makeRange(1, 3, 0, 'Partly cloudy'));
        ranges.add(makeRange(45, 48, 1, 'Fog'));
        ranges.add(makeRange(51, 57, 1, 'Drizzle'));
        ranges.add(makeRange(61, 67, 2, 'Rain'));
        ranges.add(makeRange(71, 77, 2, 'Snow'));
        ranges.add(makeRange(80, 82, 2, 'Rain showers'));
        ranges.add(makeRange(85, 86, 2, 'Snow showers'));
        ranges.add(makeRange(95, 95, 3, 'Thunderstorm'));
        ranges.add(makeRange(96, 99, 4, 'Thunderstorm with hail'));
        return ranges;
    }

    /**
     * @description Constructs a single WmoCodeRange row.
     *
     * @param  minCode     Inclusive lower bound of the WMO code range.
     * @param  maxCode     Inclusive upper bound of the WMO code range.
     * @param  rank        Severity rank for codes in this range.
     * @param  description Human-readable description for codes in this range.
     * @return             Populated WmoCodeRange.
     */
    private static WmoCodeRange makeRange(Integer minCode, Integer maxCode, Integer rank, String description) {
        WmoCodeRange range = new WmoCodeRange();
        range.minCode = minCode;
        range.maxCode = maxCode;
        range.severityRank = rank;
        range.description = description;
        return range;
    }
}