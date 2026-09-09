/**
 * Nightly Account sync batch job.
 * Refactored to fix heap size limit exceptions (US-0000468) by:
 *  - Querying only fields actually used in execute() logic.
 *  - Processing each chunk statelessly (no cross-execute collections retained;
 *    batch Apex is stateless by default, so no Database.Stateful marker is used).
 *  - Using a Map<Id, Account> keyed lookup instead of holding full lists in state.
 *  - Exposing a configurable batch scope, defaulted to 200.
 *  - Logging failures via Logger.error() instead of letting exceptions surface.
 */
public with sharing class AccountBatch implements Database.Batchable<SObject> {

    /** Default Database.executeBatch() scope size when none is supplied. */
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    /**
     * Runs the batch using the default scope size (200).
     * @return the AsyncApexJob Id of the submitted batch.
     */
    public static Id run() {
        return run(DEFAULT_BATCH_SIZE);
    }

    /**
     * Runs the batch with a caller-supplied scope size.
     * @param batchSize desired scope size; falls back to DEFAULT_BATCH_SIZE when null or non-positive.
     * @return the AsyncApexJob Id of the submitted batch.
     */
    public static Id run(Integer batchSize) {
        Integer scopeSize = (batchSize == null || batchSize <= 0) ? DEFAULT_BATCH_SIZE : batchSize;
        return Database.executeBatch(new AccountBatch(), scopeSize);
    }

    /**
     * Selective-field query: only Id, Name, NumberOfEmployees and AnnualRevenue are
     * used by execute(), so no other Account fields are retrieved.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, NumberOfEmployees, AnnualRevenue
            FROM Account
        ]);
    }

    /**
     * Stateless per-batch processing. Builds a Map<Id, Account> for the current
     * chunk only (nothing persisted across execute() calls) and applies the
     * segmentation update via a single DML statement.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            Map<Id, Account> accountsById = new Map<Id, Account>();
            for (SObject record : scope) {
                Account acc = (Account) record;
                accountsById.put(acc.Id, acc);
            }

            List<Account> updates = new List<Account>();
            for (Account acc : accountsById.values()) {
                String segment = resolveSegment(acc.NumberOfEmployees, acc.AnnualRevenue);
                if (segment != null) {
                    updates.add(new Account(Id = acc.Id, Segment__c = segment));
                }
            }

            if (!updates.isEmpty()) {
                List<Database.SaveResult> results = Database.update(updates, false);
                logFailures(results, updates, accountsById);
            }
        } catch (Exception ex) {
            Logger.error('AccountBatch.execute', ex);
        }
    }

    /**
     * Checks the completed AsyncApexJob for errors and logs a summary if any
     * records failed. Guards against a null context so it can be unit tested
     * with a mocked/absent Database.BatchableContext.
     */
    public void finish(Database.BatchableContext bc) {
        try {
            if (bc == null) {
                return;
            }
            List<AsyncApexJob> jobs = [
                SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
                FROM AsyncApexJob
                WHERE Id = :bc.getJobId()
            ];
            if (!jobs.isEmpty() && jobs[0].NumberOfErrors > 0) {
                Logger.error('AccountBatch.finish', 'Batch completed with ' + jobs[0].NumberOfErrors
                    + ' error(s). JobId: ' + jobs[0].Id);
            }
        } catch (Exception ex) {
            Logger.error('AccountBatch.finish', ex);
        }
    }

    /** Logs any failed DML results with the related Account Id/Name for traceability. */
    private void logFailures(List<Database.SaveResult> results, List<Account> updates, Map<Id, Account> accountsById) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                Account source = accountsById.get(updates[i].Id);
                String accName = source == null ? 'Unknown' : source.Name;
                for (Database.Error err : results[i].getErrors()) {
                    Logger.error('AccountBatch.execute', 'Account ' + updates[i].Id + ' (' + accName + '): ' + err.getMessage());
                }
            }
        }
    }

    /** Derives the Segment__c value from employee count and annual revenue thresholds. */
    private String resolveSegment(Decimal numberOfEmployees, Decimal annualRevenue) {
        Decimal employees = numberOfEmployees == null ? 0 : numberOfEmployees;
        Decimal revenue = annualRevenue == null ? 0 : annualRevenue;

        if (employees >= 1000 || revenue >= 100000000) {
            return 'Enterprise';
        }
        if (employees >= 100 || revenue >= 10000000) {
            return 'Commercial';
        }
        return 'SMB';
    }
}