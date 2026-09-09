public with sharing class AccountService {

    private static final String DEFAULT_ONBOARDING_MESSAGE = 'Thank you for choosing us. Your account is being onboarded and additional details will follow shortly.';

    public static void updateDescription(Account acc) {
        System.debug('Updating account: ' + acc.Name);
        acc.Description = 'Updated by service';
        acc.Industry = 'Finance';
    }

    public static void enrichAccount(List<Account> accounts) {
        enrichAccount(accounts, null);
    }

    public static void enrichAccount(List<Account> accounts, Map<Id, Account> oldMap) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }

        try {
            for (Account acc : accounts) {
                if (String.isBlank(acc.Description)) {
                    acc.Description = DEFAULT_ONBOARDING_MESSAGE;
                    System.debug(LoggingLevel.DEBUG,
                        'AccountService.enrichAccount: populated onboarding Description for account ' + acc.Name);
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'AccountService.enrichAccount: error enriching accounts - ' + ex.getMessage());
        }
    }

    public static void detectDuplicates(List<Account> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }

        try {
            Set<String> nameSet = new Set<String>();
            for (Account acc : accounts) {
                if (String.isNotBlank(acc.Name)) {
                    nameSet.add(acc.Name);
                }
            }

            if (nameSet.isEmpty()) {
                return;
            }

            Map<String, Account> existingAccountsByName = new Map<String, Account>();
            for (Account existing : [SELECT Id, Name FROM Account WHERE Name IN :nameSet]) {
                existingAccountsByName.put(existing.Name, existing);
            }

            for (Account acc : accounts) {
                if (String.isBlank(acc.Name)) {
                    continue;
                }
                Account matched = existingAccountsByName.get(acc.Name);
                if (matched != null && matched.Id != acc.Id) {
                    acc.Duplicate_Flag__c = true;
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'AccountService.detectDuplicates: error detecting duplicates - ' + ex.getMessage());
        }
    }
}