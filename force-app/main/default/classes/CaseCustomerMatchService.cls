/**
 * Resolves the Contact/Account for a newly created Case from its supplied
 * email, so every Case creation channel (Web-to-Case, the Customise wizard,
 * chat, REST, agent-created Cases, etc.) ends up linked to a customer
 * without each caller having to implement its own lookup/creation logic.
 *
 * Runs from a before-insert trigger (see CaseCustomerMatchTrigger) so the
 * resolved ContactId/AccountId are set directly on the records being
 * inserted - no second DML on Case, so no update-triggered recursion risk.
 *
 * Skipped entirely when the Case already has a ContactId (an upstream
 * process, like CustomiseRequestController's exact-one-match lookup,
 * already resolved it) or has no SuppliedEmail to match on.
 *
 * "without sharing": some Cases (e.g. the Customise wizard) are created by
 * guest users, who have no sharing visibility into Contact/Account. The
 * existing-Contact lookup must still see every Contact regardless of the
 * running user, or guest-created Cases would wrongly look like new
 * customers and get duplicate Accounts/Contacts created for them.
 *
 * New customers are created as Person Accounts. Internal-user Cases are
 * resolved here before insert. An unmatched guest Case is intentionally
 * left without AccountId/ContactId so the system-context
 * Link_Case_To_Account_By_Email after-save flow can create the Person
 * Account and link both fields; a guest license cannot directly insert a
 * Person Account record type.
 */
public without sharing class CaseCustomerMatchService {

    public static void resolveCustomersForNewCases(List<Case> newCases) {
        Map<String, List<Case>> casesByNormalizedEmail = new Map<String, List<Case>>();
        for (Case caseRecord : newCases) {
            if (caseRecord.ContactId != null || String.isBlank(caseRecord.SuppliedEmail)) {
                continue;
            }
            String trimmedEmail = caseRecord.SuppliedEmail.trim();
            if (String.isBlank(trimmedEmail)) {
                continue;
            }
            String normalizedEmail = trimmedEmail.toLowerCase();
            if (!casesByNormalizedEmail.containsKey(normalizedEmail)) {
                casesByNormalizedEmail.put(normalizedEmail, new List<Case>());
            }
            casesByNormalizedEmail.get(normalizedEmail).add(caseRecord);
        }

        if (casesByNormalizedEmail.isEmpty()) {
            return;
        }

        Map<String, Contact> contactByNormalizedEmail = existingContactsByEmail(casesByNormalizedEmail.keySet());
        Boolean isGuestContext = UserInfo.getUserType() == 'Guest';

        List<Account> accountsToInsert = new List<Account>();
        // Parallel list, index-aligned with accountsToInsert, of every Case
        // waiting on that not-yet-inserted Person Account so the DML result
        // can be fanned back out to all of them.
        List<List<Case>> casesPendingNewAccount = new List<List<Case>>();

        for (String normalizedEmail : casesByNormalizedEmail.keySet()) {
            List<Case> casesForEmail = casesByNormalizedEmail.get(normalizedEmail);
            Contact existingContact = contactByNormalizedEmail.get(normalizedEmail);

            if (existingContact != null) {
                for (Case caseRecord : casesForEmail) {
                    caseRecord.ContactId = existingContact.Id;
                    if (existingContact.AccountId != null) {
                        caseRecord.AccountId = existingContact.AccountId;
                    }
                }
                continue;
            }

            if (isGuestContext) {
                // The active after-save flow handles this in system context.
                // Leaving both relationship fields null is also what allows
                // that flow's entry criteria to run.
                continue;
            }

            Case templateCase = casesForEmail[0];
            String normalizedName = firstNonBlank(templateCase.SuppliedName, templateCase.SuppliedCompany, templateCase.SuppliedEmail.trim());
            List<String> nameParts = splitName(normalizedName);

            // A Person Account is also the customer Contact. Inserting it
            // auto-creates the underlying PersonContact record.
            accountsToInsert.add(new Account(
                RecordTypeId = CARAPersonAccountUtil.getRecordTypeId(),
                FirstName = nameParts[0],
                LastName = nameParts[1],
                PersonEmail = templateCase.SuppliedEmail.trim()
            ));
            casesPendingNewAccount.add(casesForEmail);
        }

        if (accountsToInsert.isEmpty()) {
            return;
        }

        insertAllowingDuplicates(accountsToInsert);

        Map<Id, Account> insertedAccountsById = new Map<Id, Account>(
            [SELECT Id, PersonContactId FROM Account WHERE Id IN :accountsToInsert WITH SYSTEM_MODE]
        );

        for (Integer i = 0; i < accountsToInsert.size(); i++) {
            Id newAccountId = accountsToInsert[i].Id;
            Id newContactId = insertedAccountsById.get(newAccountId).PersonContactId;
            for (Case caseRecord : casesPendingNewAccount[i]) {
                caseRecord.ContactId = newContactId;
                caseRecord.AccountId = newAccountId;
            }
        }
    }

    /**
     * One query for every email in the batch. Ties (more than one existing
     * Contact already sharing the same email, from data created before this
     * automation existed) are broken by picking the earliest-created
     * Contact - a deterministic, documented choice rather than silently
     * skipping the Case or guessing further.
     */
    private static Map<String, Contact> existingContactsByEmail(Set<String> normalizedEmails) {
        Map<String, Contact> result = new Map<String, Contact>();
        // Queried into a List first, rather than looped over inline, to
        // avoid a platform bind-variable resolution bug ("Variable does
        // not exist: tmpVarX") seen with inline SOQL-in-for-loops under
        // guest-user execution context (e.g. the Customise wizard).
        List<Contact> matchingContacts = [
            SELECT Id, AccountId, Email
            FROM Contact
            WHERE Email IN :normalizedEmails
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ];
        for (Contact contactRecord : matchingContacts) {
            String normalizedEmail = contactRecord.Email.trim().toLowerCase();
            if (!result.containsKey(normalizedEmail)) {
                result.put(normalizedEmail, contactRecord);
            }
        }
        return result;
    }

    private static void insertAllowingDuplicates(List<SObject> records) {
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        // AccessLevel.SYSTEM_MODE is required here (not just implied by
        // this class being "without sharing") because Guest User sessions
        // - e.g. the Customise wizard - cannot touch Contact/Account via
        // plain Apex DML at all unless a statement explicitly opts into
        // system mode.
        Database.insert(records, dmlOptions, AccessLevel.SYSTEM_MODE);
    }

    private static String firstNonBlank(String first, String second, String third) {
        if (String.isNotBlank(first)) {
            return first;
        }
        if (String.isNotBlank(second)) {
            return second;
        }
        return third;
    }

    private static List<String> splitName(String fullName) {
        String normalizedName = String.isBlank(fullName) ? 'Customer' : fullName.trim();
        Integer firstSpace = normalizedName.indexOf(' ');
        if (firstSpace <= 0) {
            return new List<String>{ null, normalizedName };
        }
        return new List<String>{
            normalizedName.substring(0, firstSpace).trim(),
            normalizedName.substring(firstSpace + 1).trim()
        };
    }
}