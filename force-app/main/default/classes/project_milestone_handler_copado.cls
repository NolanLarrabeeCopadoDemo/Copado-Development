/**
 * Handler class for the Project_Milestone__c trigger.
 * Contains all business logic; the trigger itself only delegates to this class.
 * Bulkified, uses try-catch with Logger error logging, and offloads heavier
 * post-completion processing to an asynchronous Queueable.
 */
public with sharing class project_milestone_handler_copado {

    private static final String CONTEXT = 'project_milestone_handler_copado';
    private static final String STATUS_COMPLETED = 'Completed';
    private static final Decimal COMPLETE_PERCENTAGE = 100;

    /**
     * Before insert/update: defaults a null Completion_Percentage__c to 0 so
     * downstream logic and reporting never operate on nulls.
     * @param newRecords the trigger.new list (bulk safe)
     */
    public static void beforeSave(List<Project_Milestone__c> newRecords) {
        try {
            for (Project_Milestone__c milestone : newRecords) {
                if (milestone.Completion_Percentage__c == null) {
                    milestone.Completion_Percentage__c = 0;
                }
            }
        } catch (Exception ex) {
            Logger.error(CONTEXT + '.beforeSave', ex);
        }
    }

    /**
     * After insert/update: detects milestones that just transitioned to fully
     * complete (100% and Status__c = Completed) and offloads any heavier
     * follow-up processing to an async Queueable, bulk safe and free of
     * SOQL/DML inside loops.
     * @param newRecords trigger.new list
     * @param oldMap trigger.oldMap (null on insert)
     */
    public static void afterSave(List<Project_Milestone__c> newRecords, Map<Id, Project_Milestone__c> oldMap) {
        try {
            Set<Id> newlyCompletedIds = collectNewlyCompletedIds(newRecords, oldMap);
            if (!newlyCompletedIds.isEmpty() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new MilestoneCompletionProcessor(newlyCompletedIds));
            }
        } catch (Exception ex) {
            Logger.error(CONTEXT + '.afterSave', ex);
        }
    }

    private static Set<Id> collectNewlyCompletedIds(List<Project_Milestone__c> newRecords, Map<Id, Project_Milestone__c> oldMap) {
        Set<Id> newlyCompletedIds = new Set<Id>();
        for (Project_Milestone__c milestone : newRecords) {
            Project_Milestone__c oldMilestone = (oldMap == null) ? null : oldMap.get(milestone.Id);
            Boolean wasCompletedBefore = oldMilestone != null && oldMilestone.Status__c == STATUS_COMPLETED;
            Boolean isCompletedNow = milestone.Completion_Percentage__c == COMPLETE_PERCENTAGE
                && milestone.Status__c == STATUS_COMPLETED;
            if (isCompletedNow && !wasCompletedBefore) {
                newlyCompletedIds.add(milestone.Id);
            }
        }
        return newlyCompletedIds;
    }

    /**
     * Asynchronous processor for milestones that just completed. Kept as a
     * Queueable so any future heavy/long-running follow-up work (e.g.
     * notifications, project rollups) does not consume the triggering
     * transaction's limits.
     */
    public class MilestoneCompletionProcessor implements Queueable {
        private final Set<Id> milestoneIds;

        /**
         * @param milestoneIds ids of milestones that just became fully complete
         */
        public MilestoneCompletionProcessor(Set<Id> milestoneIds) {
            this.milestoneIds = milestoneIds;
        }

        /**
         * Re-queries the completed milestones with FLS/CRUD enforcement and
         * logs the outcome. Wrapped in try-catch so async failures never
         * surface to the end user and are captured for support follow-up.
         */
        public void execute(QueueableContext context) {
            try {
                List<Project_Milestone__c> completedMilestones = [
                    SELECT Id, Project__c, Status__c
                    FROM Project_Milestone__c
                    WHERE Id IN :milestoneIds
                    WITH SECURITY_ENFORCED
                ];
                Logger.info(CONTEXT + '.MilestoneCompletionProcessor',
                    'Processed ' + completedMilestones.size() + ' completed milestone(s).');
            } catch (Exception ex) {
                Logger.error(CONTEXT + '.MilestoneCompletionProcessor', ex);
            }
        }
    }
}