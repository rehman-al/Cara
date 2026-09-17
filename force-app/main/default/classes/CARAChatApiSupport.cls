public with sharing class CARAChatApiSupport {
    public static final Integer MAX_MESSAGE_LENGTH = 4000;

    public static Id requireCaseId(String caseIdValue) {
        if (String.isBlank(caseIdValue)) {
            throw new RequestException('caseId is required.');
        }

        Id caseId;
        try {
            caseId = Id.valueOf(caseIdValue.trim());
        } catch (Exception error) {
            throw new RequestException('caseId must be a valid Salesforce Case Id.');
        }

        if (caseId.getSObjectType() != Case.SObjectType) {
            throw new RequestException('caseId must identify a Case record.');
        }

        List<Case> cases = [
            SELECT Id
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw new NotFoundException(
                'The Case was not found or is not accessible.'
            );
        }

        return caseId;
    }
    public static Case requireCaseByNumber(String caseNumberValue) {
    String caseNumber = caseNumberValue == null
        ? null
        : caseNumberValue.trim();

    if (String.isBlank(caseNumber)) {
        throw new RequestException('caseNumber is required.');
    }

    List<Case> cases = [
        SELECT Id, CaseNumber
        FROM Case
        WHERE CaseNumber = :caseNumber
        LIMIT 1
    ];

    if (cases.isEmpty()) {
        throw new NotFoundException(
            'The Case was not found or is not accessible.'
        );
    }

    return cases[0];
    }

    public static Case requireCaseById(String caseIdValue) {
        Id caseId = requireCaseId(caseIdValue);

        List<Case> cases = [
            SELECT Id, CaseNumber
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (cases.isEmpty()) {
            throw new NotFoundException(
                'The Case was not found or is not accessible.'
            );
        }

        return cases[0];
    }

    public static String requireMessageBody(String messageBody) {
        String normalizedBody = messageBody == null ? null : messageBody.trim();
        if (String.isBlank(normalizedBody)) {
            throw new RequestException('messageBody is required.');
        }
        if (normalizedBody.length() > MAX_MESSAGE_LENGTH) {
            throw new RequestException(
                'messageBody cannot exceed 4,000 characters.'
            );
        }
        return normalizedBody;
    }

    public static void writeResponse(Integer statusCode, Object responseBody) {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.addHeader('Cache-Control', 'no-store');
        RestContext.response.responseBody = Blob.valueOf(
            JSON.serialize(responseBody)
        );
    }

    public static void writeError(Integer statusCode, String message) {
        ErrorResponse responseBody = new ErrorResponse();
        responseBody.success = false;
        responseBody.message = message;
        writeResponse(statusCode, responseBody);
    }

    public class MessageResponse {
        public Id id;
        public Id caseId;
        public String body;
        public String direction;
        public String senderType;
        public Datetime createdDate;

        public MessageResponse(Chat_Message__c messageRecord) {
            id = messageRecord.Id;
            caseId = messageRecord.Case__c;
            body = messageRecord.Message_Body__c;
            direction = messageRecord.Direction__c;
            senderType = messageRecord.Sender_Type__c;
            createdDate = messageRecord.CreatedDate;
        }
    }

    public class ErrorResponse {
        public Boolean success;
        public String message;
    }

    public class RequestException extends Exception {
    }

    public class NotFoundException extends Exception {
    }
}