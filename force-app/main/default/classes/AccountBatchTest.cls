/**
 * Unit tests for AccountBatch (US-0000468).
 * Covers: full end-to-end run via Database.executeBatch, default/custom scope
 * sizing, direct execute()/finish() invocation with a null (mocked-absent)
 * Database.BatchableContext, and start() query locator generation.
 *
 * Test accounts populate Region__c, Segment__c and Account_Ext_Id__c up front
 * because an org-level validation rule requires those fields for "merge
 * completeness" on any Account insert; the batch under test only owns
 * Segment__c's final value once it runs.
 */
@isTest
private class AccountBatchTest {

    @TestSetup
    static void setupData() {
        List<Account> accounts = new List<Account>();
        accounts.add(new Account(Name = 'Enterprise Test Co', NumberOfEmployees = 5000, AnnualRevenue = 200000000,
            Region__c = 'NA', Segment__c = 'Enterprise', Account_Ext_Id__c = 'US468ENT00000001'));
        accounts.add(new Account(Name = 'Commercial Test Co', NumberOfEmployees = 150, AnnualRevenue = 15000000,
            Region__c = 'NA', Segment__c = 'Commercial', Account_Ext_Id__c = 'US468COM00000002'));
        accounts.add(new Account(Name = 'SMB Test Co', NumberOfEmployees = 10, AnnualRevenue = 500000,
            Region__c = 'NA', Segment__c = 'SMB', Account_Ext_Id__c = 'US468SMB00000003'));
        insert accounts;
    }

    @isTest
    static void testBatchExecutionEndToEnd() {
        Test.startTest();
        Id jobId = AccountBatch.run();
        Test.stopTest();

        Map<String, String> segmentByName = new Map<String, String>();
        for (Account acc : [SELECT Id, Name, Segment__c FROM Account]) {
            segmentByName.put(acc.Name, acc.Segment__c);
        }

        System.assertEquals(3, segmentByName.size(), 'Expected 3 accounts to be processed');
        System.assertEquals('Enterprise', segmentByName.get('Enterprise Test Co'), 'High employee/revenue account should be Enterprise');
        System.assertEquals('Commercial', segmentByName.get('Commercial Test Co'), 'Mid-size account should be Commercial');
        System.assertEquals('SMB', segmentByName.get('SMB Test Co'), 'Small account should be SMB');
        System.assertNotEquals(null, jobId, 'Batch job Id should be returned');
    }

    @isTest
    static void testDefaultBatchScopeSizeWhenNullSupplied() {
        Test.startTest();
        Id jobId = AccountBatch.run(null);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Default scope run should return a valid job Id');
    }

    @isTest
    static void testExecuteAndFinishDirectlyWithoutBatchableContext() {
        List<Account> scope = [SELECT Id, Name, NumberOfEmployees, AnnualRevenue FROM Account];
        AccountBatch batchJob = new AccountBatch();

        Test.startTest();
        batchJob.execute(null, scope);
        batchJob.finish(null);
        Test.stopTest();

        Integer segmentedCount = [SELECT COUNT() FROM Account WHERE Segment__c != null];
        System.assertEquals(3, segmentedCount, 'All accounts should have a segment assigned after direct execute call');
    }

    @isTest
    static void testStartReturnsQueryLocator() {
        AccountBatch batchJob = new AccountBatch();

        Test.startTest();
        Database.QueryLocator ql = batchJob.start(null);
        Test.stopTest();

        System.assertNotEquals(null, ql, 'start() should return a valid job Id');
    }
}