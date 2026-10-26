/**
 * @description Tests for ShipmentRiskScoringBatch_copado.
 */
@IsTest
private class ShipmentRiskScoringBatchTest_copado {
    private static List<Shipment__c> seed(Integer n, String status) {
        ShipmentRiskTriggerHandler_copado.skipScoring = true;
        List<Shipment__c> list1 = new List<Shipment__c>();
        for (Integer i = 0; i < n; i++) {
            list1.add((Shipment__c) LogisticsTestFactory.buildShipment(new Map<String, Object>{
                'Status__c' => status, 'Cargo_Type__c' => 'Hazmat' }));
        }
        insert list1;
        ShipmentRiskTriggerHandler_copado.skipScoring = false;
        return list1;
    }

    @IsTest
    static void batchScoresOpenShipmentsOnly() {
        List<Shipment__c> open = seed(5, 'Draft');
        List<Shipment__c> closed = seed(2, 'Delivered');
        Test.startTest();
        Database.executeBatch(new ShipmentRiskScoringBatch_copado(), ShipmentRiskScoringBatch_copado.SCOPE_SIZE);
        Test.stopTest();
        Assert.areEqual(5, [SELECT COUNT() FROM Shipment__c WHERE Id IN :open AND Risk_Score__c = 15 AND Risk_Last_Calculated__c != null]);
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WHERE Id IN :closed AND Risk_Score__c != null]);
    }

    @IsTest
    static void batchBulk200() {
        List<Shipment__c> open = seed(200, 'Draft');
        Test.startTest();
        Database.executeBatch(new ShipmentRiskScoringBatch_copado(), ShipmentRiskScoringBatch_copado.SCOPE_SIZE);
        Test.stopTest();
        Assert.areEqual(200, [SELECT COUNT() FROM Shipment__c WHERE Id IN :open AND Risk_Score__c = 15]);
    }

    @IsTest
    static void batchFailureIsLoggedNotThrown() {
        List<Shipment__c> open = seed(3, 'Draft');
        ShipmentRiskScoringBatch_copado.forceFailure = true;
        ShipmentRiskScoringBatch_copado b = new ShipmentRiskScoringBatch_copado();
        Test.startTest();
        Database.executeBatch(b, 200);
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WHERE Id IN :open AND Risk_Score__c != null]);
    }

    @IsTest
    static void directExecuteCountsFailures() {
        List<Shipment__c> open = seed(2, 'Draft');
        ShipmentRiskScoringBatch_copado.forceFailure = true;
        ShipmentRiskScoringBatch_copado b = new ShipmentRiskScoringBatch_copado();
        Test.startTest();
        b.execute(null, open);
        Test.stopTest();
        Assert.areEqual(2, b.failureCount);
    }

    @IsTest
    static void schedulableRuns() {
        seed(1, 'Draft');
        Test.startTest();
        String jobId = System.schedule('ShipmentRiskScoringBatchTest_copado', '0 0 2 * * ?', new ShipmentRiskScoringBatch_copado());
        Test.stopTest();
        Assert.isNotNull(jobId);
        Assert.areEqual(1, [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId]);
    }
}