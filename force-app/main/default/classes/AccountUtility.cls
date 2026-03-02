public class AccountUtility {
    
    // Get account by ID
    public static Account getAccountById(Id accountId) {
        return [SELECT Id, Name, Phone FROM Account WHERE Id = :accountId LIMIT 1];
    }
    
    // Update account name
    public static void updateAccountName(Id accountId, String newName) {
        Account acc = getAccountById(accountId);
        acc.Name = newName;
        update acc;
    }
}