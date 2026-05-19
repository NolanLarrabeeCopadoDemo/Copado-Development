public with sharing class AccountService {
    
    public static void updateDescription(Account acc) {
        acc.Description = 'Updated by service';
        acc.Industry = 'Finance';
    }
}