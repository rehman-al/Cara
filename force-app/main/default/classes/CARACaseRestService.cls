@RestResource(urlMapping='/cara/cases')
global with sharing class CARACaseRestService {
    @HttpGet
    global static void getCasesByAccount() {
        try {
            Id accountId = requireAccountId(RestContext.request.params.get('accountId'));
            requireAccountExists(accountId);

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

    private static Id requireAccountId(String accountIdValue) {
        if (String.isBlank(accountIdValue)) {
            throw new CARAChatApiSupport.RequestException('accountId is required.');
        }

        Id accountId;
        try {
            accountId = Id.valueOf(accountIdValue.trim());
        } catch (Exception error) {
            throw new CARAChatApiSupport.RequestException('accountId must be a valid Salesforce Account Id.');
        }

        if (accountId.getSObjectType() != Account.SObjectType) {
            throw new CARAChatApiSupport.RequestException('accountId must identify an Account record.');
        }

        return accountId;
    }

    private static void requireAccountExists(Id accountId) {
        if ([SELECT COUNT() FROM Account WHERE Id = :accountId] == 0) {
            throw new CARAChatApiSupport.NotFoundException('The Account was not found or is not accessible.');
        }
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