@isTest
private class GuestFileReproTest3 {
    @isTest
    static void reproSyncWithProfilePermission() {
        User guestUser = [SELECT Id FROM User WHERE Username = 'cara_custom_product_site@00dfv0029wxhzfo2qa.org.force.com' LIMIT 1];

        Id caseId;
        System.runAs(guestUser) {
            Case c = new Case(Subject='Repro3', Origin='Web', SuppliedName='Jane Doe', SuppliedEmail='jane.doe@example.com');
            Database.insert(c, false, AccessLevel.SYSTEM_MODE);
            caseId = c.Id;

            ContentVersion cv = new ContentVersion();
            cv.Title = 'repro3.png';
            cv.PathOnClient = 'repro3.png';
            cv.VersionData = Blob.valueOf('test image bytes');
            cv.FirstPublishLocationId = caseId;

            Database.SaveResult cvResult = Database.insert(cv, false, AccessLevel.SYSTEM_MODE);
            System.debug('SYNC-SYSTEMMODE CV insert success: ' + cvResult.isSuccess());
            if (!cvResult.isSuccess()) {
                for (Database.Error e : cvResult.getErrors()) {
                    System.debug('SYNC-SYSTEMMODE CV ERROR: ' + e.getStatusCode() + ' ' + e.getMessage());
                }
            }

            ContentVersion cv2 = new ContentVersion();
            cv2.Title = 'repro3b.png';
            cv2.PathOnClient = 'repro3b.png';
            cv2.VersionData = Blob.valueOf('test image bytes 2');
            cv2.FirstPublishLocationId = caseId;

            try {
                insert cv2;
                System.debug('SYNC-USERMODE CV insert success: true');
            } catch (Exception e) {
                System.debug('SYNC-USERMODE CV ERROR: ' + e.getMessage());
            }

            Attachment att = new Attachment();
            att.Name = 'repro3.png';
            att.Body = Blob.valueOf('test image bytes');
            att.ParentId = caseId;
            att.ContentType = 'image/png';
            Database.SaveResult attResult = Database.insert(att, false, AccessLevel.SYSTEM_MODE);
            System.debug('SYNC-SYSTEMMODE ATT insert success: ' + attResult.isSuccess());
            if (!attResult.isSuccess()) {
                for (Database.Error e : attResult.getErrors()) {
                    System.debug('SYNC-SYSTEMMODE ATT ERROR: ' + e.getStatusCode() + ' ' + e.getMessage());
                }
            }

            Attachment att2 = new Attachment();
            att2.Name = 'repro3b.png';
            att2.Body = Blob.valueOf('test image bytes 2');
            att2.ParentId = caseId;
            att2.ContentType = 'image/png';
            try {
                insert att2;
                System.debug('SYNC-USERMODE ATT insert success: true');
            } catch (Exception e) {
                System.debug('SYNC-USERMODE ATT ERROR: ' + e.getMessage());
            }
        }
    }
}