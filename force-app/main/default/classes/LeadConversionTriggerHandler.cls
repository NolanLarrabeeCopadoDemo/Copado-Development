public class LeadConversionTriggerHandler {

    public static void handleBeforeInsert(List<Lead> newLeads) {
        for (Lead ld : newLeads) {
            processLead(ld);
        }
    }

    public static void handleBeforeUpdate(List<Lead> newLeads) {
        for (Lead ld : newLeads) {
            processLead(ld);
        }
    }

    private static void processLead(Lead ld) {
        String normalizedLeadSource;
        if (ld.LeadSource == null) {
            System.debug(LoggingLevel.WARN, 'LeadConversionTriggerHandler: Null LeadSource detected on Lead (Id=' + ld.Id + '). Skipping LeadSource normalization to avoid NullPointerException.');
        } else {
            normalizedLeadSource = ld.LeadSource.toLowerCase();
        }

        String normalizedCompany;
        if (ld.Company == null) {
            System.debug(LoggingLevel.WARN, 'LeadConversionTriggerHandler: Null Company detected on Lead (Id=' + ld.Id + '). Skipping Company normalization to avoid NullPointerException.');
        } else {
            normalizedCompany = ld.Company.toLowerCase();
        }
    }
}