@RestResource(urlMapping='/cara/chat/inbound')
global with sharing class CARAChatInboundRestService {
    @HttpPost
    global static void createInboundMessage() {
        try {
            InboundRequest payload = deserializeRequest();
            Id caseId = CARAChatApiSupport.requireCaseId(payload.caseId);
            String messageBody = CARAChatApiSupport.requireMessageBody(
                payload.messageBody
            );

            Chat_Message__c messageRecord = new Chat_Message__c(
                Case__c = caseId,
                Message_Body__c = messageBody,
                Direction__c = 'Inbound',
                Sender_Type__c = 'Storefront Customer'
            );
            Database.SaveResult saveResult = Database.insert(
                messageRecord,
                false
            );
            if (!saveResult.isSuccess()) {
                throw new CARAChatApiSupport.RequestException(
                    saveResult.getErrors()[0].getMessage()
                );
            }

            Chat_Message__c savedMessage = [
                SELECT
                    Id,
                    Case__c,
                    Message_Body__c,
                    Direction__c,
                    Sender_Type__c,
                    CreatedDate
                FROM Chat_Message__c
                WHERE Id = :saveResult.getId()
                LIMIT 1
            ];

            InboundResponse responseBody = new InboundResponse();
            responseBody.success = true;
            responseBody.message = 'Inbound chat message created.';
            responseBody.data = new CARAChatApiSupport.MessageResponse(
                savedMessage
            );
            CARAChatApiSupport.writeResponse(201, responseBody);
        } catch (CARAChatApiSupport.NotFoundException error) {
            CARAChatApiSupport.writeError(404, error.getMessage());
        } catch (CARAChatApiSupport.RequestException error) {
            CARAChatApiSupport.writeError(400, error.getMessage());
        } catch (Exception error) {
            CARAChatApiSupport.writeError(
                500,
                'Unable to create the inbound chat message.'
            );
        }
    }

    private static InboundRequest deserializeRequest() {
        if (
            RestContext.request == null ||
            RestContext.request.requestBody == null ||
            String.isBlank(RestContext.request.requestBody.toString())
        ) {
            throw new CARAChatApiSupport.RequestException(
                'A JSON request body is required.'
            );
        }

        try {
            InboundRequest payload = (InboundRequest) JSON.deserialize(
                RestContext.request.requestBody.toString(),
                InboundRequest.class
            );
            if (payload == null) {
                throw new CARAChatApiSupport.RequestException(
                    'A valid JSON request body is required.'
                );
            }
            return payload;
        } catch (CARAChatApiSupport.RequestException error) {
            throw error;
        } catch (Exception error) {
            throw new CARAChatApiSupport.RequestException(
                'Invalid JSON request body.'
            );
        }
    }

    private class InboundRequest {
        public String caseId;
        public String messageBody;
    }

    private class InboundResponse {
        public Boolean success;
        public String message;
        public CARAChatApiSupport.MessageResponse data;
    }
}