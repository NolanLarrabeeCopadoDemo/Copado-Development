/**
 * @description Invocable fault logger callable from flow fault connectors. Writes a
 * Flow_Fault_Log__c record and mirrors the error to Logger.
 */
public with sharing class FlowFaultLogger {

    /**
     * @description Input for one fault entry.
     */
    public class LogRequest {
        @InvocableVariable(label='Flow Name' required=true)
        public String flowName;
        @InvocableVariable(label='Element Name')
        public String elementName;
        @InvocableVariable(label='Record Id')
        public String recordId;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    /**
     * @description Logs all fault requests in a single bulk-safe DML.
     * @param requests the fault entries to log
     */
    @InvocableMethod(label='Log Flow Fault' description='Writes flow fault details to Flow_Fault_Log__c')
    public static void logFaults(List<LogRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        List<Flow_Fault_Log__c> logs = new List<Flow_Fault_Log__c>();
        for (LogRequest req : requests) {
            Logger.error(req.flowName + '.' + req.elementName, req.errorMessage);
            logs.add(new Flow_Fault_Log__c(
                Flow_Name__c = req.flowName,
                Element_Name__c = req.elementName,
                Record_Id__c = req.recordId,
                Error_Message__c = req.errorMessage
            ));
        }
        try {
            insert logs;
        } catch (DmlException ex) {
            Logger.error('FlowFaultLogger', ex);
        }
    }
}