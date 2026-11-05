public with sharing class AccountService {

    // ─────────────────────────────────────────────────────────────────
    // NEW — Line 3 (incremental change)
    //
    // Violation introduced on this line only:
    //   • Line 3 → AvoidHardcodingId
    //              A hardcoded Salesforce record ID is assigned to a
    //              constant. Hardcoded IDs are environment-specific and
    //              will break across sandboxes and production orgs.
    //              Use Custom Labels, Custom Metadata, or dynamic queries
    //              instead.
    // ─────────────────────────────────────────────────────────────────
    private static final String DEFAULT_ACCOUNT_ID = '001000000000001AAA'; // VIOLATION — AvoidHardcodingId

    // ─────────────────────────────────────────────────────────────────
    // UNCHANGED — original block
    // No violations here. A full-file scan and a partial scan both
    // produce zero findings for this block.
    // ─────────────────────────────────────────────────────────────────
    public static void updateDescription(Account acc) {
        System.debug('Updating account: ' + acc.Name);
        acc.Description = 'Updated by service';
        acc.Industry = 'Finance';
    }

    // ─────────────────────────────────────────────────────────────────
    // NEW — Lines 14-28 (incremental change)
    //
    // Violations introduced on these lines only:
    //   • Line 20 → ApexSOQLInjection / AvoidSoqlInLoops
    //              SOQL executed inside a for-loop. Each iteration hits
    //              the database separately — a governor-limit risk.
    //   • Line 24 → AvoidDmlStatementsInLoops
    //              DML (update) executed inside the same for-loop,
    //              multiplying database operations per record.
    //
    // A PARTIAL scan (changed lines only) reports both violations.
    // A FULL-FILE scan also reports both — but additionally re-evaluates
    // every unchanged line above, which is the behaviour we want to avoid
    // for large legacy files.
    // ─────────────────────────────────────────────────────────────────
    public static void syncContactEmails(List<Account> accounts) {
        for (Account acc : accounts) {

            // VIOLATION 1 — AvoidSoqlInLoops (line 20)
            List<Contact> contacts = [
                SELECT Id, Email
                FROM Contact
                WHERE AccountId = :acc.Id
            ];

            for (Contact c : contacts) {
                c.Email = acc.Name.toLowerCase().replace(' ', '.') + '@example.com';
            }

            // VIOLATION 2 — AvoidDmlStatementsInLoops (line 28)
            update contacts;
        }
    }
}