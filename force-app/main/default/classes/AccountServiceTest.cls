@isTest
private class AccountServiceTest {

    // ─────────────────────────────────────────────────────────────────
    // UNCHANGED — original tests for updateDescription()
    // ─────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────
    // NEW — test for syncContactEmails() (incremental change)
    // ─────────────────────────────────────────────────────────────────

    @isTest
    static void testSyncContactEmails() {
        // Arrange
        Account acc = new Account(Name = 'Acme Corp', Account_Ext_Id__c = 'EXT-003');
        insert acc;

        Contact c = new Contact(
            FirstName = 'Jane',
            LastName  = 'Doe',
            AccountId = acc.Id,
            Email     = 'old@example.com'
        );
        insert c;

        // Act
        Test.startTest();
        AccountService.syncContactEmails(new List<Account>{ acc });
        Test.stopTest();

        // Assert — email should be derived from the account name
        Contact updated = [SELECT Email FROM Contact WHERE Id = :c.Id];
        System.assertEquals(
            'acme.corp@example.com',
            updated.Email,
            'Contact email should be synced from the Account name'
        );
    }
}