public with sharing class AccountService {
    
    public static void updateDescription(Account acc) {
        System.debug('Updating account: ' + acc.Name);
        acc.Description = 'Updated by service';
    }
}