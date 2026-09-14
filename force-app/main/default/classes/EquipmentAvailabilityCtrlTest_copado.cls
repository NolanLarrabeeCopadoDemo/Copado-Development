/**
 * @description Test coverage for EquipmentAvailabilityController_copado. Runs as a dedicated
 * test user with a dynamically created PermissionSet granting Equipment__c object and field
 * read access, exercising the controller's WITH SECURITY_ENFORCED path realistically.
 */
@isTest
private class EquipmentAvailabilityCtrlTest_copado {

    @TestSetup
    static void setupData() {
        Equipment__c truck = new Equipment__c(
            Truck_ID__c = 'TRK-0001',
            Truck_Size_Class__c = 'Class_8',
            Operational_Status__c = 'Available',
            Payload_Capacity_lbs__c = 12000,
            Cargo_Volume_Cu_Ft__c = 500,
            VIN__c = '1HGCM82633A123456'
        );
        insert truck;

        Equipment__c inTransitTruck = new Equipment__c(
            Truck_ID__c = 'TRK-0002',
            Truck_Size_Class__c = 'Class_6',
            Operational_Status__c = 'In_Transit',
            Payload_Capacity_lbs__c = 8000,
            Cargo_Volume_Cu_Ft__c = 300,
            Active_Shipment__c = truck.Id,
            VIN__c = '2HGCM82633A654321'
        );
        insert inTransitTruck;

        Profile standardUserProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User runAsUser = new User(
            FirstName = 'Equipment',
            LastName = 'AvailabilityTestUser',
            Alias = 'eqavl',
            Email = 'equipment.availability.test.copado@example.com.invalid',
            Username = 'equipment.availability.test.copado@example.com.' + Crypto.getRandomLong() + '.invalid',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardUserProfile.Id
        );
        insert runAsUser;

        PermissionSet permissionSet = new PermissionSet(
            Name = 'EquipmentAvailabilityCtrlTest_copado_PS',
            Label = 'Equipment Availability Ctrl Test PS'
        );
        insert permissionSet;

        insert new ObjectPermissions(
            ParentId = permissionSet.Id,
            SobjectType = 'Equipment__c',
            PermissionsRead = true,
            PermissionsViewAllRecords = true
        );

        List<FieldPermissions> fieldPermissionsList = new List<FieldPermissions>();
        for (String fieldName : new List<String>{
            'Truck_ID__c', 'Truck_Size_Class__c', 'Operational_Status__c',
            'Payload_Capacity_lbs__c', 'Cargo_Volume_Cu_Ft__c', 'Active_Shipment__c'
        }) {
            fieldPermissionsList.add(new FieldPermissions(
                ParentId = permissionSet.Id,
                SobjectType = 'Equipment__c',
                Field = 'Equipment__c.' + fieldName,
                PermissionsRead = true
            ));
        }
        insert fieldPermissionsList;

        insert new PermissionSetAssignment(
            AssigneeId = runAsUser.Id,
            PermissionSetId = permissionSet.Id
        );

        User noAccessUser = new User(
            FirstName = 'Equipment',
            LastName = 'AvailabilityNoAccessUser',
            Alias = 'eqnoa',
            Email = 'equipment.availability.noaccess.copado@example.com.invalid',
            Username = 'equipment.availability.noaccess.copado@example.com.' + Crypto.getRandomLong() + '.invalid',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardUserProfile.Id
        );
        insert noAccessUser;

        User partialAccessUser = new User(
            FirstName = 'Equipment',
            LastName = 'AvailabilityPartialAccessUser',
            Alias = 'eqpar',
            Email = 'equipment.availability.partial.copado@example.com.invalid',
            Username = 'equipment.availability.partial.copado@example.com.' + Crypto.getRandomLong() + '.invalid',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardUserProfile.Id
        );
        insert partialAccessUser;

        PermissionSet objectOnlyPermissionSet = new PermissionSet(
            Name = 'EquipmentAvailabilityCtrlTest_copado_ObjOnlyPS',
            Label = 'Equipment Availability Ctrl Test Object Only PS'
        );
        insert objectOnlyPermissionSet;

        insert new ObjectPermissions(
            ParentId = objectOnlyPermissionSet.Id,
            SobjectType = 'Equipment__c',
            PermissionsRead = true,
            PermissionsViewAllRecords = true
        );

        insert new PermissionSetAssignment(
            AssigneeId = partialAccessUser.Id,
            PermissionSetId = objectOnlyPermissionSet.Id
        );
    }

    @isTest
    static void testGetEquipmentAvailabilityReturnsRecords() {
        User runAsUser = [
            SELECT Id FROM User
            WHERE LastName = 'AvailabilityTestUser'
            LIMIT 1
        ];

        List<Equipment__c> results;
        System.runAs(runAsUser) {
            Test.startTest();
            results = EquipmentAvailabilityController_copado.getEquipmentAvailability();
            Test.stopTest();
        }

        System.assertEquals(2, results.size(), 'Expected two Equipment__c records to be returned.');
    }

    @isTest
    static void testGetEquipmentAvailabilityIncludesActiveShipmentName() {
        User runAsUser = [
            SELECT Id FROM User
            WHERE LastName = 'AvailabilityTestUser'
            LIMIT 1
        ];

        List<Equipment__c> results;
        System.runAs(runAsUser) {
            Test.startTest();
            results = EquipmentAvailabilityController_copado.getEquipmentAvailability();
            Test.stopTest();
        }

        Boolean foundActiveShipment = false;
        for (Equipment__c record : results) {
            if (record.Active_Shipment__c != null) {
                System.assertNotEquals(null, record.Active_Shipment__r.Name,
                    'Active_Shipment__r.Name should be populated when Active_Shipment__c is set.');
                foundActiveShipment = true;
            }
        }
        System.assertEquals(true, foundActiveShipment, 'Expected at least one record with an active shipment.');
    }

    @isTest
    static void testGetEquipmentAvailabilityThrowsWhenObjectNotAccessible() {
        User noAccessUser = [
            SELECT Id FROM User
            WHERE LastName = 'AvailabilityNoAccessUser'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;
        System.runAs(noAccessUser) {
            Test.startTest();
            try {
                EquipmentAvailabilityController_copado.getEquipmentAvailability();
            } catch (AuraHandledException auraException) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }

        System.assertEquals(true, exceptionThrown,
            'Expected an AuraHandledException when the object is not accessible.');
    }

    @isTest
    static void testGetEquipmentAvailabilityThrowsWhenFieldNotAccessible() {
        User partialAccessUser = [
            SELECT Id FROM User
            WHERE LastName = 'AvailabilityPartialAccessUser'
            LIMIT 1
        ];

        Boolean exceptionThrown = false;
        System.runAs(partialAccessUser) {
            Test.startTest();
            try {
                EquipmentAvailabilityController_copado.getEquipmentAvailability();
            } catch (AuraHandledException auraException) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }

        System.assertEquals(true, exceptionThrown,
            'Expected an AuraHandledException when a queried field is not accessible.');
    }
}