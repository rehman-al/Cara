@RestResource(urlMapping='/cara/orders/attachments')
global with sharing class CARAOrderAttachmentRestService {
    private static final String REST_API_VERSION = 'v67.0';

    @HttpGet
    global static void getAttachments() {
        try {
            String orderReferenceNumber = RestContext.request == null
                ? null
                : RestContext.request.params.get('orderReferenceNumber');

            if (String.isBlank(orderReferenceNumber)) {
                throw new IntegrationException('orderReferenceNumber is required.');
            }

            Order orderRecord = findOrder(orderReferenceNumber);
            List<AttachmentSummary> attachmentSummaries = listAttachments(orderRecord.Id);

            writeListResponse(200, true, 'Attachments retrieved successfully.', orderRecord.Id, attachmentSummaries);
        } catch (IntegrationException exceptionRecord) {
            writeListResponse(400, false, exceptionRecord.getMessage(), null, new List<AttachmentSummary>());
        } catch (Exception exceptionRecord) {
            writeListResponse(500, false, 'Unable to retrieve attachments.', null, new List<AttachmentSummary>());
        }
    }

    @HttpPost
    global static void createAttachments() {
        Savepoint transactionSavepoint = Database.setSavepoint();

        try {
            CARAOrderAttachmentPayload payload = deserializePayload();
            validateRequiredFields(payload);

            Order orderRecord = findOrder(payload.orderReferenceNumber);
            List<Id> contentDocumentIds = saveAttachments(orderRecord.Id, payload.attachments);

            writeResponse(200, true, 'Attachment(s) created successfully.', orderRecord.Id, contentDocumentIds);
        } catch (Exception exceptionRecord) {
            Database.rollback(transactionSavepoint);
            writeResponse(400, false, exceptionRecord.getMessage(), null, new List<Id>());
        }
    }

    private static CARAOrderAttachmentPayload deserializePayload() {
        if (RestContext.request == null || RestContext.request.requestBody == null) {
            throw new IntegrationException('A JSON request body is required.');
        }

        String requestBody = RestContext.request.requestBody.toString();
        if (String.isBlank(requestBody)) {
            throw new IntegrationException('A JSON request body is required.');
        }

        CARAOrderAttachmentPayload payload;
        try {
            payload = (CARAOrderAttachmentPayload) JSON.deserialize(requestBody, CARAOrderAttachmentPayload.class);
        } catch (Exception jsonException) {
            throw new IntegrationException('Invalid JSON payload: ' + jsonException.getMessage());
        }

        if (payload == null) {
            throw new IntegrationException('A valid attachment payload is required.');
        }
        return payload;
    }

    private static void validateRequiredFields(CARAOrderAttachmentPayload payload) {
        List<String> missingFields = new List<String>();

        if (String.isBlank(payload.orderReferenceNumber)) {
            missingFields.add('orderReferenceNumber');
        }
        if (payload.attachments == null || payload.attachments.isEmpty()) {
            missingFields.add('attachments');
        } else {
            for (Integer i = 0; i < payload.attachments.size(); i++) {
                CARAOrderAttachmentPayload.AttachmentItem item = payload.attachments[i];
                if (item == null || String.isBlank(item.fileName)) {
                    missingFields.add('attachments[' + i + '].fileName');
                }
                if (item == null || String.isBlank(item.fileContent)) {
                    missingFields.add('attachments[' + i + '].fileContent');
                }
            }
        }

        if (!missingFields.isEmpty()) {
            throw new IntegrationException('Missing required field(s): ' + String.join(missingFields, ', '));
        }
    }

    private static Order findOrder(String orderReferenceNumber) {
        List<Order> matchingOrders = [
            SELECT Id
            FROM Order
            WHERE OrderReferenceNumber = :orderReferenceNumber
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
        if (matchingOrders.isEmpty()) {
            throw new IntegrationException('No Order found with OrderReferenceNumber ' + orderReferenceNumber + '.');
        }
        if (matchingOrders.size() > 1) {
            throw new IntegrationException('Multiple Orders use OrderReferenceNumber ' + orderReferenceNumber + '.');
        }
        return matchingOrders[0];
    }

    private static List<Id> saveAttachments(Id orderId, List<CARAOrderAttachmentPayload.AttachmentItem> attachments) {
        List<ContentVersion> versionsToInsert = new List<ContentVersion>();
        for (CARAOrderAttachmentPayload.AttachmentItem item : attachments) {
            Blob fileData;
            try {
                fileData = EncodingUtil.base64Decode(item.fileContent);
            } catch (Exception decodeException) {
                throw new IntegrationException('Attachment ' + item.fileName + ' has invalid base64 fileContent.');
            }

            versionsToInsert.add(new ContentVersion(
                Title = item.fileName,
                PathOnClient = item.fileName,
                VersionData = fileData,
                Description = item.description
            ));
        }
        insert versionsToInsert;

        Set<Id> versionIds = (new Map<Id, ContentVersion>(versionsToInsert)).keySet();
        Map<Id, Id> documentIdByVersionId = new Map<Id, Id>();
        for (ContentVersion version : [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIds
        ]) {
            documentIdByVersionId.put(version.Id, version.ContentDocumentId);
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        List<Id> contentDocumentIds = new List<Id>();
        for (ContentVersion version : versionsToInsert) {
            Id documentId = documentIdByVersionId.get(version.Id);
            contentDocumentIds.add(documentId);
            linksToInsert.add(new ContentDocumentLink(
                ContentDocumentId = documentId,
                LinkedEntityId = orderId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }
        insert linksToInsert;

        return contentDocumentIds;
    }

    private static List<AttachmentSummary> listAttachments(Id orderId) {
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink linkRecord : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :orderId
        ]) {
            contentDocumentIds.add(linkRecord.ContentDocumentId);
        }

        List<AttachmentSummary> attachmentSummaries = new List<AttachmentSummary>();
        if (contentDocumentIds.isEmpty()) {
            return attachmentSummaries;
        }

        for (ContentVersion version : [
            SELECT Id, ContentDocumentId, Title, FileExtension, FileType, ContentSize, Description, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            AND IsLatest = true
            ORDER BY CreatedDate DESC
        ]) {
            attachmentSummaries.add(new AttachmentSummary(version));
        }
        return attachmentSummaries;
    }

    private static void writeResponse(
        Integer statusCode,
        Boolean success,
        String message,
        Id orderId,
        List<Id> contentDocumentIds
    ) {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }
        ResponseBody responseBody = new ResponseBody();
        responseBody.success = success;
        responseBody.message = message;
        responseBody.orderId = orderId;
        responseBody.contentDocumentIds = contentDocumentIds;

        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(responseBody));
    }

    private static void writeListResponse(
        Integer statusCode,
        Boolean success,
        String message,
        Id orderId,
        List<AttachmentSummary> attachments
    ) {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }
        AttachmentListResponse responseBody = new AttachmentListResponse();
        responseBody.success = success;
        responseBody.message = message;
        responseBody.orderId = orderId;
        responseBody.count = attachments.size();
        responseBody.attachments = attachments;

        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(responseBody));
    }

    private class ResponseBody {
        public Boolean success;
        public String message;
        public Id orderId;
        public List<Id> contentDocumentIds;
    }

    private class AttachmentListResponse {
        public Boolean success;
        public String message;
        public Id orderId;
        public Integer count;
        public List<AttachmentSummary> attachments;
    }

    private class AttachmentSummary {
        public Id contentDocumentId;
        public Id contentVersionId;
        public String fileName;
        public String fileExtension;
        public String fileType;
        public Integer contentSize;
        public String description;
        public Datetime createdDate;
        public String downloadUrl;

        private AttachmentSummary(ContentVersion version) {
            this.contentDocumentId = version.ContentDocumentId;
            this.contentVersionId = version.Id;
            this.fileName = version.Title;
            this.fileExtension = version.FileExtension;
            this.fileType = version.FileType;
            this.contentSize = version.ContentSize;
            this.description = version.Description;
            this.createdDate = version.CreatedDate;
            this.downloadUrl = '/services/data/' + REST_API_VERSION + '/sobjects/ContentVersion/' + version.Id + '/VersionData';
        }
    }

    private class IntegrationException extends Exception {
    }
}