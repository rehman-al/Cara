@isTest
private class ReferenceImageChunkProcessorTest {

    @isTest
    static void testScheduleRecurringCreatesSixtyJobs() {
        Test.startTest();
        List<Id> jobIds = ReferenceImageChunkProcessor.scheduleRecurring();
        Test.stopTest();

        System.assertEquals(60, jobIds.size(), 'Expected one CronTrigger per minute value.');

        List<CronTrigger> jobs = [
            SELECT CronExpression FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Reference Image Chunk Processor - min %'
        ];
        System.assertEquals(60, jobs.size());
    }

    @isTest
    static void testScheduleRecurringIsIdempotent() {
        Test.startTest();
        ReferenceImageChunkProcessor.scheduleRecurring();
        List<Id> secondRunJobIds = ReferenceImageChunkProcessor.scheduleRecurring();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Reference Image Chunk Processor - min %'
        ];
        System.assertEquals(60, jobs.size(), 'Re-scheduling should abort the previous 60 jobs rather than stacking a second set.');

        Set<Id> jobIdSet = new Set<Id>();
        for (CronTrigger job : jobs) {
            jobIdSet.add(job.Id);
        }
        for (Id jobId : secondRunJobIds) {
            System.assert(jobIdSet.contains(jobId), 'Expected the surviving jobs to be from the second scheduling run.');
        }
    }

    @isTest
    static void testProcessPendingUploadsWithNoChunksDoesNothing() {
        Test.startTest();
        ReferenceImageChunkProcessor.processPendingUploads();
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion]);
    }
}