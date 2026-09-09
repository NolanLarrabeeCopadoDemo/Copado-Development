@isTest
private class AccountServiceTest {

    @TestSetup
    static void setup() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Setup Account 1', Account_Ext_Id__c = 'EXT-SETUP-001'),
            new Account(Name = 'Setup Account 2', Account_Ext_Id__c = 'EXT-SETUP-002', Description = 'Pre-existing description')
        };
        insert accounts;
    }

    @isTest
    static void testUpdateDescription() {
        Account acc = new Account(Name = 'Test Account', Account_Ext_Id__c = 'EXT-001');
        insert acc;

        Test.startTest();
        AccountService.updateDescription(acc);
        Test.stopTest();

        System.assertEquals('Updated by service', acc.Description,
            'Description should be updated by AccountService.updateDescription()');
    }

    @isTest
    static void testUpdateDescriptionName() {
        Account acc = new Account(Name = 'Another Account', Account_Ext_Id__c = 'EXT-002');
        insert acc;

        Test.startTest();
        AccountService.updateDescription(acc);
        Test.stopTest();

        System.assertEquals('Updated by service', acc.Description,
            'Description should always be set to "Updated by service"');
        System.assertEquals('Another Account', acc.Name,
            'Account Name should remain unchanged after updateDescription()');
    }

    @isTest
    static void testEnrichAccount_InsertScenario_BlankDescriptionPopulated() {
        Account acc = new Account(Name = 'Insert Enrich Account', Account_Ext_Id__c = 'EXT-101');

        Test.startTest();
        List<Account> accounts = new List<Account>{ acc };
        AccountService.enrichAccount(accounts);
        insert accounts;
        Test.stopTest();

        Account result = [SELECT Id, Description FROM Account WHERE Id = :acc.Id];
        System.assert(String.isNotBlank(result.Description),
            'Description should be populated with onboarding message on insert');
    }

    @isTest
    static void testEnrichAccount_InsertScenario_ExistingDescriptionNotOverwritten() {
        Account acc = new Account(Name = 'Insert Enrich Account 2', Account_Ext_Id__c = 'EXT-102',
            Description = 'Custom description already set');

        Test.startTest();
        List<Account> accounts = new List<Account>{ acc };
        AccountService.enrichAccount(accounts);
        insert accounts;
        Test.stopTest();

        Account result = [SELECT Id, Description FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Custom description already set', result.Description,
            'Existing Description should not be overwritten');
    }

    @isTest
    static void testEnrichAccount_UpdateScenario_BlankDescriptionPopulated() {
        Account acc = [SELECT Id, Name, Description FROM Account WHERE Account_Ext_Id__c = 'EXT-SETUP-001' LIMIT 1];
        Map<Id, Account> oldMap = new Map<Id, Account>{ acc.Id => acc.clone(true, true, true, true) };

        Test.startTest();
        List<Account> accounts = new List<Account>{ acc };
        AccountService.enrichAccount(accounts, oldMap);
        update accounts;
        Test.stopTest();

        Account result = [SELECT Id, Description FROM Account WHERE Id = :acc.Id];
        System.assert(String.isNotBlank(result.Description),
            'Description should be populated with onboarding message on update when blank');
    }

    @isTest
    static void testEnrichAccount_UpdateScenario_ExistingDescriptionUnchanged() {
        Account acc = [SELECT Id, Name, Description FROM Account WHERE Account_Ext_Id__c = 'EXT-SETUP-002' LIMIT 1];
        Map<Id, Account> oldMap = new Map<Id, Account>{ acc.Id => acc.clone(true, true, true, true) };

        Test.startTest();
        List<Account> accounts = new List<Account>{ acc };
        AccountService.enrichAccount(accounts, oldMap);
        update accounts;
        Test.stopTest();

        Account result = [SELECT Id, Description FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Pre-existing description', result.Description,
            'Existing non-blank Description should remain unchanged');
    }

    @isTest
    static void testEnrichAccount_BulkInsertScenario() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(Name = 'Bulk Account ' + i, Account_Ext_Id__c = 'EXT-BULK-' + i));
        }

        Test.startTest();
        AccountService.enrichAccount(accounts);
        insert accounts;
        Test.stopTest();

        List<Account> results = [SELECT Id, Description FROM Account WHERE Id IN :accounts];
        for (Account result : results) {
            System.assert(String.isNotBlank(result.Description),
                'All bulk-inserted accounts should have a populated Description');
        }
    }

    @isTest
    static void testEnrichAccount_NullAndEmptyListHandledGracefully() {
        Test.startTest();
        AccountService.enrichAccount(null);
        AccountService.enrichAccount(new List<Account>());
        Test.stopTest();

        System.assert(true, 'No exception should be thrown for null or empty list input');
    }

    @isTest
    static void testDetectDuplicates_MatchFlagsExistingNameDuplicate() {
        Account existing = [SELECT Id, Name FROM Account WHERE Account_Ext_Id__c = 'EXT-SETUP-001' LIMIT 1];

        Account newAcc = new Account(Name = existing.Name, Account_Ext_Id__c = 'EXT-DUP-001');

        Test.startTest();
        List<Account> accounts = new List<Account>{ newAcc };
        AccountService.detectDuplicates(accounts);
        insert accounts;
        Test.stopTest();

        Account result = [SELECT Id, Duplicate_Flag__c FROM Account WHERE Id = :newAcc.Id];
        System.assertEquals(true, result.Duplicate_Flag__c,
            'Account with a Name matching an existing Account should be flagged as duplicate');
    }

    @isTest
    static void testDetectDuplicates_NoMatchDoesNotFlag() {
        Account newAcc = new Account(Name = 'Completely Unique Name 12345', Account_Ext_Id__c = 'EXT-DUP-002');

        Test.startTest();
        List<Account> accounts = new List<Account>{ newAcc };
        AccountService.detectDuplicates(accounts);
        insert accounts;
        Test.stopTest();

        Account result = [SELECT Id, Duplicate_Flag__c FROM Account WHERE Id = :newAcc.Id];
        System.assertEquals(false, result.Duplicate_Flag__c,
            'Account with a unique Name should not be flagged as duplicate');
    }

    @isTest
    static void testDetectDuplicates_BulkifiedSingleQueryNoLoopSoql() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(Name = 'Setup Account 1', Account_Ext_Id__c = 'EXT-DUP-BULK-' + i));
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        AccountService.detectDuplicates(accounts);
        Integer queriesAfter = Limits.getQueries();
        insert accounts;
        Test.stopTest();

        System.assertEquals(1, queriesAfter - queriesBefore,
            'detectDuplicates should execute exactly one bulkified SOQL query regardless of list size');

        List<Account> results = [SELECT Id, Duplicate_Flag__c FROM Account WHERE Id IN :accounts];
        for (Account result : results) {
            System.assertEquals(true, result.Duplicate_Flag__c,
                'All bulk-inserted accounts sharing an existing Name should be flagged as duplicate');
        }
    }

    @isTest
    static void testDetectDuplicates_NullAndEmptyListHandledGracefully() {
        Test.startTest();
        AccountService.detectDuplicates(null);
        AccountService.detectDuplicates(new List<Account>());
        Test.stopTest();

        System.assert(true, 'No exception should be thrown for null or empty list input');
    }

    @isTest
    static void testDetectDuplicates_BlankNameSkipped() {
        Account acc = new Account(Name = 'Blank Name Test', Account_Ext_Id__c = 'EXT-DUP-003');
        insert acc;
        acc.Name = null;

        Test.startTest();
        AccountService.detectDuplicates(new List<Account>{ acc });
        Test.stopTest();

        System.assertEquals(false, acc.Duplicate_Flag__c,
            'Account with blank Name should be skipped and not flagged');
    }
}