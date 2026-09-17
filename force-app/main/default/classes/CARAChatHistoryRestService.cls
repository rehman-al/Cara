@RestResource(urlMapping='/cara/chat/messages')
global with sharing class CARAChatHistoryRestService {

    @HttpGet
    global static void getChatHistory() {
        try {
            String caseId = RestContext.request == null
                ? null
                : RestContext.request.params.get('caseId');

            Case caseRecord =
                CARAChatApiSupport.requireCaseById(caseId);


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
            responseBody.message =
                'Chat messages retrieved successfully.';
            responseBody.caseId =
                caseRecord.Id;
            responseBody.count =
                messageRecords.size();
            responseBody.messages =
                new List<CARAChatApiSupport.MessageResponse>();

            for (
                Chat_Message__c messageRecord :
                messageRecords
            ) {
                responseBody.messages.add(
                    new CARAChatApiSupport.MessageResponse(
                        messageRecord
                    )
                );
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
        public String message;
        public Id caseId;
        public Integer count;
        public List<CARAChatApiSupport.MessageResponse> messages;
    }
}