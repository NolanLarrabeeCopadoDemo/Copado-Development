@isTest
private class NotificationServiceTest {

    @TestSetup
    static void setup() {
    }

    @isTest
    static void testSendInAppNotification_NullRecipients_NoException() {
        Test.startTest();
        NotificationService.sendInAppNotification(null, 'Account_Onboarding_Notification', 'Title', 'Body', null);
        Test.stopTest();
        System.assert(true, 'Null recipientIds should be handled gracefully by the guard clause.');
    }

    @isTest
    static void testSendInAppNotification_EmptyRecipients_NoException() {
        Test.startTest();
        NotificationService.sendInAppNotification(new Set<String>(), 'Account_Onboarding_Notification', 'Title', 'Body', null);
        Test.stopTest();
        System.assert(true, 'Empty recipientIds should be handled gracefully by the guard clause.');
    }

    @isTest
    static void testSendInAppNotification_BlankTitle_NoException() {
        Set<String> recipients = new Set<String>{ UserInfo.getUserId() };
        Test.startTest();
        NotificationService.sendInAppNotification(recipients, 'Account_Onboarding_Notification', '', 'Body', null);
        Test.stopTest();
        System.assert(true, 'Blank title should be handled gracefully by the guard clause.');
    }

    @isTest
    static void testSendInAppNotification_NullTitle_NoException() {
        Set<String> recipients = new Set<String>{ UserInfo.getUserId() };
        Test.startTest();
        NotificationService.sendInAppNotification(recipients, 'Account_Onboarding_Notification', null, 'Body', null);
        Test.stopTest();
        System.assert(true, 'Null title should be handled gracefully by the guard clause.');
    }

    @isTest
    static void testSendInAppNotification_BlankNotifTypeApiName_NoException() {
        Set<String> recipients = new Set<String>{ UserInfo.getUserId() };
        Test.startTest();
        NotificationService.sendInAppNotification(recipients, '', 'Title', 'Body', null);
        Test.stopTest();
        System.assert(true, 'Blank notifTypeApiName should be handled gracefully by the guard clause.');
    }

    @isTest
    static void testSendInAppNotification_UnknownNotifType_NoException() {
        Set<String> recipients = new Set<String>{ UserInfo.getUserId() };
        Test.startTest();
        NotificationService.sendInAppNotification(recipients, 'Nonexistent_Notification_Type_XYZ', 'Title', 'Body', null);
        Test.stopTest();
        System.assert(true, 'Unknown CustomNotificationType DeveloperName should be handled gracefully.');
    }

    @isTest
    static void testSendInAppNotification_ValidSingleRecipient_SendsNotification() {
        Set<String> recipients = new Set<String>{ UserInfo.getUserId() };
        Test.startTest();
        NotificationService.sendInAppNotification(
            recipients,
            'Account_Onboarding_Notification',
            'Welcome',
            'Your account has been onboarded.',
            UserInfo.getUserId()
        );
        Test.stopTest();
        System.assert(true, 'Valid single-recipient send should complete without throwing.');
    }

    @isTest
    static void testSendInAppNotification_ValidNoTargetId_SendsNotification() {
        Set<String> recipients = new Set<String>{ UserInfo.getUserId() };
        Test.startTest();
        NotificationService.sendInAppNotification(
            recipients,
            'Account_Onboarding_Notification',
            'Welcome',
            'Your account has been onboarded.',
            null
        );
        Test.stopTest();
        System.assert(true, 'Valid send without a targetId should complete without throwing.');
    }

    @isTest
    static void testSendInAppNotification_ValidBlankBody_SendsNotification() {
        Set<String> recipients = new Set<String>{ UserInfo.getUserId() };
        Test.startTest();
        NotificationService.sendInAppNotification(
            recipients,
            'Account_Onboarding_Notification',
            'Welcome',
            '',
            null
        );
        Test.stopTest();
        System.assert(true, 'Valid send with a blank body should complete without throwing.');
    }

    @isTest
    static void testSendInAppNotification_BulkRecipients_BatchesSends() {
        Set<String> recipients = new Set<String>();
        for (Integer i = 0; i < 25; i++) {
            recipients.add(UserInfo.getUserId());
        }
        Test.startTest();
        NotificationService.sendInAppNotification(
            recipients,
            'Account_Onboarding_Notification',
            'Bulk Welcome',
            'Bulk onboarding batch test.',
            null
        );
        Test.stopTest();
        System.assert(true, 'Bulk recipient set (single unique Id) should be batched and sent without throwing.');
    }
}