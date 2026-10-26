/**
 * @description Tests for FlowFaultLogger.
 */
@IsTest
private class FlowFaultLoggerTest {

    private static FlowFaultLogger.LogRequest build(Integer i) {
        FlowFaultLogger.LogRequest r = new FlowFaultLogger.LogRequest();
        r.flowName = 'Outage_Tracker_Flow';
        r.elementName = 'Element' + i;
        r.recordId = '001000000000000AAA';
        r.errorMessage = 'Error ' + i;
        return r;
    }

    @IsTest
    static void logsSingleFault() {
        Test.startTest();
        FlowFaultLogger.logFaults(new List<FlowFaultLogger.LogRequest>{ build(1) });
        Test.stopTest();
        List<Flow_Fault_Log__c> logs = [SELECT Flow_Name__c, Error_Message__c FROM Flow_Fault_Log__c];
        Assert.areEqual(1, logs.size(), 'One log expected');
        Assert.areEqual('Error 1', logs[0].Error_Message__c, 'Message stored');
    }

    @IsTest
    static void logsBulkFaults() {
        List<FlowFaultLogger.LogRequest> reqs = new List<FlowFaultLogger.LogRequest>();
        for (Integer i = 0; i < 200; i++) {
            reqs.add(build(i));
        }
        Test.startTest();
        FlowFaultLogger.logFaults(reqs);
        Test.stopTest();
        Assert.areEqual(200, [SELECT COUNT() FROM Flow_Fault_Log__c], '200 logs expected');
    }

    @IsTest
    static void handlesEmptyAndNullInput() {
        Test.startTest();
        FlowFaultLogger.logFaults(null);
        FlowFaultLogger.logFaults(new List<FlowFaultLogger.LogRequest>());
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Flow_Fault_Log__c], 'No logs expected');
    }

    @IsTest
    static void survivesDmlFailure() {
        FlowFaultLogger.LogRequest r = build(1);
        r.recordId = '123456789012345678901234567890';
        Test.startTest();
        FlowFaultLogger.logFaults(new List<FlowFaultLogger.LogRequest>{ r });
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Flow_Fault_Log__c], 'Insert failed gracefully');
    }
}