/**
 * Reassembles guest-submitted reference images into ContentVersions and links
 * each to its Case, then cleans up the staging rows. Runs on a recurring
 * schedule (see scheduleRecurring) rather than being triggered synchronously
 * by the guest submission, because Salesforce blocks guest users from
 * creating Files directly - even asynchronously, even with
 * AccessLevel.SYSTEM_MODE (confirmed empirically; there is no supported
 * profile/permission-set grant that lifts it). A Scheduled Apex job's
 * running user is fixed to whoever scheduled it, which is a real internal
 * user here, not the guest - see CustomiseRequestController for the guest
 * side of this flow (it only ever writes plain Reference_Image_Chunk__c
 * rows, which guest users can do without restriction).
 */
public with sharing class ReferenceImageChunkProcessor implements Schedulable {

    public void execute(SchedulableContext context) {
        processPendingUploads();
    }

    public static void processPendingUploads() {
        Map<String, List<Reference_Image_Chunk__c>> chunksByUploadId = new Map<String, List<Reference_Image_Chunk__c>>();
        for (Reference_Image_Chunk__c chunk : [
            SELECT Upload_Id__c, Case__c, File_Name__c, Chunk_Data__c
            FROM Reference_Image_Chunk__c
            WITH SYSTEM_MODE
            ORDER BY Upload_Id__c ASC, Chunk_Index__c ASC
            LIMIT 5000
        ]) {
            if (!chunksByUploadId.containsKey(chunk.Upload_Id__c)) {
                chunksByUploadId.put(chunk.Upload_Id__c, new List<Reference_Image_Chunk__c>());
            }
            chunksByUploadId.get(chunk.Upload_Id__c).add(chunk);
        }
        if (chunksByUploadId.isEmpty()) {
            return;
        }

        List<ContentVersion> versionsToInsert = new List<ContentVersion>();
        List<String> uploadIdOrder = new List<String>();

        for (String uploadId : chunksByUploadId.keySet()) {
            List<Reference_Image_Chunk__c> chunks = chunksByUploadId.get(uploadId);

            String base64Body = '';
            for (Reference_Image_Chunk__c chunk : chunks) {
                base64Body += chunk.Chunk_Data__c;
            }

            Blob fileBlob;
            try {
                fileBlob = EncodingUtil.base64Decode(base64Body);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'ReferenceImageChunkProcessor: could not decode image for upload ' + uploadId + ': ' + e.getMessage());
                continue;
            }

            ContentVersion cv = new ContentVersion();
            cv.Title = chunks[0].File_Name__c;
            cv.PathOnClient = chunks[0].File_Name__c;
            cv.VersionData = fileBlob;
            cv.FirstPublishLocationId = chunks[0].Case__c;
            versionsToInsert.add(cv);
            uploadIdOrder.add(uploadId);
        }

        if (versionsToInsert.isEmpty()) {
            return;
        }

        Database.SaveResult[] cvResults = Database.insert(versionsToInsert, false, AccessLevel.SYSTEM_MODE);
        List<Reference_Image_Chunk__c> chunksToDelete = new List<Reference_Image_Chunk__c>();
        for (Integer i = 0; i < cvResults.size(); i++) {
            String uploadId = uploadIdOrder[i];
            if (cvResults[i].isSuccess()) {
                chunksToDelete.addAll(chunksByUploadId.get(uploadId));
            } else {
                System.debug(LoggingLevel.ERROR, 'ReferenceImageChunkProcessor: ContentVersion insert failed for upload ' + uploadId + ': ' + cvResults[i].getErrors());
            }
        }

        if (!chunksToDelete.isEmpty()) {
            Database.delete(chunksToDelete, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static final String JOB_NAME_PREFIX = 'Reference Image Chunk Processor - min ';

    /**
     * One-time setup: schedules this job to run once every minute, indefinitely,
     * so a submitted photo attaches to its Case within ~60 seconds rather than
     * making a support agent wait. Salesforce cron rejects both wildcard ("*")
     * and step ("0/1") syntax for the minutes field ("Seconds and minutes must
     * be specified as integers") - true every-minute coverage requires one
     * CronTrigger per explicit minute value, so this stacks 60 of them. Safe to
     * call more than once - aborts any existing jobs with this prefix first.
     * Not invoked automatically; run once per org (see deployment notes),
     * since Scheduled Apex jobs are org state, not deployable metadata.
     */
    public static List<Id> scheduleRecurring() {
        for (CronTrigger existing : [
            SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :(JOB_NAME_PREFIX + '%')
        ]) {
            System.abortJob(existing.Id);
        }

        List<Id> jobIds = new List<Id>();
        for (Integer minute = 0; minute < 60; minute++) {
            String cron = '0 ' + minute + ' * * * ?';
            jobIds.add(System.schedule(JOB_NAME_PREFIX + minute, cron, new ReferenceImageChunkProcessor()));
        }
        return jobIds;
    }
}