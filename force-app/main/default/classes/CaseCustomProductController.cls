public with sharing class CaseCustomProductController {

    private static final Set<String> VALID_CATEGORIES = new Set<String>{
        'Ring',
        'Bracelet',
        'Necklace',
        'Earring',
        'Pendant',
        'Watch',
        'Anklet',
        'Chain'
    };

    private static final Set<String> VALID_STATUSES = new Set<String>{
        'Draft',
        'Under Review',
        'Approved',
        'Rejected'
    };

    @AuraEnabled(cacheable=true)
    public static List<Custom_Product_Request__c> getRequests(Id caseId) {

        if (caseId == null) {
            return new List<Custom_Product_Request__c>();
        }

        try {

            ensureCaseAccessible(caseId);

            return [
                SELECT
                    Id,
                    Name,
                    Case__c,
                    Product_Name__c,
                    Description__c,
                    Category__c,
                    Quantity__c,
                    Dimensions__c,
                    Requested_Specification__c,
                    Estimated_Cost__c,
                    Selling_Price__c,
                    Status__c,
                    Product__c,
                    Product__r.Name,
                    Size__c,
                    Metal__c,
                    Diamond_Carat__c,
                    Diamond_Shape__c,
                    Diamond_Type__c,
                    Certification_Type_Requested__c,
                    CreatedDate,
                    LastModifiedDate
                FROM Custom_Product_Request__c
                WHERE Case__c = :caseId
                ORDER BY CreatedDate DESC
            ];

        } catch (AuraHandledException e) {
            throw e;

        } catch (Exception e) {

            throw handled(
                'Unable to load custom product requests.',
                e
            );
        }
    }


    @AuraEnabled
    public static Custom_Product_Request__c createRequest(
        Id caseId,
        Custom_Product_Request__c requestRecord
    ) {

        try {

            if (caseId == null) {
                throw userError(
                    'A Case is required.'
                );
            }

            validateRequest(requestRecord);

            ensureCaseAccessible(caseId);

            Custom_Product_Request__c recordToInsert =
                new Custom_Product_Request__c();

            recordToInsert.Case__c =
                caseId;

            recordToInsert.Product_Name__c =
                requestRecord.Product_Name__c;

            recordToInsert.Description__c =
                requestRecord.Description__c;

            recordToInsert.Category__c =
                requestRecord.Category__c;

            recordToInsert.Quantity__c =
                requestRecord.Quantity__c;

            recordToInsert.Dimensions__c =
                requestRecord.Dimensions__c;

            recordToInsert.Requested_Specification__c =
                requestRecord.Requested_Specification__c;

            recordToInsert.Estimated_Cost__c =
                requestRecord.Estimated_Cost__c;

            recordToInsert.Selling_Price__c =
                requestRecord.Selling_Price__c;

            recordToInsert.Status__c =
                String.isBlank(requestRecord.Status__c)
                    ? 'Draft'
                    : requestRecord.Status__c;

            recordToInsert.Size__c =
                requestRecord.Size__c;

            recordToInsert.Metal__c =
                requestRecord.Metal__c;

            recordToInsert.Diamond_Carat__c =
                requestRecord.Diamond_Carat__c;

            recordToInsert.Diamond_Shape__c =
                requestRecord.Diamond_Shape__c;

            recordToInsert.Diamond_Type__c =
                requestRecord.Diamond_Type__c;

            recordToInsert.Certification_Type_Requested__c =
                requestRecord.Certification_Type_Requested__c;

            recordToInsert.Product__c = resolveOrCreateProduct(
                requestRecord.Product__c,
                requestRecord.Product_Name__c,
                requestRecord.Description__c
            );

            Database.SaveResult result =
                Database.insert(
                    recordToInsert,
                    false
                );


            if (!result.isSuccess()) {

                throw dmlError(
                    'create',
                    result.getErrors()
                );
            }


            try {

                return getRequestById(
                    result.getId()
                );

            } catch (Exception e) {

                throw userError(
                    'Record was created successfully but failed while loading it.' +
                    ' | Record Id: ' +
                    result.getId() +
                    ' | Error Type: ' +
                    e.getTypeName() +
                    ' | Error: ' +
                    e.getMessage()
                );
            }

        } catch (AuraHandledException e) {

            throw e;

        } catch (Exception e) {

            throw handled(
                'Unable to create the custom product request.',
                e
            );
        }
    }


    @AuraEnabled
    public static Custom_Product_Request__c updateRequest(
        Custom_Product_Request__c requestRecord
    ) {

        try {

            if (
                requestRecord == null ||
                requestRecord.Id == null
            ) {
                throw userError(
                    'A request Id is required.'
                );
            }


            validateRequest(
                requestRecord
            );


            List<Custom_Product_Request__c> existingRecords = [
                SELECT
                    Id,
                    Case__c
                FROM Custom_Product_Request__c
                WHERE Id = :requestRecord.Id
                LIMIT 1
            ];


            if (existingRecords.isEmpty()) {

                throw userError(
                    'The custom product request was not found.'
                );
            }


            Custom_Product_Request__c recordToUpdate =
                existingRecords[0];


            ensureCaseAccessible(
                recordToUpdate.Case__c
            );


            recordToUpdate.Product_Name__c =
                requestRecord.Product_Name__c;

            recordToUpdate.Description__c =
                requestRecord.Description__c;

            recordToUpdate.Category__c =
                requestRecord.Category__c;

            recordToUpdate.Quantity__c =
                requestRecord.Quantity__c;

            recordToUpdate.Dimensions__c =
                requestRecord.Dimensions__c;

            recordToUpdate.Requested_Specification__c =
                requestRecord.Requested_Specification__c;

            recordToUpdate.Estimated_Cost__c =
                requestRecord.Estimated_Cost__c;

            recordToUpdate.Selling_Price__c =
                requestRecord.Selling_Price__c;

            recordToUpdate.Status__c =
                String.isBlank(requestRecord.Status__c)
                    ? 'Draft'
                    : requestRecord.Status__c;

            recordToUpdate.Size__c =
                requestRecord.Size__c;

            recordToUpdate.Metal__c =
                requestRecord.Metal__c;

            recordToUpdate.Diamond_Carat__c =
                requestRecord.Diamond_Carat__c;

            recordToUpdate.Diamond_Shape__c =
                requestRecord.Diamond_Shape__c;

            recordToUpdate.Diamond_Type__c =
                requestRecord.Diamond_Type__c;

            recordToUpdate.Certification_Type_Requested__c =
                requestRecord.Certification_Type_Requested__c;

            recordToUpdate.Product__c = resolveOrCreateProduct(
                requestRecord.Product__c,
                requestRecord.Product_Name__c,
                requestRecord.Description__c
            );

            Database.SaveResult result =
                Database.update(
                    recordToUpdate,
                    false
                );


            if (!result.isSuccess()) {

                throw dmlError(
                    'update',
                    result.getErrors()
                );
            }


            try {

                return getRequestById(
                    result.getId()
                );

            } catch (Exception e) {

                throw userError(
                    'Record was updated successfully but failed while reloading it.' +
                    ' | Record Id: ' +
                    result.getId() +
                    ' | Error Type: ' +
                    e.getTypeName() +
                    ' | Error: ' +
                    e.getMessage()
                );
            }

        } catch (AuraHandledException e) {

            throw e;

        } catch (Exception e) {

            throw handled(
                'Unable to update the custom product request.',
                e
            );
        }
    }


    @AuraEnabled
    public static void deleteRequest(
        Id requestId
    ) {

        try {

            if (requestId == null) {

                throw userError(
                    'A request Id is required.'
                );
            }


            List<Custom_Product_Request__c> existingRecords = [
                SELECT
                    Id,
                    Case__c
                FROM Custom_Product_Request__c
                WHERE Id = :requestId
                LIMIT 1
            ];


            if (existingRecords.isEmpty()) {

                throw userError(
                    'The custom product request was not found.'
                );
            }


            ensureCaseAccessible(
                existingRecords[0].Case__c
            );


            Database.DeleteResult result =
                Database.delete(
                    existingRecords[0],
                    false
                );


            if (!result.isSuccess()) {

                throw dmlError(
                    'delete',
                    result.getErrors()
                );
            }

        } catch (AuraHandledException e) {

            throw e;

        } catch (Exception e) {

            throw handled(
                'Unable to delete the custom product request.',
                e
            );
        }
    }


    @AuraEnabled
    public static List<CaseFile> getCaseFiles(Id caseId) {
        if (caseId == null || String.isBlank(caseId)) {
            return new List<CaseFile>();
        }

        try {
            ensureCaseAccessible(caseId);
            
            // Step 1: Collect document IDs
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :caseId]) {
                docIds.add(link.ContentDocumentId);
            }
            
            // Return early if no documents found
            List<CaseFile> result = new List<CaseFile>();
            if (docIds.isEmpty()) {
                return result;
            }
            
            // Step 2: Get file metadata
            for (ContentVersion version : [
                SELECT Id, ContentDocumentId, VersionDataUrl, Title, FileExtension, FileType
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds AND IsLatest = true
                ORDER BY CreatedDate DESC
            ]) {
                result.add(new CaseFile(version));
            }
            
            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled('Unable to load Case files.', e);
        }
    }


    @AuraEnabled
    public static List<CaseFile> getRequestFiles(Id requestId) {
        if (requestId == null || String.isBlank(requestId)) {
            return new List<CaseFile>();
        }

        try {
            // Validate case access
            List<Custom_Product_Request__c> requests = [SELECT Id, Case__c FROM Custom_Product_Request__c WHERE Id = :requestId LIMIT 1];
            if (requests.isEmpty()) {
                return new List<CaseFile>();
            }
            
            ensureCaseAccessible(requests[0].Case__c);
            
            // Step 1: Collect document IDs
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :requestId]) {
                docIds.add(link.ContentDocumentId);
            }
            
            // Return early if no documents found
            List<CaseFile> result = new List<CaseFile>();
            if (docIds.isEmpty()) {
                return result;
            }
            
            // Step 2: Get file metadata
            for (ContentVersion version : [
                SELECT Id, ContentDocumentId, VersionDataUrl, Title, FileExtension, FileType
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds AND IsLatest = true
                ORDER BY CreatedDate DESC
            ]) {
                result.add(new CaseFile(version));
            }
            
            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled('Unable to load custom product request files.', e);
        }
    }

    private static Id resolveOrCreateProduct(
        Id existingProductId,
        String productName,
        String description
    ) {
        if (existingProductId != null) {
            return existingProductId;
        }

        if (String.isBlank(productName)) {
            return null;
        }

        List<Product2> existingProducts = [
            SELECT Id
            FROM Product2
            WHERE Name = :productName
            LIMIT 1
        ];

        if (!existingProducts.isEmpty()) {
            return existingProducts[0].Id;
        }

        Product2 newProduct = new Product2(
            Name = productName,
            Description = description,
            IsActive = true,
            Is_Custom__c = true
        );
        insert newProduct;

        return newProduct.Id;
    }


    private static Custom_Product_Request__c getRequestById(
        Id requestId
    ) {

        try {

            List<Custom_Product_Request__c> records = [

                SELECT
                    Id,
                    Name,
                    Case__c,
                    Product_Name__c,
                    Description__c,
                    Category__c,
                    Quantity__c,
                    Dimensions__c,
                    Requested_Specification__c,
                    Estimated_Cost__c,
                    Selling_Price__c,
                    Status__c,
                    Product__c,
                    Product__r.Name,
                    Size__c,
                    Metal__c,
                    Diamond_Carat__c,
                    Diamond_Shape__c,
                    Diamond_Type__c,
                    Certification_Type_Requested__c,
                    CreatedDate,
                    LastModifiedDate

                FROM Custom_Product_Request__c

                WHERE Id = :requestId

                LIMIT 1
            ];


            if (records.isEmpty()) {

                throw userError(
                    'The record was not found.'
                );
            }


            return records[0];

        } catch (AuraHandledException e) {

            throw e;

        } catch (Exception e) {

            throw handled(
                'Unable to load request Id ' +
                String.valueOf(requestId) +
                '.',
                e
            );
        }
    }


    private static void ensureCaseAccessible(
        Id caseId
    ) {

        try {

            List<Case> cases = [

                SELECT Id

                FROM Case

                WHERE Id = :caseId

                LIMIT 1
            ];


            if (cases.isEmpty()) {

                throw userError(
                    'The Case was not found.'
                );
            }

        } catch (AuraHandledException e) {

            throw e;

        } catch (Exception e) {

            throw handled(
                'Unable to access Case ' +
                String.valueOf(caseId) +
                '.',
                e
            );
        }
    }


    private static void validateRequest(
        Custom_Product_Request__c requestRecord
    ) {

        if (requestRecord == null) {

            throw userError(
                'Request details are required.'
            );
        }


        if (
            String.isBlank(
                requestRecord.Product_Name__c
            )
        ) {

            throw userError(
                'Product Name is required.'
            );
        }


        if (
            requestRecord.Quantity__c == null ||
            requestRecord.Quantity__c <= 0
        ) {

            throw userError(
                'Quantity must be greater than zero.'
            );
        }


        if (
            requestRecord.Estimated_Cost__c != null &&
            requestRecord.Estimated_Cost__c < 0
        ) {

            throw userError(
                'Estimated Cost cannot be negative.'
            );
        }


        if (
            requestRecord.Selling_Price__c != null &&
            requestRecord.Selling_Price__c < 0
        ) {

            throw userError(
                'Selling Price cannot be negative.'
            );
        }


        if (
            !String.isBlank(
                requestRecord.Category__c
            ) &&
            !VALID_CATEGORIES.contains(
                requestRecord.Category__c
            )
        ) {

            throw userError(
                'Category is invalid.' +
                ' Received value: ' +
                requestRecord.Category__c
            );
        }


        if (
            !String.isBlank(
                requestRecord.Status__c
            ) &&
            !VALID_STATUSES.contains(
                requestRecord.Status__c
            )
        ) {

            throw userError(
                'Status is invalid.' +
                ' Received value: ' +
                requestRecord.Status__c
            );
        }
    }


    private static AuraHandledException dmlError(
        String operation,
        Database.Error[] errors
    ) {

        List<String> messages =
            new List<String>();


        if (errors != null) {

            for (
                Database.Error errorValue :
                errors
            ) {

                List<String> fieldNames =
                    new List<String>();


                if (
                    errorValue.getFields() != null
                ) {

                    fieldNames.addAll(
                        errorValue.getFields()
                    );
                }


                messages.add(

                    'StatusCode: ' +
                    String.valueOf(
                        errorValue.getStatusCode()
                    ) +

                    ' | Message: ' +
                    errorValue.getMessage() +

                    ' | Fields: ' +
                    String.join(
                        fieldNames,
                        ', '
                    )
                );
            }
        }


        String detail =
            messages.isEmpty()
                ? 'No additional DML error details were returned.'
                : String.join(
                    messages,
                    ' || '
                );


        return userError(

            'Unable to ' +
            operation +
            ' the custom product request.' +
            ' | ' +
            detail
        );
    }


    private static AuraHandledException handled(
        String message,
        Exception exceptionValue
    ) {

        String fullMessage =

            message +

            ' | Error Type: ' +
            exceptionValue.getTypeName() +

            ' | Error: ' +
            exceptionValue.getMessage() +

            ' | Line: ' +
            exceptionValue.getLineNumber();


        System.debug(
            LoggingLevel.ERROR,
            fullMessage
        );


        System.debug(
            LoggingLevel.ERROR,
            exceptionValue.getStackTraceString()
        );


        return userError(
            fullMessage
        );
    }


    private static AuraHandledException userError(
        String message
    ) {

        AuraHandledException exceptionValue =
            new AuraHandledException(
                message
            );


        exceptionValue.setMessage(
            message
        );


        return exceptionValue;
    }


    public class CaseFile {

        @AuraEnabled
        public Id contentDocumentId {
            get;
            set;
        }


        @AuraEnabled
        public Id latestPublishedVersionId {
            get;
            set;
        }


        @AuraEnabled
        public String fileName {
            get;
            set;
        }


        @AuraEnabled
        public String fileType {
            get;
            set;
        }


        @AuraEnabled
        public String previewUrl {
            get;
            set;
        }


        @AuraEnabled
        public Boolean isImage {
            get;
            set;
        }


        private CaseFile(ContentVersion version) {

            contentDocumentId = version.ContentDocumentId;

            latestPublishedVersionId = version.Id;

            fileType = version.FileType;

            isImage =
                String.isNotBlank(fileType) &&
                (
                    fileType.equalsIgnoreCase('PNG') ||
                    fileType.equalsIgnoreCase('JPG') ||
                    fileType.equalsIgnoreCase('JPEG') ||
                    fileType.equalsIgnoreCase('GIF') ||
                    fileType.equalsIgnoreCase('WEBP') ||
                    fileType.equalsIgnoreCase('BMP')
                );

            String extension = version.FileExtension;

            fileName =
                version.Title +
                (
                    String.isBlank(extension)
                        ? ''
                        : '.' + extension
                );

            previewUrl = version.VersionDataUrl;
        }
    }
}