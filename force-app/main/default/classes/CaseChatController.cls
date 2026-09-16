public with sharing class CaseChatController {
    private static final Integer MAX_MESSAGE_LENGTH = 4000;

    @AuraEnabled(cacheable=true)
    public static ChatData getChatData(Id caseId) {
        ChatData result = new ChatData();
        result.messages = new List<ChatMessage>();

        if (caseId == null) {
            return result;
        }

        List<Case> cases = [
            SELECT Id, Account.Name
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (cases.isEmpty()) {
            throw userError('The Case was not found or is not accessible.');
        }

        result.accountName = cases[0].Account == null
            ? 'Case Customer'
            : cases[0].Account.Name;

        for (Chat_Message__c messageRecord : [
            SELECT
                Id,
                Message_Body__c,
                Direction__c,
                CreatedBy.Name,
                CreatedDate
            FROM Chat_Message__c
            WHERE Case__c = :caseId
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            result.messages.add(
                new ChatMessage(messageRecord, result.accountName)
            );
        }

        return result;
    }

    @AuraEnabled
    public static ChatMessage sendMessage(Id caseId, String messageBody) {
        if (caseId == null) {
            throw userError('A Case is required.');
        }

        String normalizedMessage = messageBody == null ? null : messageBody.trim();
        if (String.isBlank(normalizedMessage)) {
            throw userError('Enter a message before sending.');
        }
        if (normalizedMessage.length() > MAX_MESSAGE_LENGTH) {
            throw userError('Messages cannot exceed 4,000 characters.');
        }

        List<Case> cases = [
            SELECT Id, Account.Name
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw userError('The Case was not found or is not accessible.');
        }

        Chat_Message__c messageRecord = new Chat_Message__c(
            Case__c = caseId,
            Message_Body__c = normalizedMessage,
            Direction__c = 'Outbound',
            Sender_Type__c = 'Salesforce Agent'
        );

        try {
            Database.SaveResult saveResult = Database.insert(messageRecord, false);
            if (!saveResult.isSuccess()) {
                throw userError(saveResult.getErrors()[0].getMessage());
            }

            Chat_Message__c savedMessage = [
                SELECT
                    Id,
                    Message_Body__c,
                    Direction__c,
                    CreatedBy.Name,
                    CreatedDate
                FROM Chat_Message__c
                WHERE Id = :saveResult.getId()
                LIMIT 1
            ];
            String accountName = cases[0].Account == null
                ? 'Case Customer'
                : cases[0].Account.Name;
            return new ChatMessage(savedMessage, accountName);
        } catch (AuraHandledException error) {
            throw error;
        } catch (Exception error) {
            throw userError('Unable to send the message. ' + error.getMessage());
        }
    }

    private static AuraHandledException userError(String message) {
        return new AuraHandledException(message);
    }

    public class ChatData {
        @AuraEnabled
        public String accountName { get; set; }

        @AuraEnabled
        public List<ChatMessage> messages { get; set; }
    }

    public class ChatMessage {
        @AuraEnabled
        public Id id { get; set; }

        @AuraEnabled
        public String body { get; set; }

        @AuraEnabled
        public Datetime createdDate { get; set; }

        @AuraEnabled
        public String direction { get; set; }

        @AuraEnabled
        public String senderName { get; set; }

        public ChatMessage(
            Chat_Message__c messageRecord,
            String accountName
        ) {
            id = messageRecord.Id;
            body = messageRecord.Message_Body__c;
            createdDate = messageRecord.CreatedDate;
            direction = messageRecord.Direction__c == 'Inbound'
                ? 'Inbound'
                : 'Outbound';
            senderName = direction == 'Inbound'
                ? accountName
                : messageRecord.CreatedBy.Name;
        }
    }
}