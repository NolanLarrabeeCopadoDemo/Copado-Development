/**
 * After insert/update trigger on Route__c. Detects changes to coordinate or
 * departure date/time fields and enqueues RouteCalculationQueueable_copado once
 * per transaction with the affected record Ids.
 */
trigger route_insert_update_copado on Route__c (after insert, after update) {

    Set<Id> changedRouteIds = new Set<Id>();

    for (Route__c route : Trigger.new) {
        Route__c oldRoute = Trigger.isUpdate ? Trigger.oldMap.get(route.Id) : null;

        Boolean coordinatesReady = route.Origin_Latitude__c != null
            && route.Origin_Longitude__c != null
            && route.Destination_Latitude__c != null
            && route.Destination_Longitude__c != null;

        Boolean relevantFieldChanged = Trigger.isInsert
            ? coordinatesReady
            : coordinatesReady && (
                route.Origin_Latitude__c != oldRoute.Origin_Latitude__c
                || route.Origin_Longitude__c != oldRoute.Origin_Longitude__c
                || route.Destination_Latitude__c != oldRoute.Destination_Latitude__c
                || route.Destination_Longitude__c != oldRoute.Destination_Longitude__c
                || route.Departure_DateTime__c != oldRoute.Departure_DateTime__c
            );

        if (relevantFieldChanged) {
            changedRouteIds.add(route.Id);
        }
    }

    if (!changedRouteIds.isEmpty()) {
        System.enqueueJob(new RouteCalculationQueueable_copado(changedRouteIds));
    }
}