@IsTest
public class LogisticsTestFactory {

    public static Shipment__c buildShipment(Map<String, Object> overrides) {
        Shipment__c record = new Shipment__c(
            Cargo_Type__c = 'General Freight',
            Cargo_Weight_lbs__c = 1000,
            Cargo_Volume_Cu_Ft__c = 100,
            Status__c = 'Draft',
            Origin_State__c = 'California',
            Destination_State__c = 'Nevada'
        );
        return (Shipment__c) applyOverrides(record, overrides);
    }

    public static Equipment__c buildEquipment(Map<String, Object> overrides) {
        Equipment__c record = new Equipment__c(
            Truck_ID__c = 'TRK-' + generateUniqueSuffix(),
            VIN__c = generateVin(),
            Year__c = 2020,
            Payload_Capacity_lbs__c = 20000,
            Cargo_Capacity_Lbs__c = 2000,
            Cargo_Volume_Cu_Ft__c = 1500,
            Truck_Size_Class__c = 'Class_8',
            Operational_Status__c = 'Available',
            Refrigeration_Capable__c = false,
            Hazmat_Certified__c = false
        );
        return (Equipment__c) applyOverrides(record, overrides);
    }

    public static Route__c buildRoute(Map<String, Object> overrides) {
        Route__c record = new Route__c(
            Name = 'Test Route ' + generateUniqueSuffix(),
            Status__c = 'Planned',
            Total_Mileage__c = 250.5,
            Estimated_Duration_Hours__c = 5,
            Departure_DateTime__c = DateTime.now().addDays(1),
            Origin_Latitude__c = 30.0,
            Origin_Longitude__c = -90.0,
            Destination_Latitude__c = 40.0,
            Destination_Longitude__c = -100.0
        );
        return (Route__c) applyOverrides(record, overrides);
    }

    public static Completed_Shipment__c buildCompletedShipment(Id shipmentId, Map<String, Object> overrides) {
        Completed_Shipment__c record = new Completed_Shipment__c(
            Shipment__c = shipmentId,
            Actual_Mileage__c = 250,
            Driver_Pay__c = 500,
            Driver_Rating__c = 4.5,
            Fuel_Price_Per_Gallon__c = 3.5,
            Gross_Revenue__c = 2000
        );
        return (Completed_Shipment__c) applyOverrides(record, overrides);
    }

    public static Trip_Expense__c buildTripExpense(Id completedShipmentId, Map<String, Object> overrides) {
        Trip_Expense__c record = new Trip_Expense__c(
            Completed_Shipment__c = completedShipmentId,
            Amount__c = 50,
            Expense_Category__c = 'Fuel',
            Expense_Date__c = Date.today()
        );
        return (Trip_Expense__c) applyOverrides(record, overrides);
    }

    private static SObject applyOverrides(SObject record, Map<String, Object> overrides) {
        if (overrides == null) {
            return record;
        }
        for (String fieldName : overrides.keySet()) {
            record.put(fieldName, overrides.get(fieldName));
        }
        return record;
    }

    private static String generateUniqueSuffix() {
        return String.valueOf(Crypto.getRandomInteger());
    }

    private static String generateVin() {
        String raw = String.valueOf(Crypto.getRandomInteger()) + String.valueOf(Crypto.getRandomInteger());
        String digitsOnly = raw.replaceAll('[^0-9]', '');
        while (digitsOnly.length() < 17) {
            digitsOnly += digitsOnly;
        }
        return digitsOnly.substring(0, 17);
    }
}