/**
 * Customer-facing controller for the Experience Cloud "Customise" wizard.
 * Runs for guest and authenticated community users. Object DML is performed
 * with AccessLevel.SYSTEM_MODE so the guest profile does not need to be
 * granted direct CRUD on Case / Custom_Product_Request__c / Customisation_Option__c
 * / Files — every input is validated server-side first.
 *
 * Category, Metal Type, Stone Type, Colour, Budget Guide and Timeline are all
 * CSR-managed via Customisation_Option__c records (Setup > Customisation
 * Options tab) rather than hardcoded picklists, so support staff can add or
 * retire options without an engineering deployment. This controller always
 * validates submissions against the live, active catalog.
 *
 * "without sharing": AccessLevel.SYSTEM_MODE only bypasses CRUD/FLS, not
 * record-level sharing. Guest-owned records are not visible even to the
 * same guest user under "with sharing" (Salesforce's guest record-access
 * hardening removes the owner's implicit access), which would block this
 * class from reading back the Case it just inserted. Every query here
 * only ever touches records this transaction itself created, or global/
 * catalog reference data — never an arbitrary caller-supplied Id — so this
 * is safe.
 *
 * Reference image uploads: Salesforce hard-blocks guest users from creating
 * Files (ContentVersion) themselves - AccessLevel.SYSTEM_MODE does not
 * bypass this, unlike ordinary CRUD/FLS/sharing checks, and it holds true
 * whether the insert is attempted synchronously or from a Queueable enqueued
 * by the guest (confirmed empirically; there is no supported profile or
 * permission-set grant that lifts it). The only reliable workaround is to
 * move the ContentVersion insert to a genuinely different running user, so
 * the image is instead staged as base64 chunks on Reference_Image_Chunk__c
 * (an ordinary custom object - guest can insert those without restriction)
 * and picked up by ReferenceImageChunkProcessor, a Scheduled Apex job that
 * runs every minute as whoever scheduled it (a real internal user, fixed
 * at schedule time - see that class for the one-time setup this requires
 * per org). Chunking exists because a Long Text Area field caps out at
 * 131,072 characters, far below the base64 size of a multi-MB photo.
 */
public without sharing class CustomiseRequestController {

    private static final String TYPE_CATEGORY = 'Category';
    private static final String TYPE_METAL = 'Metal Type';
    private static final String TYPE_STONE = 'Stone Type';
    private static final String TYPE_COLOR = 'Color';
    private static final String TYPE_BUDGET = 'Budget Guide';
    private static final String TYPE_TIMELINE = 'Timeline';

    private static final Set<String> VALID_CONTACT_METHODS = new Set<String>{
        'Email', 'Phone', 'WhatsApp'
    };

    private static final String SALES_FOLLOW_UP_RECORD_TYPE = 'Sales_Follow_up';
    private static final String CASE_TYPE_CUSTOMIZED_PRODUCT = 'Customized product';

    private static final Set<String> VALID_IMAGE_EXTENSIONS = new Set<String>{
        'png', 'jpg', 'jpeg', 'webp', 'gif'
    };

    private static final Integer MAX_FILE_BYTES = 4 * 1024 * 1024;
    private static final Integer CHUNK_SIZE_CHARS = 100000;

    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$');

    public class RequestException extends Exception {}

    public class CustomisationRequestInput {
        @AuraEnabled public String pieceType;
        @AuraEnabled public String briefType;
        @AuraEnabled public String description;
        @AuraEnabled public String preferredMetal;
        @AuraEnabled public String stoneType;
        @AuraEnabled public String color;
        @AuraEnabled public String budgetGuide;
        @AuraEnabled public String timeline;
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String preferredContactMethod;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileContentType;
        @AuraEnabled public String fileBase64;
    }

    public class CustomisationRequestResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public Boolean fileAttached = false;
        @AuraEnabled public String warning;
    }

    public class OptionItem {
        @AuraEnabled public String value;
        @AuraEnabled public String description;
        public OptionItem(String value, String description) {
            this.value = value;
            this.description = description;
        }
    }

    /**
     * Returns the active, CSR-managed catalog grouped by Option Type, for the
     * LWC to render its category cards / chip groups from. Cacheable so the
     * wizard only fetches this once per session.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<OptionItem>> getActiveOptions() {
        Map<String, List<OptionItem>> grouped = new Map<String, List<OptionItem>>();

        for (Customisation_Option__c opt : [
            SELECT Name, Option_Type__c, Description__c
            FROM Customisation_Option__c
            WHERE Is_Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Option_Type__c, Sort_Order__c ASC, Name ASC
        ]) {
            if (!grouped.containsKey(opt.Option_Type__c)) {
                grouped.put(opt.Option_Type__c, new List<OptionItem>());
            }
            grouped.get(opt.Option_Type__c).add(new OptionItem(opt.Name, opt.Description__c));
        }

        return grouped;
    }

    @AuraEnabled
    public static CustomisationRequestResult submitCustomisationRequestV2(String inputJson) {
        try {
            if (String.isBlank(inputJson)) {
                throw new RequestException('Request details are required.');
            }
            CustomisationRequestInput input = (CustomisationRequestInput) JSON.deserialize(inputJson, CustomisationRequestInput.class);
            validate(input);

            Case caseRecord = buildCase(input);

            Database.SaveResult caseResult = Database.insert(caseRecord, false, AccessLevel.SYSTEM_MODE);
            if (!caseResult.isSuccess()) {
                throw new RequestException('Unable to create your request. ' + firstErrorMessage(caseResult.getErrors()));
            }
            Id caseId = caseResult.getId();

            Custom_Product_Request__c requestRecord = buildRequest(input, caseId);
            Database.SaveResult requestResult = Database.insert(requestRecord, false, AccessLevel.SYSTEM_MODE);
            if (!requestResult.isSuccess()) {
                throw new RequestException('Unable to save your customisation details. ' + firstErrorMessage(requestResult.getErrors()));
            }
            Case insertedCase = [
                SELECT CaseNumber FROM Case WHERE Id = :caseId WITH SYSTEM_MODE LIMIT 1
            ];

            CustomisationRequestResult result = new CustomisationRequestResult();
            result.success = true;
            result.caseNumber = insertedCase.CaseNumber;

            if (String.isNotBlank(input.fileBase64)) {
                try {
                    stageReferenceImage(input, caseId);
                    result.fileAttached = true;
                } catch (Exception fileEx) {
                    result.fileAttached = false;
                    result.warning = 'Your request was received, but the reference image could not be attached. Our team will follow up with you directly.';
                    System.debug(LoggingLevel.ERROR, 'CustomiseRequestController file attach failed: ' + fileEx.getMessage());
                }
            }

            try {
                sendConfirmationEmail(input, result.caseNumber);
            } catch (Exception emailEx) {
                System.debug(LoggingLevel.ERROR, 'CustomiseRequestController confirmation email failed: ' + emailEx.getMessage());
            }

            return result;

        } catch (RequestException re) {
            throw userError(re.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CustomiseRequestController error: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            throw userError('We could not submit your request. Please try again.');
        }
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    private static void validate(CustomisationRequestInput input) {
        if (input == null) {
            throw new RequestException('Request details are required.');
        }
        if (String.isBlank(input.pieceType) || !activeOptionValues(TYPE_CATEGORY).contains(input.pieceType)) {
            throw new RequestException('Please choose what you would like to customise.');
        }
        if (String.isBlank(input.description)) {
            throw new RequestException('Please tell us a little about your vision.');
        }
        if (String.isNotBlank(input.preferredMetal) && !activeOptionValues(TYPE_METAL).contains(input.preferredMetal)) {
            throw new RequestException('Preferred metal is invalid.');
        }
        if (String.isNotBlank(input.stoneType) && !activeOptionValues(TYPE_STONE).contains(input.stoneType)) {
            throw new RequestException('Stone type is invalid.');
        }
        if (String.isNotBlank(input.color) && !activeOptionValues(TYPE_COLOR).contains(input.color)) {
            throw new RequestException('Colour is invalid.');
        }
        if (String.isNotBlank(input.budgetGuide) && !activeOptionValues(TYPE_BUDGET).contains(input.budgetGuide)) {
            throw new RequestException('Budget guide is invalid.');
        }
        if (String.isNotBlank(input.timeline) && !activeOptionValues(TYPE_TIMELINE).contains(input.timeline)) {
            throw new RequestException('Timeline is invalid.');
        }
        if (String.isBlank(input.fullName) || input.fullName.trim().length() < 2) {
            throw new RequestException('Please enter your full name.');
        }
        if (String.isBlank(input.email) || !EMAIL_PATTERN.matcher(input.email.trim()).matches()) {
            throw new RequestException('Please enter a valid email address.');
        }
        if (String.isNotBlank(input.preferredContactMethod) && !VALID_CONTACT_METHODS.contains(input.preferredContactMethod)) {
            throw new RequestException('Preferred contact method is invalid.');
        }
        if (String.isNotBlank(input.fileBase64)) {
            if (String.isBlank(input.fileName)) {
                throw new RequestException('The uploaded file is missing a name.');
            }
            String extension = input.fileName.contains('.')
                ? input.fileName.substringAfterLast('.').toLowerCase()
                : '';
            if (!VALID_IMAGE_EXTENSIONS.contains(extension)) {
                throw new RequestException('Reference images must be PNG, JPG, WEBP or GIF.');
            }
        }
    }

    private static Set<String> activeOptionValues(String optionType) {
        Set<String> values = new Set<String>();
        for (Customisation_Option__c opt : [
            SELECT Name
            FROM Customisation_Option__c
            WHERE Option_Type__c = :optionType AND Is_Active__c = true
            WITH SYSTEM_MODE
        ]) {
            values.add(opt.Name);
        }
        return values;
    }

    private static Case buildCase(CustomisationRequestInput input) {
        Case caseRecord = new Case();
        caseRecord.Subject = 'Customisation Request - ' + input.pieceType;
        caseRecord.Description = buildCaseDescription(input);
        caseRecord.Origin = 'Web';
        caseRecord.Type = CASE_TYPE_CUSTOMIZED_PRODUCT;
        caseRecord.SuppliedName = input.fullName.trim();
        caseRecord.SuppliedEmail = input.email.trim();
        if (String.isNotBlank(input.phone)) {
            caseRecord.SuppliedPhone = input.phone.trim();
        }
        caseRecord.Contact_Method_Preference__c = String.isNotBlank(input.preferredContactMethod)
            ? input.preferredContactMethod
            : 'Email';

        Id salesFollowUpRtId = salesFollowUpRecordTypeId();
        if (salesFollowUpRtId != null) {
            caseRecord.RecordTypeId = salesFollowUpRtId;
        }

        // Contact/Account matching or creation from SuppliedEmail now
        // happens org-wide in CaseCustomerMatchTrigger, so every Case
        // creation channel (this wizard included) gets the same behavior.
        return caseRecord;
    }

    private static String buildCaseDescription(CustomisationRequestInput input) {
        List<String> lines = new List<String>();
        lines.add('Piece: ' + input.pieceType);
        lines.add('Brief: ' + (String.isNotBlank(input.fileBase64) ? 'Reference image + notes' : 'Written brief'));
        lines.add('Description: ' + input.description.trim());
        if (String.isNotBlank(input.preferredMetal)) {
            lines.add('Preferred metal: ' + input.preferredMetal);
        }
        if (String.isNotBlank(input.stoneType)) {
            lines.add('Stone type: ' + input.stoneType);
        }
        if (String.isNotBlank(input.color)) {
            lines.add('Colour: ' + input.color);
        }
        if (String.isNotBlank(input.budgetGuide)) {
            lines.add('Budget guide: ' + input.budgetGuide);
        }
        if (String.isNotBlank(input.timeline)) {
            lines.add('Timeline: ' + input.timeline);
        }
        return String.join(lines, '\n');
    }

    private static Custom_Product_Request__c buildRequest(CustomisationRequestInput input, Id caseId) {
        Custom_Product_Request__c requestRecord = new Custom_Product_Request__c();
        requestRecord.Case__c = caseId;
        requestRecord.Product_Name__c = input.pieceType + ' Customisation';
        requestRecord.Description__c = input.description.trim();
        requestRecord.Quantity__c = 1;
        requestRecord.Status__c = 'Draft';
        requestRecord.Brief_Source__c = String.isNotBlank(input.fileBase64) ? 'Uploaded Reference' : 'Written Description';
        requestRecord.Piece_Type__c = input.pieceType;
        if (String.isNotBlank(input.preferredMetal)) {
            requestRecord.Preferred_Metal__c = input.preferredMetal;
        }
        if (String.isNotBlank(input.stoneType)) {
            requestRecord.Stone_Type__c = input.stoneType;
        }
        if (String.isNotBlank(input.color)) {
            requestRecord.Color__c = input.color;
        }
        if (String.isNotBlank(input.budgetGuide)) {
            requestRecord.Budget_Guide__c = input.budgetGuide;
        }
        if (String.isNotBlank(input.timeline)) {
            requestRecord.Timeline__c = input.timeline;
        }
        return requestRecord;
    }

    /**
     * Decodes/validates the image and stages it as Reference_Image_Chunk__c
     * rows (chunked to stay under the 131,072-character Long Text Area cap).
     * ReferenceImageChunkProcessor, running on its own schedule as a real
     * internal user, picks these up and inserts the actual ContentVersion.
     * See the class-level comment for why this exists.
     */
    private static void stageReferenceImage(CustomisationRequestInput input, Id caseId) {
        Blob fileBlob;
        try {
            fileBlob = EncodingUtil.base64Decode(input.fileBase64);
        } catch (Exception e) {
            throw new RequestException('The uploaded image could not be read.');
        }
        if (fileBlob == null || fileBlob.size() == 0) {
            throw new RequestException('The uploaded image could not be read.');
        }
        if (fileBlob.size() > MAX_FILE_BYTES) {
            throw new RequestException('Reference images must be smaller than 4MB.');
        }

        String base64Body = EncodingUtil.base64Encode(fileBlob);
        String uploadId = String.valueOf(caseId).left(15) + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));

        List<Reference_Image_Chunk__c> chunks = new List<Reference_Image_Chunk__c>();
        Integer chunkIndex = 0;
        for (Integer start = 0; start < base64Body.length(); start += CHUNK_SIZE_CHARS) {
            Integer stop = Math.min(start + CHUNK_SIZE_CHARS, base64Body.length());
            Reference_Image_Chunk__c chunk = new Reference_Image_Chunk__c();
            chunk.Case__c = caseId;
            chunk.Upload_Id__c = uploadId;
            chunk.Chunk_Index__c = chunkIndex;
            chunk.File_Name__c = input.fileName;
            chunk.Chunk_Data__c = base64Body.substring(start, stop);
            chunks.add(chunk);
            chunkIndex++;
        }

        Database.SaveResult[] chunkResults = Database.insert(chunks, false, AccessLevel.SYSTEM_MODE);
        for (Database.SaveResult chunkResult : chunkResults) {
            if (!chunkResult.isSuccess()) {
                throw new RequestException(firstErrorMessage(chunkResult.getErrors()));
            }
        }
    }

    private static void sendConfirmationEmail(CustomisationRequestInput input, String caseNumber) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[]{ input.email.trim() });
        email.setSubject('We\'ve received your custom ' + input.pieceType + ' request');
        email.setPlainTextBody(confirmationEmailBody(input, caseNumber));
        email.setHtmlBody(confirmationEmailHtmlBody(input, caseNumber));
        email.setSaveAsActivity(false);

        Id orgWideAddressId = firstVerifiedOrgWideEmailAddressId();
        if (orgWideAddressId != null) {
            email.setOrgWideEmailAddressId(orgWideAddressId);
        }

        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ email }, false);
    }

    private static String confirmationEmailBody(CustomisationRequestInput input, String caseNumber) {
        return 'Hi ' + input.fullName.trim() + ',\n\n' +
            'Thank you for telling us about your custom ' + input.pieceType + ' — we\'ve received your request.\n\n' +
            'Reference number: ' + caseNumber + '\n\n' +
            'Our designers will review your brief and be in touch within two business days to discuss your vision, materials and next steps.\n\n' +
            'Warm regards,\nThe Cara Jewellers Team';
    }

    /*
     * HTML counterpart of confirmationEmailBody(), sent alongside the plain
     * text version. Header/footer/nav links come from CARAEmailBrandingUtil,
     * the same shared source of truth used by the appointment confirmation
     * and payment-link emails. Public (rather than private) so sandbox QA
     * can render/send a one-off preview without exercising the full guest
     * submission pipeline (Case + file-chunk creation).
     */
    public static String confirmationEmailHtmlBody(CustomisationRequestInput input, String caseNumber) {
        String bodyRows =
            '<tr><td align="center" style="padding: 0 30px 20px 30px;">' +
            '<p style="margin: 0; font-family: \'Playfair Display\', Georgia, \'Times New Roman\', serif; font-weight: 700; font-size: 28px; line-height: 36px; text-align: center; text-transform: uppercase; color: #000000;">We\'ve received your request</p>' +
            '</td></tr>' +

            '<tr><td align="center" style="padding: 0 30px 25px 30px;">' +
            '<p style="margin: 0 0 10px 0; font-size: 16px; line-height: 22px; color: #000000;">Hi <b>' + input.fullName.trim() + '</b>,</p>' +
            '<p style="margin: 0; font-size: 16px; line-height: 22px; color: #000000;">Thank you for telling us about your custom ' + input.pieceType + ' — we\'ve received your request.</p>' +
            '</td></tr>' +

            '<tr><td style="padding: 0 20px 20px 20px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0"><tr>' +
            '<td align="left" style="background-color: #bfdde4; padding: 14px 16px; font-size: 16px; font-weight: 700; color: #000000;">Reference number &nbsp;#' + caseNumber + '</td>' +
            '</tr></table>' +
            '</td></tr>' +

            '<tr><td align="center" style="padding: 0 30px 25px 30px;">' +
            '<p style="margin: 0; font-size: 16px; line-height: 22px; color: #000000;">Our designers will review your brief and be in touch within two business days to discuss your vision, materials and next steps.</p>' +
            '</td></tr>' +

            CARAEmailBrandingUtil.divider();

        return CARAEmailBrandingUtil.wrapEmail(bodyRows);
    }

    private static Id firstVerifiedOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> addresses = [
            SELECT Id FROM OrgWideEmailAddress WHERE IsVerified = true WITH SYSTEM_MODE LIMIT 1
        ];
        return addresses.isEmpty() ? null : addresses[0].Id;
    }

    private static Id salesFollowUpRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName = :SALES_FOLLOW_UP_RECORD_TYPE AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static String firstErrorMessage(Database.Error[] errors) {
        if (errors == null || errors.isEmpty()) {
            return 'Please try again.';
        }
        return errors[0].getMessage();
    }
}