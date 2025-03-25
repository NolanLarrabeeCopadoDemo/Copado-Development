public class Install2GPackage {
    @InvocableMethod
    public static void UpdateResultRecords(List<FlowInputs> flowInput)
    {
        List<copado__Result__c> results = [SELECT    ID, copado__Description__c,copado__ParentID__c
                                          FROM      copado__Result__c
                                          WHERE     ID IN :flowInput[0].resultIds];

        List<string> environmentIds = new List<string>();
        for(copado__Result__c result : results)
        {
            environmentIds.add(result.copado__ParentID__c);
        }

        List<copado__Environment__c> environments = [SELECT ID, Name
                                                     FROM   copado__Environment__c
                                                     WHERE  ID IN :environmentIds];

        Map<string,string> environmentNameMap = new Map<string,string>();
        for(copado__Environment__c result : environments)
        {
            if(environmentNameMap.containsKey(result.ID))
            {
                continue;
            }

            environmentNameMap.put(result.ID, result.Name);
        }

        for(copado__Result__c result : results)
        {
            result.copado__Description__c = 'Installing Package ' + flowInput[0].packageId + ' in ' + environmentNameMap.get(result.copado__ParentID__c);
        }

        update results;
    }

    public class FlowInputs{
    
        @InvocableVariable
        public List<string> resultIds;
        
        @InvocableVariable
        public String packageId;
        
    }
}