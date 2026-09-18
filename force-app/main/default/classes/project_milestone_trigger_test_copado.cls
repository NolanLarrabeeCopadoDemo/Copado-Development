/**
 * Test class for project_milestone_trigger_copado / project_milestone_handler_copado.
 * Uses a Data Factory pattern (TestDataFactory inner class) since no shared
 * DataFactory utility currently exists in the org. Covers positive, negative
 * and bulk (200+) scenarios.
 */
@IsTest
private class project_milestone_trigger_test_copado {

    /**
     * Inner Data Factory responsible for building Project_Milestone__c test
     * records with sensible defaults that callers can override per scenario.
     */
    private class TestDataFactory {
        Integer sequence = 0;

        Project_Milestone__c buildMilestone(Decimal completionPercentage, String status) {
            sequence++;
            Project_Milestone__c milestone = new Project_Milestone__c(
                Milestone_Name__c = 'Milestone ' + sequence,
                Due_Date__c = Date.today().addDays(30),
                Status__c = status,
                Completion_Percentage__c = completionPercentage
            );
            return milestone;
        }

        List<Project_Milestone__c> buildMilestones(Integer count, Decimal completionPercentage, String status) {
            List<Project_Milestone__c> milestones = new List<Project_Milestone__c>();
            for (Integer i = 0; i < count; i++) {
                milestones.add(buildMilestone(completionPercentage, status));
            }
            return milestones;
        }
    }

    @IsTest
    static void testPositiveSingleMilestoneReachesCompletion() {
        TestDataFactory factory = new TestDataFactory();
        Project_Milestone__c milestone = factory.buildMilestone(50, 'In Progress');

        Test.startTest();
        insert milestone;
        milestone.Completion_Percentage__c = 100;
        milestone.Status__c = 'Completed';
        update milestone;
        Test.stopTest();

        Project_Milestone__c result = [
            SELECT Status__c, Completion_Percentage__c
            FROM Project_Milestone__c
            WHERE Id = :milestone.Id
        ];
        System.assertEquals(100, result.Completion_Percentage__c, 'Completion percentage should be 100.');
        System.assertEquals('Completed', result.Status__c, 'Status should be Completed.');
    }

    @IsTest
    static void testPositiveNullCompletionDefaultsToZero() {
        TestDataFactory factory = new TestDataFactory();
        Project_Milestone__c milestone = factory.buildMilestone(null, 'Not Started');

        Test.startTest();
        insert milestone;
        Test.stopTest();

        Project_Milestone__c result = [
            SELECT Completion_Percentage__c
            FROM Project_Milestone__c
            WHERE Id = :milestone.Id
        ];
        System.assertEquals(0, result.Completion_Percentage__c, 'Null completion percentage should default to 0.');
    }

    @IsTest
    static void testNegativeCompletionPercentageAboveRangeIsBlocked() {
        TestDataFactory factory = new TestDataFactory();
        Project_Milestone__c milestone = factory.buildMilestone(150, 'In Progress');

        Test.startTest();
        Boolean caughtException = false;
        try {
            insert milestone;
        } catch (DmlException dmlEx) {
            caughtException = true;
            System.assert(
                dmlEx.getMessage().contains('Completion Percentage must be a value between 0 and 100.'),
                'Expected validation rule error message.'
            );
        }
        Test.stopTest();

        System.assert(caughtException, 'Expected a validation rule exception for out-of-range completion percentage.');
    }

    @IsTest
    static void testNegativeCompletionPercentageBelowRangeIsBlocked() {
        TestDataFactory factory = new TestDataFactory();
        Project_Milestone__c milestone = factory.buildMilestone(-5, 'In Progress');

        Test.startTest();
        Boolean caughtException = false;
        try {
            insert milestone;
        } catch (DmlException dmlEx) {
            caughtException = true;
        }
        Test.stopTest();

        System.assert(caughtException, 'Expected a validation rule exception for negative completion percentage.');
    }

    @IsTest
    static void testNegativeMissingRequiredFieldsIsBlocked() {
        Project_Milestone__c milestone = new Project_Milestone__c();

        Test.startTest();
        Boolean caughtException = false;
        try {
            insert milestone;
        } catch (DmlException dmlEx) {
            caughtException = true;
        }
        Test.stopTest();

        System.assert(caughtException, 'Expected a required field exception when Milestone_Name__c/Due_Date__c are missing.');
    }

    @IsTest
    static void testBulkInsertAndUpdateTwoHundredRecords() {
        TestDataFactory factory = new TestDataFactory();
        List<Project_Milestone__c> milestones = factory.buildMilestones(200, 40, 'In Progress');

        Test.startTest();
        insert milestones;

        for (Project_Milestone__c milestone : milestones) {
            milestone.Completion_Percentage__c = 100;
            milestone.Status__c = 'Completed';
        }
        update milestones;
        Test.stopTest();

        List<Project_Milestone__c> results = [
            SELECT Status__c, Completion_Percentage__c
            FROM Project_Milestone__c
            WHERE Id IN :milestones
        ];
        System.assertEquals(200, results.size(), 'All 200 records should be present.');
        for (Project_Milestone__c result : results) {
            System.assertEquals('Completed', result.Status__c, 'Every bulk record should be Completed.');
        }
    }
}