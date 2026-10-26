/**
 * @description Tests for the Shipment risk trigger and ShipmentRiskTriggerHandler_copado.
 */
@IsTest
private class ShipmentRiskTriggerHandlerTest_copado {
    @IsTest
    static void insertPopulatesRiskFields() {
        Route__c r = (Route__c) LogisticsTestFactory.buildRoute(new Map<String, Object>());
        r.Weather_Severity__c = 'Extreme';
        insert r;
        Equipment__c e = (Equipment__c) LogisticsTestFactory.buildEquipment(new Map<String, Object>{
            'Truck_ID__c' => 'T' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            'Hazmat_Certified__c' => true });
        insert e;
        Shipment__c s = (Shipment__c) LogisticsTestFactory.buildShipment(new Map<String, Object>{
            'Route__c' => r.Id, 'Equipment__c' => e.Id, 'Cargo_Type__c' => 'Hazmat',
            'Expected_Delivery_Date__c' => Date.today().addDays(1), 'Cargo_Weight_lbs__c' => 20000 });
        Test.startTest();
        insert s;
        Test.stopTest();
        Shipment__c res = [SELECT Risk_Score__c, Risk_Level__c, Risk_Factors__c, Risk_Last_Calculated__c FROM Shipment__c WHERE Id = :s.Id];
        Assert.areEqual(90, Integer.valueOf(res.Risk_Score__c));
        Assert.areEqual('Critical', res.Risk_Level__c);
        Assert.isNotNull(res.Risk_Factors__c);
        Assert.isNotNull(res.Risk_Last_Calculated__c);
    }

    @IsTest
    static void updateRecalculates() {
        Shipment__c s = (Shipment__c) LogisticsTestFactory.buildShipment(new Map<String, Object>());
        insert s;
        Assert.areEqual(0, Integer.valueOf([SELECT Risk_Score__c FROM Shipment__c WHERE Id = :s.Id].Risk_Score__c));
        Test.startTest();
        s.Cargo_Type__c = 'Hazmat';
        update s;
        Test.stopTest();
        Assert.areEqual(15, Integer.valueOf([SELECT Risk_Score__c FROM Shipment__c WHERE Id = :s.Id].Risk_Score__c));
    }

    @IsTest
    static void blankRouteAndEquipment() {
        Shipment__c s = (Shipment__c) LogisticsTestFactory.buildShipment(new Map<String, Object>{ 'Status__c' => 'Scheduled' });
        Test.startTest();
        insert s;
        Test.stopTest();
        Shipment__c res = [SELECT Risk_Score__c, Risk_Level__c FROM Shipment__c WHERE Id = :s.Id];
        Assert.areEqual(10, Integer.valueOf(res.Risk_Score__c));
        Assert.areEqual('Low', res.Risk_Level__c);
    }

    @IsTest
    static void deliveredAndCancelledCleared() {
        Shipment__c open = (Shipment__c) LogisticsTestFactory.buildShipment(new Map<String, Object>{ 'Cargo_Type__c' => 'Hazmat' });
        insert open;
        Test.startTest();
        open.Status__c = 'Cancelled';
        update open;
        Shipment__c del = (Shipment__c) LogisticsTestFactory.buildShipment(new Map<String, Object>{ 'Status__c' => 'Delivered' });
        insert del;
        Test.stopTest();
        Shipment__c a = [SELECT Risk_Score__c, Risk_Level__c, Risk_Factors__c, Risk_Last_Calculated__c FROM Shipment__c WHERE Id = :open.Id];
        Shipment__c b = [SELECT Risk_Score__c, Risk_Level__c, Risk_Factors__c, Risk_Last_Calculated__c FROM Shipment__c WHERE Id = :del.Id];
        Assert.isNull(a.Risk_Score__c);
        Assert.isNull(a.Risk_Level__c);
        Assert.isNull(a.Risk_Factors__c);
        Assert.isNull(a.Risk_Last_Calculated__c);
        Assert.isNull(b.Risk_Score__c);
        Assert.isNull(b.Risk_Last_Calculated__c);
    }

    @IsTest
    static void bulkInsert200() {
        Route__c r = (Route__c) LogisticsTestFactory.buildRoute(new Map<String, Object>());
        r.Weather_Severity__c = 'Severe';
        insert r;
        List<Shipment__c> list200 = new List<Shipment__c>();
        for (Integer i = 0; i < 200; i++) {
            list200.add((Shipment__c) LogisticsTestFactory.buildShipment(new Map<String, Object>{ 'Route__c' => r.Id }));
        }
        Test.startTest();
        insert list200;
        Test.stopTest();
        Assert.areEqual(200, [SELECT COUNT() FROM Shipment__c WHERE Risk_Score__c = 20 AND Risk_Level__c = 'Low']);
    }

    @IsTest
    static void scoringFailureDoesNotBlockSave() {
        ShipmentRiskTriggerHandler_copado.forceFailure = true;
        Shipment__c s = (Shipment__c) LogisticsTestFactory.buildShipment(new Map<String, Object>{ 'Cargo_Type__c' => 'Hazmat' });
        Test.startTest();
        insert s;
        Test.stopTest();
        Shipment__c res = [SELECT Risk_Score__c FROM Shipment__c WHERE Id = :s.Id];
        Assert.isNull(res.Risk_Score__c);
    }

    @IsTest
    static void skipAndEmptyInputs() {
        ShipmentRiskTriggerHandler_copado.skipScoring = true;
        Shipment__c s = (Shipment__c) LogisticsTestFactory.buildShipment(new Map<String, Object>{ 'Cargo_Type__c' => 'Hazmat' });
        insert s;
        Assert.isNull([SELECT Risk_Score__c FROM Shipment__c WHERE Id = :s.Id].Risk_Score__c);
        ShipmentRiskTriggerHandler_copado.skipScoring = false;
        ShipmentRiskTriggerHandler_copado.handleBeforeSave(null);
        ShipmentRiskTriggerHandler_copado.handleBeforeSave(new List<Shipment__c>());
        Assert.isTrue(ShipmentRiskTriggerHandler_copado.loadRoutes(null).isEmpty());
        Assert.isTrue(ShipmentRiskTriggerHandler_copado.loadEquipment(new Set<Id>()).isEmpty());
    }
}