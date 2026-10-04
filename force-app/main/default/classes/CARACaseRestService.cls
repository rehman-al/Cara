@RestResource(urlMapping='/cara/cases')
global with sharing class CARACaseRestService {
    private static final String GENERAL_ENQUIRY_RECORD_TYPE = 'General_Enquiry';

    @HttpGet
    global static void getCasesByAccount() {
        try {
            Id accountId = resolveAccountIdFromEmail(RestContext.request.params.get('email'));

            List<Case> caseRecords = [
                SELECT
                    Id,
                    CaseNumber,
                    Subject,
                    Status,
                    Origin,
                    Priority,
                    Type,
                    Reason,
                    Description,
                    IsClosed,
                    CreatedDate,
                    ClosedDate
                FROM Case
                WHERE AccountId = :accountId
                AND RecordType.DeveloperName = :GENERAL_ENQUIRY_RECORD_TYPE
                ORDER BY CreatedDate DESC
            ];

            List<CaseSummary> caseSummaries = new List<CaseSummary>();
            for (Case caseRecord : caseRecords) {
                caseSummaries.add(new CaseSummary(caseRecord));
            }

            CaseListResponse responseBody = new CaseListResponse();
            responseBody.success = true;
            responseBody.message = 'Cases retrieved successfully.';
            responseBody.accountId = accountId;
            responseBody.count = caseSummaries.size();
            responseBody.cases = caseSummaries;
            CARAChatApiSupport.writeResponse(200, responseBody);
        } catch (CARAChatApiSupport.NotFoundException error) {
            CARAChatApiSupport.writeError(404, error.getMessage());
        } catch (CARAChatApiSupport.RequestException error) {
            CARAChatApiSupport.writeError(400, error.getMessage());
        } catch (Exception error) {
            CARAChatApiSupport.writeError(500, 'Unable to retrieve cases.');
        }
    }

    private static Id resolveAccountIdFromEmail(String emailValue) {
        if (String.isBlank(emailValue)) {
            throw new CARAChatApiSupport.RequestException('email is required.');
        }

        String emailAddress = emailValue.trim().toLowerCase();
        List<Contact> matchingContacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Email = :emailAddress
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];

        if (matchingContacts.isEmpty()) {
            throw new CARAChatApiSupport.NotFoundException('No customer was found for the given email.');
        }
        if (matchingContacts.size() > 1) {
            throw new CARAChatApiSupport.RequestException('Multiple contacts use customer email ' + emailAddress + '.');
        }

        Id accountId = matchingContacts[0].AccountId;
        if (accountId == null) {
            throw new CARAChatApiSupport.NotFoundException('The customer is not associated with an Account.');
        }

        return accountId;
    }

    private class CaseSummary {
        public Id id;
        public String caseNumber;
        public String subject;
        public String status;
        public String origin;
        public String priority;
        public String type;
        public String reason;
        public String description;
        public Boolean isClosed;
        public Datetime createdDate;
        public Datetime closedDate;

        public CaseSummary(Case caseRecord) {
            id = caseRecord.Id;
            caseNumber = caseRecord.CaseNumber;
            subject = caseRecord.Subject;
            status = caseRecord.Status;
            origin = caseRecord.Origin;
            priority = caseRecord.Priority;
            type = caseRecord.Type;
            reason = caseRecord.Reason;
            description = caseRecord.Description;
            isClosed = caseRecord.IsClosed;
            createdDate = caseRecord.CreatedDate;
            closedDate = caseRecord.ClosedDate;
        }
    }

    private class CaseListResponse {
        public Boolean success;
        public String message;
        public Id accountId;
        public Integer count;
        public List<CaseSummary> cases;
    }
}