@isTest
private class AccountServiceTest {

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
}