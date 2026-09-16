@RestResource(urlMapping='/cara/chat/messages')
global with sharing class CARAChatMessagesRestService {
    @HttpGet
    global static void getMessagesByCase() {
        try {
            Id caseId = CARAChatApiSupport.requireCaseId(RestContext.request.params.get('caseId'));

            List<Chat_Message__c> messageRecords = [
                SELECT
                    Id,
                    Case__c,
                    Message_Body__c,
                    Direction__c,
                    Sender_Type__c,
                    CreatedDate
                FROM Chat_Message__c
                WHERE Case__c = :caseId
                ORDER BY CreatedDate ASC, Id ASC
            ];

            List<CARAChatApiSupport.MessageResponse> messages = new List<CARAChatApiSupport.MessageResponse>();
            for (Chat_Message__c messageRecord : messageRecords) {
                messages.add(new CARAChatApiSupport.MessageResponse(messageRecord));
            }

            ChatListResponse responseBody = new ChatListResponse();
            responseBody.success = true;
            responseBody.message = 'Chat messages retrieved successfully.';
            responseBody.caseId = caseId;
            responseBody.count = messages.size();
            responseBody.messages = messages;
            CARAChatApiSupport.writeResponse(200, responseBody);
        } catch (CARAChatApiSupport.NotFoundException error) {
            CARAChatApiSupport.writeError(404, error.getMessage());
        } catch (CARAChatApiSupport.RequestException error) {
            CARAChatApiSupport.writeError(400, error.getMessage());
        } catch (Exception error) {
            CARAChatApiSupport.writeError(500, 'Unable to retrieve chat messages.');
        }
    }

    private class ChatListResponse {
        public Boolean success;
        public String message;
        public Id caseId;
        public Integer count;
        public List<CARAChatApiSupport.MessageResponse> messages;
    }
}
