@IsTest
private class CaseCustomProductControllerTest {
    @TestSetup
    static void setupData() {
        insert new Case(Subject = 'Custom product test', Origin = 'Phone', Status = 'New');
    }

    @IsTest
    static void supportsCrudAndMultipleRequests() {
        Case caseRecord = [SELECT Id FROM Case LIMIT 1];
        Product2 product = new Product2(Name = 'Existing Product', IsActive = true);
        insert product;

        Test.startTest();
        Custom_Product_Request__c first = CaseCustomProductController.createRequest(
            caseRecord.Id,
            new Custom_Product_Request__c(
                Product_Name__c = 'Configured Widget',
                Category__c = 'Custom',
                Quantity__c = 2,
                Estimated_Cost__c = 10,
                Selling_Price__c = 15,
                Product__c = product.Id
            )
        );
        Custom_Product_Request__c second = CaseCustomProductController.createRequest(
            caseRecord.Id,
            new Custom_Product_Request__c(
                Product_Name__c = 'Implementation Service',
                Category__c = 'Service',
                Quantity__c = 1
            )
        );
        List<Custom_Product_Request__c> requests = CaseCustomProductController.getRequests(
            caseRecord.Id
        );
        Test.stopTest();

        Assert.areEqual(2, requests.size(), 'A Case should support multiple requests.');
        Assert.areEqual('Draft', first.Status__c, 'New requests should default to Draft.');
        Assert.areEqual(product.Id, first.Product__c, 'An existing Product can be linked.');

        first.Product_Name__c = 'Updated Widget';
        first.Quantity__c = 3;
        first.Status__c = 'Under Review';
        Custom_Product_Request__c updated = CaseCustomProductController.updateRequest(first);
        Assert.areEqual('Updated Widget', updated.Product_Name__c);
        Assert.areEqual(3, updated.Quantity__c);
        Assert.areEqual('Under Review', updated.Status__c);

        CaseCustomProductController.deleteRequest(second.Id);
        Assert.areEqual(
            1,
            CaseCustomProductController.getRequests(caseRecord.Id).size(),
            'Delete should remove only the selected request.'
        );
    }

    @IsTest
    static void returnsEmptyResults() {
        Case caseRecord = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<Custom_Product_Request__c> requests = CaseCustomProductController.getRequests(
            caseRecord.Id
        );
        List<CaseCustomProductController.CaseFile> files = CaseCustomProductController.getCaseFiles(
            caseRecord.Id
        );
        Test.stopTest();

        Assert.areEqual(0, requests.size());
        Assert.areEqual(0, files.size());
        Assert.areEqual(0, CaseCustomProductController.getRequests(null).size());
    }

    @IsTest
    static void returnsCaseFilesWithoutCopyingThem() {
        Case caseRecord = [SELECT Id FROM Case LIMIT 1];
        ContentVersion version = new ContentVersion(
            Title = 'requirements',
            PathOnClient = 'requirements.pdf',
            VersionData = Blob.valueOf('test file'),
            FirstPublishLocationId = caseRecord.Id
        );
        insert version;
        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];

        Test.startTest();
        List<CaseCustomProductController.CaseFile> files = CaseCustomProductController.getCaseFiles(
            caseRecord.Id
        );
        Test.stopTest();

        Assert.areEqual(1, files.size());
        Assert.areEqual(version.ContentDocumentId, files[0].contentDocumentId);
        Assert.areEqual('requirements.pdf', files[0].fileName);
        Assert.areEqual('PDF', files[0].fileType);
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM ContentDocument WHERE Id = :version.ContentDocumentId],
            'The original Case file should be referenced, not duplicated.'
        );
    }

    @IsTest
    static void returnsFilesLinkedToCustomProductRequests() {
        Case caseRecord = [SELECT Id FROM Case LIMIT 1];
        Custom_Product_Request__c request = CaseCustomProductController.createRequest(
            caseRecord.Id,
            new Custom_Product_Request__c(
                Product_Name__c = 'Sample Product',
                Quantity__c = 1
            )
        );

        ContentVersion version = new ContentVersion(
            Title = 'product-image',
            PathOnClient = 'product-image.png',
            VersionData = Blob.valueOf('image data'),
            FirstPublishLocationId = request.Id
        );
        insert version;

        Test.startTest();
        List<CaseCustomProductController.CaseFile> files = CaseCustomProductController.getRequestFiles(
            request.Id
        );
        Test.stopTest();

        Assert.areEqual(1, files.size(), 'Each custom product request should track its own files.');
        Assert.areEqual('product-image.png', files[0].fileName);
    }

    @IsTest
    static void rejectsInvalidInputs() {
        Case caseRecord = [SELECT Id FROM Case LIMIT 1];

        assertCreateFails(caseRecord.Id, new Custom_Product_Request__c(Quantity__c = 1), 'Product Name');
        assertCreateFails(
            caseRecord.Id,
            new Custom_Product_Request__c(Product_Name__c = 'Invalid', Quantity__c = 0),
            'Quantity'
        );
        assertCreateFails(
            caseRecord.Id,
            new Custom_Product_Request__c(
                Product_Name__c = 'Invalid',
                Quantity__c = 1,
                Estimated_Cost__c = -1
            ),
            'Estimated Cost'
        );
        assertCreateFails(
            caseRecord.Id,
            new Custom_Product_Request__c(
                Product_Name__c = 'Invalid',
                Quantity__c = 1,
                Selling_Price__c = -1
            ),
            'Selling Price'
        );
        assertCreateFails(
            caseRecord.Id,
            new Custom_Product_Request__c(
                Product_Name__c = 'Invalid',
                Quantity__c = 1,
                Status__c = 'Unknown'
            ),
            'Status'
        );

        try {
            CaseCustomProductController.deleteRequest(null);
            Assert.fail('A null Id should fail.');
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains('Id'));
        }
    }

    private static void assertCreateFails(
        Id caseId,
        Custom_Product_Request__c requestRecord,
        String expectedMessage
    ) {
        try {
            CaseCustomProductController.createRequest(caseId, requestRecord);
            Assert.fail('Invalid input should fail.');
        } catch (AuraHandledException expected) {
            Assert.isTrue(
                expected.getMessage().contains(expectedMessage),
                'Expected error to mention ' + expectedMessage
            );
        }
    }
}