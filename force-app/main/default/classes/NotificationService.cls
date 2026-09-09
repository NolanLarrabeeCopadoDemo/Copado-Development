/**
 * @description Shared service class for sending notifications (Email Alert Engine and
 * In-App Notification Handler). This tier implements the in-app (bell) notification handler.
 *
 * Note: The Nebula Logger managed package is not installed in this org (confirmed via
 * metadata inspection prior to build - only Copado's own managed "Logger" classes
 * (copado__Logger / copadoconnect__Logger) and no unmanaged Logger/LogEntry components
 * exist). System.debug() with explicit LoggingLevel is used as an interim substitute for
 * Logger.info()/Logger.error() so behavior and log intent match the acceptance criteria.
 * Once Nebula Logger is installed, the System.debug calls below should be swapped for the
 * equivalent Logger.info()/Logger.error()/Logger.saveLog() calls.
 */
public class NotificationService {

    /** Maximum recipients accepted per Messaging.CustomNotification.send() call. */
    private static final Integer MAX_RECIPIENTS_PER_NOTIFICATION = 10;

    /**
     * @description Sends an in-app (bell) custom notification to one or more users.
     * Looks up the CustomNotificationType by DeveloperName at runtime (no hardcoded Ids),
     * builds a Messaging.CustomNotification, and sends it in bulkified batches.
     * @param recipientIds Set of User Ids to notify.
     * @param notifTypeApiName DeveloperName of the CustomNotificationType to use.
     * @param title Notification title.
     * @param body Notification body.
     * @param targetId Optional Id the notification should navigate to when clicked.
     */
    public static void sendInAppNotification(
        Set<String> recipientIds,
        String notifTypeApiName,
        String title,
        String body,
        String targetId
    ) {
        if (recipientIds == null || recipientIds.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'NotificationService.sendInAppNotification: recipientIds is null or empty. Aborting send.');
            return;
        }
        if (String.isBlank(title)) {
            System.debug(LoggingLevel.ERROR, 'NotificationService.sendInAppNotification: title is blank. Aborting send.');
            return;
        }
        if (String.isBlank(notifTypeApiName)) {
            System.debug(LoggingLevel.ERROR, 'NotificationService.sendInAppNotification: notifTypeApiName is blank. Aborting send.');
            return;
        }

        Id notificationTypeId = resolveNotificationTypeId(notifTypeApiName);
        if (notificationTypeId == null) {
            System.debug(LoggingLevel.ERROR, 'NotificationService.sendInAppNotification: No CustomNotificationType found for DeveloperName "' + notifTypeApiName + '".');
            return;
        }

        for (Set<String> recipientBatch : batchRecipients(recipientIds, MAX_RECIPIENTS_PER_NOTIFICATION)) {
            sendBatch(recipientBatch, notificationTypeId, title, body, targetId);
        }
    }

    /**
     * @description Queries CustomNotificationType by DeveloperName at runtime (no hardcoded Ids).
     * @param notifTypeApiName DeveloperName of the CustomNotificationType.
     * @return Id of the matching CustomNotificationType, or null if not found.
     */
    private static Id resolveNotificationTypeId(String notifTypeApiName) {
        if (!Schema.sObjectType.CustomNotificationType.isAccessible()) {
            System.debug(LoggingLevel.ERROR, 'NotificationService.sendInAppNotification: Running user lacks read access to CustomNotificationType.');
            return null;
        }
        List<CustomNotificationType> notifTypes = [
            SELECT Id, DeveloperName
            FROM CustomNotificationType
            WHERE DeveloperName = :notifTypeApiName
            LIMIT 1
        ];
        return notifTypes.isEmpty() ? null : notifTypes[0].Id;
    }

    /**
     * @description Sends a single bulkified batch (max 10 recipients) of the custom notification.
     * @param recipientBatch Batch of recipient User Ids (size <= MAX_RECIPIENTS_PER_NOTIFICATION).
     * @param notificationTypeId Resolved CustomNotificationType Id.
     * @param title Notification title.
     * @param body Notification body.
     * @param targetId Optional target Id for the notification.
     */
    private static void sendBatch(
        Set<String> recipientBatch,
        Id notificationTypeId,
        String title,
        String body,
        String targetId
    ) {
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(String.isBlank(body) ? '' : body);
            notification.setNotificationTypeId(notificationTypeId);
            if (String.isNotBlank(targetId)) {
                notification.setTargetId(targetId);
            }
            notification.send(recipientBatch);
            System.debug(LoggingLevel.INFO, 'NotificationService.sendInAppNotification: Sent notification "' + title + '" to ' + recipientBatch.size() + ' recipient(s).');
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'NotificationService.sendInAppNotification: Failed to send notification "' + title + '". Error: ' + ex.getMessage());
        }
    }

    /**
     * @description Splits a set of recipient Ids into bulkified batches of the given size.
     * @param recipientIds Full set of recipient Ids.
     * @param batchSize Maximum number of recipients per batch.
     * @return List of recipient batches.
     */
    private static List<Set<String>> batchRecipients(Set<String> recipientIds, Integer batchSize) {
        List<Set<String>> batches = new List<Set<String>>();
        Set<String> currentBatch = new Set<String>();
        for (String recipientId : recipientIds) {
            currentBatch.add(recipientId);
            if (currentBatch.size() == batchSize) {
                batches.add(currentBatch);
                currentBatch = new Set<String>();
            }
        }
        if (!currentBatch.isEmpty()) {
            batches.add(currentBatch);
        }
        return batches;
    }
}