@isTest
public class Install2GPackageTests {
    
    @isTest
    public static void UpdateResultRecords()
    {
        copado__Environment__c environment = new copado__Environment__c(
            Name = 'Environment Name'
        );

        insert environment;

        copado__Result__c functionResult = new copado__Result__c(
            copado__ParentID__c = environment.ID,
            copado__Description__c = 'This should be overwritten',
            copado__Job_Type__c = 'install_2G_package'
        );

        insert functionResult;

        Test.startTest();

        Install2GPackage.FlowInputs inputs = new Install2GPackage.FlowInputs();
        inputs.resultIds = new List<string> { functionResult.ID};
        inputs.packageId = 'PackageID';

        Install2GPackage.UpdateResultRecords(new List<Install2GPackage.FlowInputs> { inputs });

        Test.stopTest();

        functionResult = [SELECT    copado__Description__c
                          FROM      copado__Result__c
                          WHERE     ID = :functionResult.ID
                          LIMIT 1];

        System.assertNotEquals('This should be overwritten', functionResult.copado__Description__c);
        System.assertEquals('Installing Package PackageID in Environment Name', functionResult.copado__Description__c);
        

    }
}