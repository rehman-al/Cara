@RestResource(urlMapping='/cara/chat/history')
global with sharing class CARAChatHistoryRestService {

    @HttpGet
    global static void getChatHistory() {
        try {
            String caseNumber = RestContext.request == null
                ? null
                : RestContext.request.params.get('caseNumber');

            Case caseRecord =
                CARAChatApiSupport.requireCaseByNumber(caseNumber);


            // Current database state.
            // This lets us detect 5 -> 6 or 50 -> 51 messages
            // instead of returning stale cached data.
            AggregateResult messageStats = [
                SELECT
                    COUNT(Id) messageCount,
                    MAX(LastModifiedDate) latestModified
                FROM Chat_Message__c
                WHERE Case__c = :caseRecord.Id
            ];

            Integer currentMessageCount =
                (Integer) messageStats.get('messageCount');

            Datetime latestModified =
                (Datetime) messageStats.get('latestModified');


            // Try Platform Cache first.
            List<Chat_Message__c> messageRecords =
                CARAChatHistoryCacheService.getCachedMessages(
                    caseRecord.Id,
                    currentMessageCount,
                    latestModified
                );


            // Cache miss / stale / >50 messages.
            if (messageRecords == null) {

                messageRecords = [
                    SELECT
                        Id,
                        Name,
                        Case__c,
                        Message_Body__c,
                        Direction__c,
                        Sender_Type__c,
                        CreatedDate,
                        LastModifiedDate
                    FROM Chat_Message__c
                    WHERE Case__c = :caseRecord.Id
                    ORDER BY CreatedDate ASC, Id ASC
                ];

                CARAChatHistoryCacheService.putMessages(
                    caseRecord.Id,
                    currentMessageCount,
                    latestModified,
                    messageRecords
                );
            }


            ChatHistoryResponse responseBody =
                new ChatHistoryResponse();

            responseBody.success = true;
            responseBody.caseNumber =
                caseRecord.CaseNumber;
            responseBody.totalMessages =
                messageRecords.size();
            responseBody.messages =
                new List<ChatMessageResponse>();


            Integer sequenceNumber = 1;

            for (
                Chat_Message__c messageRecord :
                messageRecords
            ) {
                responseBody.messages.add(
                    new ChatMessageResponse(
                        messageRecord,
                        sequenceNumber
                    )
                );

                sequenceNumber++;
            }


            CARAChatApiSupport.writeResponse(
                200,
                responseBody
            );

        } catch (
            CARAChatApiSupport.NotFoundException error
        ) {

            CARAChatApiSupport.writeError(
                404,
                error.getMessage()
            );

        } catch (
            CARAChatApiSupport.RequestException error
        ) {

            CARAChatApiSupport.writeError(
                400,
                error.getMessage()
            );

        } catch (Exception error) {

            System.debug(
                LoggingLevel.ERROR,
                'Chat history API error: ' +
                error.getMessage()
            );

            CARAChatApiSupport.writeError(
                500,
                'Unable to retrieve chat history.'
            );
        }
    }


    private class ChatHistoryResponse {
        public Boolean success;
        public String caseNumber;
        public Integer totalMessages;
        public List<ChatMessageResponse> messages;
    }


    private class ChatMessageResponse {
        public Integer sequence;
        public String messageId;
        public String senderType;
        public String direction;
        public String message;
        public Datetime timestamp;


        public ChatMessageResponse(
            Chat_Message__c messageRecord,
            Integer sequenceNumber
        ) {
            sequence = sequenceNumber;
            messageId = messageRecord.Name;
            senderType =
                messageRecord.Sender_Type__c;
            direction =
                messageRecord.Direction__c;
            message =
                messageRecord.Message_Body__c;
            timestamp =
                messageRecord.CreatedDate;
        }
    }
}