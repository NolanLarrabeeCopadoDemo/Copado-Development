/**
 * @description Tests for ShipmentRiskScoringService_copado. Pure in-memory scoring.
 */
@IsTest
private class ShipmentRiskScoringServiceTest_copado {
    private static Route__c route(String severity) {
        Route__c r = (Route__c) LogisticsTestFactory.buildRoute(new Map<String, Object>());
        r.Weather_Severity__c = severity;
        insert r;
        return r;
    }

    private static Equipment__c equipment() {
        Equipment__c e = (Equipment__c) LogisticsTestFactory.buildEquipment(new Map<String, Object>{
            'Truck_ID__c' => 'T' + String.valueOf(Math.abs(Crypto.getRandomInteger())) });
        insert e;
        return e;
    }

    private static Shipment__c ship(Map<String, Object> o) {
        return (Shipment__c) LogisticsTestFactory.buildShipment(o);
    }

    private static Integer score(Shipment__c sh, Route__c r, Equipment__c e) {
        Map<Id, Route__c> rm = r == null ? new Map<Id, Route__c>() : new Map<Id, Route__c>{ r.Id => r };
        Map<Id, Equipment__c> em = e == null ? new Map<Id, Equipment__c>() : new Map<Id, Equipment__c>{ e.Id => e };
        if (r != null) {
            sh.Route__c = r.Id;
        }
        if (e != null) {
            sh.Equipment__c = e.Id;
        }
        ShipmentRiskScoringService_copado.scoreShipments(new List<Shipment__c>{ sh }, rm, em);
        return Integer.valueOf(sh.Risk_Score__c);
    }

    @IsTest
    static void daysFactor() {
        Test.startTest();
        Assert.areEqual(30, score(ship(new Map<String, Object>{ 'Expected_Delivery_Date__c' => Date.today().addDays(1) }), null, null));
        Assert.areEqual(22, score(ship(new Map<String, Object>{ 'Expected_Delivery_Date__c' => Date.today().addDays(3) }), null, null));
        Assert.areEqual(15, score(ship(new Map<String, Object>{ 'Expected_Delivery_Date__c' => Date.today().addDays(7) }), null, null));
        Assert.areEqual(8, score(ship(new Map<String, Object>{ 'Expected_Delivery_Date__c' => Date.today().addDays(14) }), null, null));
        Assert.areEqual(0, score(ship(new Map<String, Object>{ 'Expected_Delivery_Date__c' => Date.today().addDays(30) }), null, null));
        Shipment__c late = ship(new Map<String, Object>{ 'Expected_Delivery_Date__c' => Date.today().addDays(-2) });
        Assert.areEqual(30, score(late, null, null));
        Test.stopTest();
        Assert.isTrue(late.Risk_Factors__c.contains('Past due'));
    }

    @IsTest
    static void weatherFactor() {
        Test.startTest();
        Assert.areEqual(25, score(ship(new Map<String, Object>()), route('Extreme'), null));
        Assert.areEqual(20, score(ship(new Map<String, Object>()), route('Severe'), null));
        Assert.areEqual(15, score(ship(new Map<String, Object>()), route('High'), null));
        Assert.areEqual(10, score(ship(new Map<String, Object>()), route('Moderate'), null));
        Assert.areEqual(5, score(ship(new Map<String, Object>()), route('Unknown'), null));
        Assert.areEqual(0, score(ship(new Map<String, Object>()), route('Low'), null));
        Test.stopTest();
    }

    @IsTest
    static void capacityFactor() {
        Equipment__c e = equipment();
        Test.startTest();
        Assert.areEqual(20, score(ship(new Map<String, Object>{ 'Cargo_Weight_lbs__c' => 20000 }), null, e));
        Assert.areEqual(15, score(ship(new Map<String, Object>{ 'Cargo_Weight_lbs__c' => 18000 }), null, e));
        Assert.areEqual(10, score(ship(new Map<String, Object>{ 'Cargo_Weight_lbs__c' => 15000 }), null, e));
        Assert.areEqual(5, score(ship(new Map<String, Object>{ 'Cargo_Weight_lbs__c' => 10000 }), null, e));
        Assert.areEqual(0, score(ship(new Map<String, Object>{ 'Cargo_Weight_lbs__c' => 1000 }), null, e));
        Test.stopTest();
    }

    @IsTest
    static void cargoAndScheduledFactors() {
        Test.startTest();
        Assert.areEqual(15, score(ship(new Map<String, Object>{ 'Cargo_Type__c' => 'Hazmat' }), null, null));
        Assert.areEqual(10, score(ship(new Map<String, Object>{ 'Cargo_Type__c' => 'Refrigerated' }), null, null));
        Assert.areEqual(0, score(ship(new Map<String, Object>{ 'Cargo_Type__c' => 'General Freight' }), null, null));
        Shipment__c s = ship(new Map<String, Object>{ 'Status__c' => 'Scheduled' });
        Assert.areEqual(10, score(s, null, null));
        Test.stopTest();
        Assert.isTrue(s.Risk_Factors__c.contains('Scheduled without equipment'));
    }

    @IsTest
    static void noFactorsMessage() {
        Shipment__c s = ship(new Map<String, Object>());
        Test.startTest();
        Assert.areEqual(0, score(s, null, null));
        Test.stopTest();
        Assert.areEqual('Low', s.Risk_Level__c);
        Assert.areEqual('No risk factors identified.', s.Risk_Factors__c);
        Assert.isNotNull(s.Risk_Last_Calculated__c);
    }

    @IsTest
    static void levelBoundaries() {
        ShipmentRiskScoringService_copado.Settings cfg = ShipmentRiskScoringService_copado.loadSettings();
        Test.startTest();
        Assert.areEqual('Low', ShipmentRiskScoringService_copado.determineLevel(0, cfg));
        Assert.areEqual('Low', ShipmentRiskScoringService_copado.determineLevel(29, cfg));
        Assert.areEqual('Medium', ShipmentRiskScoringService_copado.determineLevel(30, cfg));
        Assert.areEqual('Medium', ShipmentRiskScoringService_copado.determineLevel(59, cfg));
        Assert.areEqual('High', ShipmentRiskScoringService_copado.determineLevel(60, cfg));
        Assert.areEqual('High', ShipmentRiskScoringService_copado.determineLevel(79, cfg));
        Assert.areEqual('Critical', ShipmentRiskScoringService_copado.determineLevel(80, cfg));
        Assert.areEqual('Critical', ShipmentRiskScoringService_copado.determineLevel(100, cfg));
        Test.stopTest();
    }

    @IsTest
    static void endToEndCriticalAndCapped() {
        Shipment__c s = ship(new Map<String, Object>{
            'Expected_Delivery_Date__c' => Date.today().addDays(1), 'Cargo_Type__c' => 'Hazmat', 'Status__c' => 'Scheduled' });
        Test.startTest();
        Integer total = score(s, route('Extreme'), null);
        Test.stopTest();
        Assert.areEqual(80, total);
        Assert.areEqual('Critical', s.Risk_Level__c);
        Shipment__c capped = ship(new Map<String, Object>{ 'Expected_Delivery_Date__c' => Date.today() });
        ShipmentRiskScoringService_copado.Settings big = new ShipmentRiskScoringService_copado.Settings();
        big.daysWeight = 500;
        ShipmentRiskScoringService_copado.scoreShipments(new List<Shipment__c>{ capped }, null, null, big);
        Assert.areEqual(100, Integer.valueOf(capped.Risk_Score__c));
    }

    @IsTest
    static void deliveredCancelledClearedAndNullSafe() {
        Shipment__c d = ship(new Map<String, Object>{ 'Status__c' => 'Delivered' });
        d.Risk_Score__c = 50;
        d.Risk_Level__c = 'Medium';
        d.Risk_Factors__c = 'x';
        d.Risk_Last_Calculated__c = System.now();
        Shipment__c c = ship(new Map<String, Object>{ 'Status__c' => 'Cancelled' });
        c.Risk_Score__c = 90;
        Test.startTest();
        ShipmentRiskScoringService_copado.scoreShipments(new List<Shipment__c>{ d, c }, null, null);
        ShipmentRiskScoringService_copado.scoreShipments(null, null, null);
        Test.stopTest();
        Assert.isNull(d.Risk_Score__c);
        Assert.isNull(d.Risk_Level__c);
        Assert.isNull(d.Risk_Factors__c);
        Assert.isNull(d.Risk_Last_Calculated__c);
        Assert.isNull(c.Risk_Score__c);
    }

    @IsTest
    static void bulkOf200() {
        Route__c r = route('High');
        List<Shipment__c> list200 = new List<Shipment__c>();
        for (Integer i = 0; i < 200; i++) {
            list200.add(ship(new Map<String, Object>{ 'Route__c' => r.Id, 'Cargo_Type__c' => 'Hazmat' }));
        }
        Test.startTest();
        ShipmentRiskScoringService_copado.scoreShipments(list200, new Map<Id, Route__c>{ r.Id => r }, null);
        Test.stopTest();
        for (Shipment__c s : list200) {
            Assert.areEqual(30, Integer.valueOf(s.Risk_Score__c));
            Assert.areEqual('Medium', s.Risk_Level__c);
        }
    }
}