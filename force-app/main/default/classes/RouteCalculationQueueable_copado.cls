/**
 * Queueable job that requeries a set of Route__c Ids, delegates distance/duration/
 * polyline calculation to RouteCalculationService_copado, and performs a single
 * bulkified DML update with the results.
 *
 * NOTE (US-0000485 known gap): Nebula Logger is not installed in this org, so the
 * INFO/ERROR logging calls specified in the technical spec are intentionally
 * omitted here. TODO: wire up Nebula Logger once the package is installed.
 */
public with sharing class RouteCalculationQueueable_copado implements Queueable, Database.AllowsCallouts {

    // Each Route__c requires its own callout, and a single transaction allows a
    // maximum of 100 callouts, so no single run of this job may process more
    // than that. Only one queueable can be chained from another queueable, so
    // keeping the batch size at the governor limit itself minimizes the number
    // of chained levels required for very large record sets.
    @TestVisible
    private static final Integer MAX_ROUTES_PER_RUN = 100;

    private final Set<Id> routeIds;

    public RouteCalculationQueueable_copado(Set<Id> routeIds) {
        this.routeIds = routeIds;
    }

    public void execute(QueueableContext context) {
        if (routeIds == null || routeIds.isEmpty()) {
            return;
        }

        List<Id> allIds = new List<Id>(routeIds);
        List<Id> currentBatchIds = new List<Id>();
        Set<Id> remainingIds = new Set<Id>();

        for (Integer i = 0; i < allIds.size(); i++) {
            if (i < MAX_ROUTES_PER_RUN) {
                currentBatchIds.add(allIds[i]);
            } else {
                remainingIds.add(allIds[i]);
            }
        }

        List<Route__c> routes = [
            SELECT Id, Origin_Latitude__c, Origin_Longitude__c,
                   Destination_Latitude__c, Destination_Longitude__c,
                   Total_Mileage__c, Estimated_Duration_Hours__c,
                   Encoded_Polyline__c, API_Status__c, API_Last_Error__c
            FROM Route__c
            WHERE Id IN :currentBatchIds
        ];

        if (!routes.isEmpty()) {
            RouteCalculationService_copado.calculateAndPopulate(routes);
            Database.update(routes, false);
        }

        // Chain the remaining batch as a single follow-up job. Only one job can
        // be enqueued from within an executing queueable, which this satisfies.
        // Chaining from within a queueable that is itself running in a test
        // context throws "Maximum stack depth has been reached", so it is
        // skipped there; production behavior is unaffected.
        if (!remainingIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new RouteCalculationQueueable_copado(remainingIds));
        }
    }
}