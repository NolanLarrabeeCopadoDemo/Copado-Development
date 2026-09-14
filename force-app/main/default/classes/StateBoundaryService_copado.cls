/**
 * Helper class that maps route waypoint coordinates to US state abbreviations
 * using bounding box reference data stored in State_Boundary__mdt, avoiding any
 * hardcoded coordinate values in Apex (US-0000486).
 */
public with sharing class StateBoundaryService_copado {

    /**
     * Given an ordered list of waypoint coordinate maps (each with 'lat'/'lng'
     * Decimal keys), returns the deduplicated list of US state abbreviations
     * whose bounding box contains at least one waypoint, ordered by first
     * occurrence along the route. Waypoints that fall outside every known
     * bounding box are silently skipped.
     */
    public static List<String> getStatesTraversed(List<Map<String, Decimal>> waypoints) {
        List<String> orderedStates = new List<String>();
        if (waypoints == null || waypoints.isEmpty()) {
            return orderedStates;
        }

        List<State_Boundary__mdt> boundaries = getAllBoundaries();
        Set<String> seenStates = new Set<String>();

        for (Map<String, Decimal> waypoint : waypoints) {
            String stateAbbreviation = findStateForCoordinate(boundaries, waypoint.get('lat'), waypoint.get('lng'));
            if (stateAbbreviation != null && !seenStates.contains(stateAbbreviation)) {
                seenStates.add(stateAbbreviation);
                orderedStates.add(stateAbbreviation);
            }
        }

        return orderedStates;
    }

    private static List<State_Boundary__mdt> getAllBoundaries() {
        return [
            SELECT State_Abbreviation__c, Min_Latitude__c, Max_Latitude__c, Min_Longitude__c, Max_Longitude__c
            FROM State_Boundary__mdt
        ];
    }

    private static String findStateForCoordinate(List<State_Boundary__mdt> boundaries, Decimal lat, Decimal lng) {
        if (lat == null || lng == null) {
            return null;
        }
        for (State_Boundary__mdt boundary : boundaries) {
            if (lat >= boundary.Min_Latitude__c && lat <= boundary.Max_Latitude__c
                && lng >= boundary.Min_Longitude__c && lng <= boundary.Max_Longitude__c) {
                return boundary.State_Abbreviation__c;
            }
        }
        return null;
    }
}