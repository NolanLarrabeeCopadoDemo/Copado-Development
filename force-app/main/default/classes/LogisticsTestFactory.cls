/**
 * @description Shared test-data factory for the Logistics application (US-0000482).
 *              Provides builder methods that return unsaved SObject instances with
 *              sensible defaults, and convenience creator methods that insert the
 *              records and return them ready for use in test assertions.
 *
 *              Builder methods (build*) accept a Map of field overrides so callers
 *              can customise only the fields relevant to each test scenario without
 *              needing to know every required field.
 *
 *              Creator methods (create*) call the corresponding builder, insert the
 *              record, and return the persisted instance.
 *
 * @author      Nolan Larrabee
 * @date        2026-09-14
 */
@IsTest
public class LogisticsTestFactory {

    // =========================================================================
    // Builder methods - return unsaved records with default values
    // =========================================================================

    /**
     * @description Builds an unsaved Shipment__c with required field defaults.
     *              Pass overrides to customise specific fields, e.g.
     *              new Map<String,Object>{'Status__c' => 'Delivered'}.
     *
     * @param  overrides Optional map of field API name to value.
     * @return           Unsaved Shipment__c.
     */
    public static Shipment__c buildShipment(Map<String, Object> overrides) {
        Shipment__c record = new Shipment__c(
            Cargo_Type__c          = 'General Freight',
            Cargo_Weight_lbs__c    = 1000,
            Cargo_Volume_Cu_Ft__c  = 100,
            Status__c              = 'Draft',
            Origin_State__c        = 'California',
            Destination_State__c   = 'Nevada'
        );
        return (Shipment__c) applyOverrides(record, overrides);
    }

    /**
     * @description Builds an unsaved Equipment__c with required field defaults.
     *
     * @param  overrides Optional map of field API name to value.
     * @return           Unsaved Equipment__c.
     */
    public static Equipment__c buildEquipment(Map<String, Object> overrides) {
        Equipment__c record = new Equipment__c(
            Truck_ID__c              = 'TRK-' + generateUniqueSuffix(),
            VIN__c                   = generateVin(),
            Year__c                  = 2020,
            Payload_Capacity_lbs__c  = 20000,
            Cargo_Capacity_Lbs__c    = 2000,
            Cargo_Volume_Cu_Ft__c    = 1500,
            Truck_Size_Class__c      = 'Class_8',
            Operational_Status__c    = 'Available',
            Refrigeration_Capable__c = false,
            Hazmat_Certified__c      = false
        );
        return (Equipment__c) applyOverrides(record, overrides);
    }

    /**
     * @description Builds an unsaved Route__c with required field defaults.
     *              Total_Mileage__c defaults to 250.5 unless overridden.
     *
     * @param  overrides Optional map of field API name to value.
     * @return           Unsaved Route__c.
     */
    public static Route__c buildRoute(Map<String, Object> overrides) {
        Route__c record = new Route__c(
            Name                       = 'Test Route ' + generateUniqueSuffix(),
            Status__c                  = 'Planned',
            Total_Mileage__c           = 250.5,
            Estimated_Duration_Hours__c = 5,
            Departure_DateTime__c      = DateTime.now().addDays(1),
            Origin_Latitude__c         = 30.0,
            Origin_Longitude__c        = -90.0,
            Destination_Latitude__c    = 40.0,
            Destination_Longitude__c   = -100.0
        );
        return (Route__c) applyOverrides(record, overrides);
    }

    /**
     * @description Builds an unsaved Route__c pre-populated with a Waypoints_JSON__c
     *              array of the requested size, suitable for WeatherService tests.
     *              Each generated waypoint has a latitude/longitude pair; overrides
     *              are applied after the waypoints are set, so callers can still
     *              replace Waypoints_JSON__c entirely if needed.
     *
     * @param  waypointCount Number of waypoint entries to generate.
     * @param  overrides     Optional map of field API name to value.
     * @return               Unsaved Route__c with Waypoints_JSON__c populated.
     */
    public static Route__c buildRouteWithWaypointWeather(Integer waypointCount, Map<String, Object> overrides) {
        List<Map<String, Object>> waypoints = new List<Map<String, Object>>();
        Integer count = waypointCount == null ? 0 : waypointCount;
        for (Integer i = 0; i < count; i++) {
            waypoints.add(new Map<String, Object>{
                'latitude' => 30.0 + i,
                'longitude' => -90.0 - i
            });
        }
        Map<String, Object> combinedOverrides = new Map<String, Object>{
            'Waypoints_JSON__c' => JSON.serialize(waypoints)
        };
        if (overrides != null) {
            combinedOverrides.putAll(overrides);
        }
        return buildRoute(combinedOverrides);
    }

    /**
     * @description Builds an unsaved Completed_Shipment__c with required defaults.
     *
     * @param  shipmentId Id of the parent Shipment__c.
     * @param  overrides  Optional map of field API name to value.
     * @return            Unsaved Completed_Shipment__c.
     */
    public static Completed_Shipment__c buildCompletedShipment(Id shipmentId, Map<String, Object> overrides) {
        Completed_Shipment__c record = new Completed_Shipment__c(
            Shipment__c              = shipmentId,
            Actual_Mileage__c        = 250,
            Driver_Pay__c            = 500,
            Driver_Rating__c         = 4.5,
            Fuel_Price_Per_Gallon__c = 3.5,
            Gross_Revenue__c         = 2000
        );
        return (Completed_Shipment__c) applyOverrides(record, overrides);
    }

    /**
     * @description Builds an unsaved Trip_Expense__c with required defaults.
     *
     * @param  completedShipmentId Id of the parent Completed_Shipment__c.
     * @param  overrides           Optional map of field API name to value.
     * @return                     Unsaved Trip_Expense__c.
     */
    public static Trip_Expense__c buildTripExpense(Id completedShipmentId, Map<String, Object> overrides) {
        Trip_Expense__c record = new Trip_Expense__c(
            Completed_Shipment__c = completedShipmentId,
            Amount__c             = 50,
            Expense_Category__c   = 'Fuel',
            Expense_Date__c       = Date.today()
        );
        return (Trip_Expense__c) applyOverrides(record, overrides);
    }

    // =========================================================================
    // Creator methods - insert and return persisted records
    // =========================================================================

    /**
     * @description Creates and inserts a Route__c with Total_Mileage__c set
     *              to the supplied value. All other fields use build defaults.
     *
     * @param  totalMileage Value for Route__c.Total_Mileage__c.
     * @return              Inserted Route__c.
     */
    public static Route__c createRoute(Decimal totalMileage) {
        Route__c route = buildRoute(
            new Map<String, Object>{ 'Total_Mileage__c' => totalMileage }
        );
        insert route;
        return route;
    }

    /**
     * @description Creates and inserts a Shipment__c linked to the given Route.
     *              Status defaults to "Draft" so tests control the transition.
     *
     * @param  routeId Id of the parent Route__c.
     * @return         Inserted Shipment__c.
     */
    public static Shipment__c createShipment(Id routeId) {
        Shipment__c shipment = buildShipment(
            new Map<String, Object>{
                'Route__c'                  => routeId,
                'Freight_Rate_Per_Mile__c'  => 2.5
            }
        );
        insert shipment;
        return shipment;
    }

    /**
     * @description Creates and inserts the requested number of Shipment__c
     *              records all linked to the same Route. Useful for bulk tests.
     *
     * @param  quantity Number of Shipment__c records to create.
     * @param  routeId  Id of the parent Route__c.
     * @return          List of inserted Shipment__c records.
     */
    public static List<Shipment__c> createShipments(Integer quantity, Id routeId) {
        List<Shipment__c> shipments = new List<Shipment__c>();
        for (Integer i = 0; i < quantity; i++) {
            shipments.add(buildShipment(
                new Map<String, Object>{
                    'Route__c'                 => routeId,
                    'Freight_Rate_Per_Mile__c' => 2.5
                }
            ));
        }
        insert shipments;
        return shipments;
    }

    // =========================================================================
    // Private utilities
    // =========================================================================

    /**
     * @description Applies a map of field overrides to an SObject record.
     *
     * @param  record    The SObject to modify.
     * @param  overrides Map of field API name to value; null is safe.
     * @return           The modified SObject.
     */
    private static SObject applyOverrides(SObject record, Map<String, Object> overrides) {
        if (overrides == null) {
            return record;
        }
        for (String fieldName : overrides.keySet()) {
            record.put(fieldName, overrides.get(fieldName));
        }
        return record;
    }

    /**
     * @description Generates a short unique numeric suffix using two random
     *              integers to avoid name collisions in bulk test data.
     *
     * @return Unique numeric string suffix.
     */
    private static String generateUniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()))
             + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    /**
     * @description Generates a 17-character numeric string suitable for use
     *              as a VIN placeholder in test data. Uses random integers
     *              padded with zeros to guarantee the required length.
     *
     * @return 17-character numeric VIN string.
     */
    private static String generateVin() {
        String base = String.valueOf(Math.abs(Crypto.getRandomLong()));
        String padded = base.leftPad(17, '0');
        return padded.right(17);
    }
}