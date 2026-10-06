@isTest
private class CustomiseRequestControllerTest {

    @TestSetup
    static void setupCatalog() {
        Database.insert(new List<Customisation_Option__c>{
            new Customisation_Option__c(Name = 'Engagement Ring', Option_Type__c = 'Category', Is_Active__c = true),
            new Customisation_Option__c(Name = 'Retired Category', Option_Type__c = 'Category', Is_Active__c = false),
            new Customisation_Option__c(Name = 'Rose Gold', Option_Type__c = 'Metal Type', Is_Active__c = true),
            new Customisation_Option__c(Name = 'Emerald', Option_Type__c = 'Stone Type', Is_Active__c = true),
            new Customisation_Option__c(Name = 'Green', Option_Type__c = 'Color', Is_Active__c = true),
            new Customisation_Option__c(Name = 'AED 25,000 - 50,000', Option_Type__c = 'Budget Guide', Is_Active__c = true),
            new Customisation_Option__c(Name = 'Within 3 months', Option_Type__c = 'Timeline', Is_Active__c = true)
        }, AccessLevel.SYSTEM_MODE);
    }

    private static CustomiseRequestController.CustomisationRequestInput baseInput() {
        CustomiseRequestController.CustomisationRequestInput input =
            new CustomiseRequestController.CustomisationRequestInput();
        input.pieceType = 'Engagement Ring';
        input.description = 'A rose gold ring with an emerald centre stone, inspired by vintage settings.';
        input.preferredMetal = 'Rose Gold';
        input.stoneType = 'Emerald';
        input.color = 'Green';
        input.budgetGuide = 'AED 25,000 - 50,000';
        input.timeline = 'Within 3 months';
        input.fullName = 'Jane Doe';
        input.email = 'jane.doe@example.com';
        input.phone = '+971500000000';
        input.preferredContactMethod = 'WhatsApp';
        return input;
    }

    @isTest
    static void testSubmitSuccessWithoutFile() {
        Test.startTest();
        CustomiseRequestController.CustomisationRequestResult result =
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(baseInput()));
        Test.stopTest();

        System.assertEquals(true, result.success, 'Expected submission to succeed.');
        System.assertNotEquals(null, result.caseNumber, 'Expected a Case number to be returned.');
        System.assertEquals(false, result.fileAttached, 'No file was submitted.');

        Case createdCase = [
            SELECT Id, Subject, Origin, SuppliedEmail, Type, RecordType.DeveloperName, ContactId, AccountId
            FROM Case
            LIMIT 1
        ];
        System.assertEquals('Web', createdCase.Origin);
        System.assertEquals('jane.doe@example.com', createdCase.SuppliedEmail);
        System.assertEquals('Customized product', createdCase.Type, 'Case Type should be set for the custom product LWC visibility rule.');
        System.assertEquals('Sales_Follow_up', createdCase.RecordType.DeveloperName, 'Case should use the Sales Follow-up record type.');
        System.assertNotEquals(null, createdCase.ContactId, 'No Contact matched this email, so the Person Account contact should be attached.');
        System.assertNotEquals(null, createdCase.AccountId, 'The newly created Person Account should be attached too.');

        Contact createdContact = [SELECT Email FROM Contact WHERE Id = :createdCase.ContactId];
        System.assertEquals('jane.doe@example.com', createdContact.Email, 'New Contact should carry the Case\'s supplied email.');

        Custom_Product_Request__c request = [SELECT Id, Case__c FROM Custom_Product_Request__c LIMIT 1];
        System.assertEquals(createdCase.Id, request.Case__c);
    }

    @isTest
    static void testSubmitAttachesMatchingContactAndAccount() {
        Account existingAccount = new Account(Name = 'Doe Household');
        Database.insert(existingAccount, AccessLevel.SYSTEM_MODE);
        Contact existingContact = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'jane.doe@example.com',
            AccountId = existingAccount.Id
        );
        Database.insert(existingContact, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(baseInput()));
        Test.stopTest();

        Case createdCase = [SELECT Id, ContactId, AccountId FROM Case LIMIT 1];
        System.assertEquals(existingContact.Id, createdCase.ContactId, 'Case should be attached to the matching Contact.');
        System.assertEquals(existingAccount.Id, createdCase.AccountId, 'Case should inherit the Contact\'s Account.');
    }

    @isTest
    static void testSubmitSuccessWithFile() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.fileName = 'inspiration.png';
        input.fileContentType = 'image/png';
        input.fileBase64 = EncodingUtil.base64Encode(Blob.valueOf('fake-image-bytes'));

        Test.startTest();
        CustomiseRequestController.CustomisationRequestResult result =
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(true, result.fileAttached);
        System.assertEquals(1, [SELECT COUNT() FROM Reference_Image_Chunk__c], 'Image should be staged pending the scheduled processor.');

        ReferenceImageChunkProcessor.processPendingUploads();

        Case createdCase = [SELECT Id FROM Case LIMIT 1];
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :createdCase.Id];
        System.assertEquals(1, links.size(), 'Expected the uploaded file to be linked to the Case once the scheduled processor runs.');

        System.assertEquals(0, [SELECT COUNT() FROM Reference_Image_Chunk__c], 'Staging chunks should be cleaned up once the image is attached.');
    }

    @isTest
    static void testSubmitAsGuestUserSucceedsWithoutDirectObjectAccess() {
        Profile guestProfile = [SELECT Id FROM Profile WHERE Name = 'Marketing Landing Pages Profile' LIMIT 1];
        User guestUser = [SELECT Id FROM User WHERE ProfileId = :guestProfile.Id AND IsActive = true LIMIT 1];

        System.runAs(guestUser) {
            CustomiseRequestController.CustomisationRequestResult result =
                CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(baseInput()));
            System.assertEquals(true, result.success, 'Guest user should be able to submit via SYSTEM_MODE DML.');
        }

        Case createdCase = [
            SELECT AccountId, ContactId, Account.IsPersonAccount, Account.PersonContactId
            FROM Case
            LIMIT 1
        ];
        System.assertEquals(
            true,
            createdCase.Account.IsPersonAccount,
            'A guest-created customer should be a Person Account.'
        );
        System.assertEquals(
            createdCase.Account.PersonContactId,
            createdCase.ContactId,
            'The Case should use the Person Account contact.'
        );
    }

    @isTest
    static void testSubmitAsGuestUserWithFileAttachesSuccessfully() {
        Profile guestProfile = [SELECT Id FROM Profile WHERE Name = 'Marketing Landing Pages Profile' LIMIT 1];
        User guestUser = [SELECT Id FROM User WHERE ProfileId = :guestProfile.Id AND IsActive = true LIMIT 1];

        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.fileName = 'inspiration.png';
        input.fileContentType = 'image/png';
        input.fileBase64 = EncodingUtil.base64Encode(Blob.valueOf('fake-image-bytes'));

        CustomiseRequestController.CustomisationRequestResult result;
        System.runAs(guestUser) {
            Test.startTest();
            result = CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            Test.stopTest();
        }

        System.assertEquals(true, result.success, 'Guest submission with a file should succeed.');
        System.assertEquals(true, result.fileAttached, 'File should be staged for attachment as guest.');
        System.assertEquals(null, result.warning, 'No warning expected when the file is staged successfully.');

        // Runs as the current (non-guest) test user, mirroring how the scheduled
        // processor runs as a real internal user in production - never as guest.
        ReferenceImageChunkProcessor.processPendingUploads();

        Case createdCase = [SELECT Id FROM Case LIMIT 1];
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :createdCase.Id WITH SYSTEM_MODE];
        System.assertEquals(1, links.size(), 'Expected the reference image to be linked to the Case once the scheduled processor runs.');
    }

    @isTest
    static void testLargeFileIsChunkedAndReassembled() {
        Profile guestProfile = [SELECT Id FROM Profile WHERE Name = 'Marketing Landing Pages Profile' LIMIT 1];
        User guestUser = [SELECT Id FROM User WHERE ProfileId = :guestProfile.Id AND IsActive = true LIMIT 1];

        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.fileName = 'large-inspiration.jpg';
        input.fileContentType = 'image/jpeg';
        String largeContent = 'x'.repeat(250000);
        input.fileBase64 = EncodingUtil.base64Encode(Blob.valueOf(largeContent));

        CustomiseRequestController.CustomisationRequestResult result;
        System.runAs(guestUser) {
            Test.startTest();
            result = CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            Test.stopTest();
        }

        System.assertEquals(true, result.fileAttached, 'A file spanning multiple chunks should still stage.');
        System.assert([SELECT COUNT() FROM Reference_Image_Chunk__c] > 1, 'A 250,000-char base64 body should span more than one chunk.');

        ReferenceImageChunkProcessor.processPendingUploads();

        Case createdCase = [SELECT Id FROM Case LIMIT 1];
        List<ContentVersion> versions = [
            SELECT Id, ContentSize FROM ContentVersion
            WHERE FirstPublishLocationId = :createdCase.Id
            WITH SYSTEM_MODE
        ];
        System.assertEquals(1, versions.size(), 'Expected exactly one reassembled ContentVersion.');
        System.assertEquals(largeContent.length(), versions[0].ContentSize, 'Reassembled file size should match the original.');
    }

    @isTest
    static void testGetActiveOptionsReturnsOnlyActiveGroupedByType() {
        Test.startTest();
        Map<String, List<CustomiseRequestController.OptionItem>> options =
            CustomiseRequestController.getActiveOptions();
        Test.stopTest();

        System.assert(options.containsKey('Category'), 'Expected a Category group.');
        Set<String> categoryValues = new Set<String>();
        for (CustomiseRequestController.OptionItem item : options.get('Category')) {
            categoryValues.add(item.value);
        }
        System.assert(categoryValues.contains('Engagement Ring'), 'Active category should be returned.');
        System.assert(!categoryValues.contains('Retired Category'), 'Inactive category should not be returned.');
    }

    @isTest
    static void testMissingPieceTypeThrows() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.pieceType = null;

        try {
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            System.assert(false, 'Expected an exception for a missing piece type.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testUnknownCategoryThrows() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.pieceType = 'Cufflinks';

        try {
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            System.assert(false, 'Expected an exception for a category not in the active catalog.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testRetiredCategoryThrows() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.pieceType = 'Retired Category';

        try {
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            System.assert(false, 'Expected an exception for a retired (inactive) category.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testBlankDescriptionThrows() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.description = '   ';

        try {
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            System.assert(false, 'Expected an exception for a blank description.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testSingleCharacterDescriptionSucceeds() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.description = 'x';

        Test.startTest();
        CustomiseRequestController.CustomisationRequestResult result = CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
        Test.stopTest();

        System.assertNotEquals(null, result, 'A single-character description should be accepted.');
    }

    @isTest
    static void testInvalidEmailThrows() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.email = 'not-an-email';

        try {
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            System.assert(false, 'Expected an exception for an invalid email.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testMissingNameThrows() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.fullName = '';

        try {
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            System.assert(false, 'Expected an exception for a missing name.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testInvalidFileExtensionThrows() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.fileName = 'malicious.exe';
        input.fileBase64 = EncodingUtil.base64Encode(Blob.valueOf('not-an-image'));

        try {
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            System.assert(false, 'Expected an exception for a disallowed file type.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testInvalidContactMethodThrows() {
        CustomiseRequestController.CustomisationRequestInput input = baseInput();
        input.preferredContactMethod = 'Carrier Pigeon';

        try {
            CustomiseRequestController.submitCustomisationRequestV2(JSON.serialize(input));
            System.assert(false, 'Expected an exception for an invalid contact method.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
