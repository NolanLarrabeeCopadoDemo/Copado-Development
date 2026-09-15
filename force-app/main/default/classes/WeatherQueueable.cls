/**
 * @description Queueable for US-0000488. Processes exactly one Route__c waypoint per
 *              execution (one HTTP callout), accumulates the per-waypoint result, and
 *              chains the next WeatherQueueable instance until all waypoints have been
 *              processed, at which point WeatherService.finalizeRoute persists the
 *              aggregated summary back onto the Route__c.
 *
 * @author      Nolan Larrabee
 * @date        2026-09-14
 */
public with sharing class WeatherQueueable implements Queueable, Database.AllowsCallouts {

    private final Id routeId;
    private final List<WeatherService.Waypoint> waypoints;
    private final Integer currentIndex;
    private final List<WeatherService.WaypointWeatherResult> results;
    private final DateTime departureDateTime;

    /**
     * @description Constructs the Queueable for a single execution step.
     *
     * @param  routeId           Id of the Route__c being processed.
     * @param  waypoints         Full ordered list of waypoints for the route.
     * @param  currentIndex      Index of the waypoint to process on this execution.
     * @param  results           Results accumulated from prior executions in the chain.
     * @param  departureDateTime Planned departure DateTime used to select the matching hour.
     */
    public WeatherQueueable(
        Id routeId,
        List<WeatherService.Waypoint> waypoints,
        Integer currentIndex,
        List<WeatherService.WaypointWeatherResult> results,
        DateTime departureDateTime
    ) {
        this.routeId = routeId;
        this.waypoints = waypoints;
        this.currentIndex = currentIndex;
        this.results = results != null ? results : new List<WeatherService.WaypointWeatherResult>();
        this.departureDateTime = departureDateTime;
    }

    /**
     * @description Processes the waypoint at currentIndex, then either chains the next
     *              WeatherQueueable or, once all waypoints are processed, finalizes the
     *              Route__c with the aggregated weather summary.
     *
     * @param  context Queueable execution context provided by the platform.
     */
    public void execute(QueueableContext context) {
        try {
            if (waypoints == null || currentIndex >= waypoints.size()) {
                WeatherService.finalizeRoute(routeId, results);
                return;
            }

            WeatherService.WaypointWeatherResult resultData = WeatherService.processWaypoint(
                waypoints.get(currentIndex),
                departureDateTime
            );
            results.add(resultData);

            Integer nextIndex = currentIndex + 1;
            if (nextIndex < waypoints.size() && !Test.isRunningTest()) {
                System.enqueueJob(new WeatherQueueable(routeId, waypoints, nextIndex, results, departureDateTime));
            } else if (nextIndex < waypoints.size()) {
                // In tests, process the remaining waypoints synchronously so a single Test.stopTest()
                // captures the full chain instead of only the first queueable execution.
                processRemainingSynchronouslyForTests(nextIndex);
            } else {
                WeatherService.finalizeRoute(routeId, results);
            }
        } catch (Exception ex) {
            Logger.error('WeatherQueueable.execute', ex);
            WeatherService.markRouteFailed(routeId, ex.getMessage());
        }
    }

    /**
     * @description Test-only helper that finishes processing the remaining waypoints inline
     *              so unit tests can assert on the fully aggregated Route__c in a single
     *              Test.startTest()/Test.stopTest() block without relying on chained async jobs.
     *
     * @param  startIndex Index of the first remaining waypoint to process.
     */
    @TestVisible
    private void processRemainingSynchronouslyForTests(Integer startIndex) {
        for (Integer i = startIndex; i < waypoints.size(); i++) {
            results.add(WeatherService.processWaypoint(waypoints.get(i), departureDateTime));
        }
        WeatherService.finalizeRoute(routeId, results);
    }
}