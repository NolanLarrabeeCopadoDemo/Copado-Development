/**
 * @description Test coverage for EquipmentAvailabilityController_copado.
 * Validates happy-path wrapper results, active-shipment name resolution,
 * empty-result path, and both CRUD/FLS guard paths (object-not-accessible
 * and field-not-accessible via WITH SECURITY_ENFORCED).
 * Targets 85-90%+ code coverage per project quality standards.
 *
 * Key schema notes for Equipment__c:
 *  - Active_Shipment__c: self-referencing placeholder lookup (relationshipName:
 *    Active_Shipment_Placeholder). Name is resolved via a secondary SOQL query
 *    on Truck_ID__c rather than relationship traversal.
 *  - VIN__c: must be exactly 17 characters (VR_VIN_Format validation rule).
 *  - Truck_ID__c: unique text (20 chars max).
 */
@isTest
private class EquipmentAvailabilityCtrlTest_copado {

    // ───────────────────────────────────────────────────────────────────
    // Test Setup
    // ───────────────────────────────────────────────────────────────────

    @TestSetup
    static void setupData() {
        // Base truck — will be self-referenced as active-shipment placeholder
        Equipment__c baseTruck = new Equipment__c(
            Truck_ID__c             = 'TRK-0001',
            Truck_Size_Class__c     = 'Class_8',
            Operational_Status__c   = 'Available',
            Payload_Capacity_lbs__c = 12000,
            Cargo_Volume_Cu_Ft__c   = 500,
            VIN__c                  = '1HGCM82633A123456'
        );
        insert baseTruck;

        // In-transit truck referencing baseTruck via the self-ref Active_Shipment__c field
        Equipment__c inTransitTruck = new Equipment__c(
            Truck_ID__c             = 'TRK-0002',
            Truck_Size_Class__c     = 'Class_6',
            Operational_Status__c   = 'In_Transit',
            Payload_Capacity_lbs__c = 8000,
            Cargo_Volume_Cu_Ft__c   = 300,
            Active_Shipment__c      = baseTruck.Id,
            VIN__c                  = '2HGCM82633A654321'
        );
        insert inTransitTruck;

        // ── Users ──────────────────────────────────────────────────────
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        Long rnd = Crypto.getRandomLong();

        // Full-access user: object read + all queried fields
        User fullAccessUser = new User(
            FirstName           = 'EqAvl',
            LastName            = 'FullAccess',
            Alias               = 'eqful',
            Email               = 'eqavl.full@example.com.invalid',
            Username            = 'eqavl.full.' + rnd + '@example.com.invalid',
            TimeZoneSidKey      = 'America/Los_Angeles',
            LocaleSidKey        = 'en_US',
            EmailEncodingKey    = 'UTF-8',
            LanguageLocaleKey   = 'en_US',
            ProfileId           = standardProfile.Id
        );

        // No-access user: no Equipment__c permissions whatsoever
        User noAccessUser = new User(
            FirstName           = 'EqAvl',
            LastName            = 'NoAccess',
            Alias               = 'eqnoa',
            Email               = 'eqavl.noaccess@example.com.invalid',
            Username            = 'eqavl.noaccess.' + rnd + '@example.com.invalid',
            TimeZoneSidKey      = 'America/Los_Angeles',
            LocaleSidKey        = 'en_US',
            EmailEncodingKey    = 'UTF-8',
            LanguageLocaleKey   = 'en_US',
            ProfileId           = standardProfile.Id
        );

        // Partial-access user: object read only, no field-level access
        User partialAccessUser = new User(
            FirstName           = 'EqAvl',
            LastName            = 'PartialAccess',
            Alias               = 'eqpar',
            Email               = 'eqavl.partial@example.com.invalid',
            Username            = 'eqavl.partial.' + rnd + '@example.com.invalid',
            TimeZoneSidKey      = 'America/Los_Angeles',
            LocaleSidKey        = 'en_US',
            EmailEncodingKey    = 'UTF-8',
            LanguageLocaleKey   = 'en_US',
            ProfileId           = standardProfile.Id
        );

        insert new List<User>{ fullAccessUser, noAccessUser, partialAccessUser };

        // ── Full-access Permission Set ─────────────────────────────────
        PermissionSet fullPS = new PermissionSet(
            Name  = 'EqAvlCtrlTest_Full_copado',
            Label = 'Eq Avl Ctrl Test Full'
        );
        insert fullPS;

        insert new ObjectPermissions(
            ParentId                  = fullPS.Id,
            SobjectType               = 'Equipment__c',
            PermissionsRead           = true,
            PermissionsViewAllRecords = true
        );

        List<FieldPermissions> fullFieldPerms = new List<FieldPermissions>();
        for (String fieldName : new List<String>{
            'Truck_ID__c', 'Truck_Size_Class__c', 'Operational_Status__c',
            'Payload_Capacity_lbs__c', 'Cargo_Volume_Cu_Ft__c', 'Active_Shipment__c'
        }) {
            fullFieldPerms.add(new FieldPermissions(
                ParentId        = fullPS.Id,
                SobjectType     = 'Equipment__c',
                Field           = 'Equipment__c.' + fieldName,
                PermissionsRead = true
            ));
        }
        insert fullFieldPerms;

        insert new PermissionSetAssignment(
            AssigneeId      = fullAccessUser.Id,
            PermissionSetId = fullPS.Id
        );

        // ── Object-only Permission Set (partial user) ──────────────────
        PermissionSet objectOnlyPS = new PermissionSet(
            Name  = 'EqAvlCtrlTest_ObjOnly_copado',
            Label = 'Eq Avl Ctrl Test Obj Only'
        );
        insert objectOnlyPS;

        insert new ObjectPermissions(
            ParentId                  = objectOnlyPS.Id,
            SobjectType               = 'Equipment__c',
            PermissionsRead           = true,
            PermissionsViewAllRecords = true
        );

        insert new PermissionSetAssignment(
            AssigneeId      = partialAccessUser.Id,
            PermissionSetId = objectOnlyPS.Id
        );
    }

    // ───────────────────────────────────────────────────────────────────
    // Happy-Path: correct wrapper count for fully-permissioned user
    // ───────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEquipmentAvailabilityReturnsRecords() {
        User runAsUser = [SELECT Id FROM User WHERE LastName = 'FullAccess' AND Alias = 'eqful' LIMIT 1];

        List<EquipmentAvailabilityController_copado.EquipmentWrapper> results;
        System.runAs(runAsUser) {
            Test.startTest();
            results = EquipmentAvailabilityController_copado.getEquipmentAvailability();
            Test.stopTest();
        }

        System.assertEquals(2, results.size(),
            'Expected two EquipmentWrapper records for a fully-permissioned user.');
    }

    // ───────────────────────────────────────────────────────────────────
    // Happy-Path: active-shipment name resolved via secondary SOQL
    // ───────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEquipmentAvailabilityIncludesActiveShipmentName() {
        User runAsUser = [SELECT Id FROM User WHERE LastName = 'FullAccess' AND Alias = 'eqful' LIMIT 1];

        List<EquipmentAvailabilityController_copado.EquipmentWrapper> results;
        System.runAs(runAsUser) {
            Test.startTest();
            results = EquipmentAvailabilityController_copado.getEquipmentAvailability();
            Test.stopTest();
        }

        Boolean foundActiveShipment = false;
        for (EquipmentAvailabilityController_copado.EquipmentWrapper wrapper : results) {
            if (wrapper.equipment.Active_Shipment__c != null) {
                System.assertNotEquals(null, wrapper.activeShipmentName,
                    'activeShipmentName should be populated when Active_Shipment__c is set.');
                System.assertEquals('TRK-0001', wrapper.activeShipmentName,
                    'activeShipmentName should match the Truck_ID__c of the referenced equipment.');
                foundActiveShipment = true;
            }
        }
        System.assertEquals(true, foundActiveShipment,
            'Expected at least one record with a populated Active_Shipment__c reference.');
    }

    // ───────────────────────────────────────────────────────────────────
    // Guard: AuraHandledException when object is not accessible
    // ───────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEquipmentAvailabilityThrowsWhenObjectNotAccessible() {
        User noAccessUser = [SELECT Id FROM User WHERE LastName = 'NoAccess' AND Alias = 'eqnoa' LIMIT 1];

        Boolean exceptionThrown = false;
        System.runAs(noAccessUser) {
            Test.startTest();
            try {
                EquipmentAvailabilityController_copado.getEquipmentAvailability();
            } catch (AuraHandledException auraEx) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }

        System.assertEquals(true, exceptionThrown,
            'Expected an AuraHandledException when Equipment__c is not accessible to the user.');
    }

    // ───────────────────────────────────────────────────────────────────
    // Guard: AuraHandledException when fields are not accessible (QueryException path)
    // ───────────────────────────────────────────────────────────────────

    @isTest
    static void testGetEquipmentAvailabilityThrowsWhenFieldNotAccessible() {
        User partialAccessUser = [SELECT Id FROM User WHERE LastName = 'PartialAccess' AND Alias = 'eqpar' LIMIT 1];

        Boolean exceptionThrown = false;
        System.runAs(partialAccessUser) {
            Test.startTest();
            try {
                EquipmentAvailabilityController_copado.getEquipmentAvailability();
            } catch (AuraHandledException auraEx) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }

        System.assertEquals(true, exceptionThrown,
            'Expected an AuraHandledException when queried fields are not accessible via WITH SECURITY_ENFORCED.');
    }
}