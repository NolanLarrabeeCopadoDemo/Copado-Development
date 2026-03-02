@isTest
public class AccountUtilityTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAcc = new Account(
            Name = 'Test Account',
            Phone = '555-0100'
        );
        insert testAcc;
    }
    
    @isTest
    static void testGetAccountById() {
        // Given
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // When
        Test.startTest();
        Account result = AccountUtility.getAccountById(acc.Id);
        Test.stopTest();
        
        // Then
        System.assertNotEquals(null, result, 'Account should be retrieved');
        System.assertEquals('Test Account', result.Name, 'Account name should match');
        System.assertEquals('555-0100', result.Phone, 'Phone should match');
    }
    
    @isTest
    static void testUpdateAccountName() {
        // Given
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String newName = 'Updated Account Name';
        
        // When
        Test.startTest();
        AccountUtility.updateAccountName(acc.Id, newName);
        Test.stopTest();
        
        // Then
        Account updatedAcc = [SELECT Name FROM Account WHERE Id = :acc.Id];
        System.assertEquals(newName, updatedAcc.Name, 'Account name should be updated');
    }
}