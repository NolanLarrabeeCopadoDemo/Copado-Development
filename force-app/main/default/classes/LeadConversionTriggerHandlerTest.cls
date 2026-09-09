@isTest
private class LeadConversionTriggerHandlerTest {

    @isTest
    static void testLeadConversionInsertWithValues() {
        Test.startTest();
        Lead ld = new Lead(LastName = 'Test', Company = 'Acme', LeadSource = 'Web');
        insert ld;
        Test.stopTest();

        Lead inserted = [SELECT Id, LeadSource, Company FROM Lead WHERE Id = :ld.Id];
        System.assertEquals('Web', inserted.LeadSource, 'LeadSource should be preserved for non-null insert');
        System.assertEquals('Acme', inserted.Company, 'Company should be preserved for non-null insert');
    }

    @isTest
    static void testLeadConversionNullFields() {
        // Exercise the trigger via DML for the null LeadSource scenario (Company is a
        // required field on Lead, so it can never be null through DML; the handler's
        // Company null-guard is exercised directly below by invoking the handler with
        // an in-memory Lead that was never inserted).
        Test.startTest();
        Lead leadInsert = new Lead(LastName = 'NullInsertTest', Company = 'TempInsertCo', LeadSource = null);
        insert leadInsert;

        Lead leadUpdate = new Lead(LastName = 'NullUpdateTest', Company = 'TempUpdateCo', LeadSource = 'Web');
        insert leadUpdate;
        leadUpdate.LeadSource = null;
        update leadUpdate;

        // Directly exercise the Company null-guard (defensive coding path) without DML,
        // since Company is a required field and cannot be persisted as null.
        Lead inMemoryLead = new Lead(LastName = 'InMemoryNullCompany', LeadSource = 'Web');
        LeadConversionTriggerHandler.handleBeforeInsert(new List<Lead>{ inMemoryLead });
        LeadConversionTriggerHandler.handleBeforeUpdate(new List<Lead>{ inMemoryLead });
        Test.stopTest();

        Lead insertedResult = [SELECT Id, LeadSource FROM Lead WHERE Id = :leadInsert.Id];
        System.assertEquals(null, insertedResult.LeadSource, 'Null LeadSource on insert should not throw and should remain null');

        Lead updatedResult = [SELECT Id, LeadSource FROM Lead WHERE Id = :leadUpdate.Id];
        System.assertEquals(null, updatedResult.LeadSource, 'Null LeadSource on update should not throw and should remain null');
    }
}