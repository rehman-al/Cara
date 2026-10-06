@isTest
private class CaseCustomerMatchTriggerTest {

    @isTest
    static void testExistingContactIsAttachedWithItsAccount() {
        Account existingAccount = new Account(Name = 'Doe Household');
        insert existingAccount;
        Contact existingContact = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'jane.doe@example.com',
            AccountId = existingAccount.Id
        );
        insert existingContact;

        Case newCase = new Case(Subject = 'Existing customer enquiry', SuppliedEmail = 'jane.doe@example.com');

        Test.startTest();
        insert newCase;
        Test.stopTest();

        Case result = [SELECT ContactId, AccountId FROM Case WHERE Id = :newCase.Id];
        System.assertEquals(existingContact.Id, result.ContactId, 'Case should attach the matching Contact.');
        System.assertEquals(existingAccount.Id, result.AccountId, 'Case should inherit the Contact\'s Account.');

        System.assertEquals(1, [SELECT COUNT() FROM Contact], 'No new Contact should have been created.');
        System.assertEquals(1, [SELECT COUNT() FROM Account], 'No new Account should have been created.');
    }

    @isTest
    static void testNewCustomerGetsAccountAndContactCreated() {
        Case newCase = new Case(
            Subject = 'New customer enquiry',
            SuppliedEmail = 'new.customer@example.com',
            SuppliedName = 'New Customer'
        );

        Test.startTest();
        insert newCase;
        Test.stopTest();

        Case result = [
            SELECT ContactId, AccountId, Account.IsPersonAccount, Account.PersonContactId
            FROM Case
            WHERE Id = :newCase.Id
        ];
        System.assertNotEquals(null, result.ContactId, 'A new Contact should have been created and attached.');
        System.assertNotEquals(null, result.AccountId, 'A new Account should have been created and attached.');
        System.assertEquals(true, result.Account.IsPersonAccount, 'A new customer should be created as a Person Account.');
        System.assertEquals(
            result.Account.PersonContactId,
            result.ContactId,
            'Case ContactId should be the Person Account contact.'
        );

        Contact createdContact = [SELECT Email, FirstName, LastName, AccountId FROM Contact WHERE Id = :result.ContactId];
        System.assertEquals('new.customer@example.com', createdContact.Email, 'Contact email should match the Case\'s supplied email.');
        System.assertEquals('New', createdContact.FirstName);
        System.assertEquals('Customer', createdContact.LastName);
        System.assertEquals(result.AccountId, createdContact.AccountId, 'Contact should be linked to the newly created Account.');
    }

    @isTest
    static void testMissingEmailSkipsMatchingEntirely() {
        Case newCase = new Case(Subject = 'Enquiry with no email');

        Test.startTest();
        insert newCase;
        Test.stopTest();

        Case result = [SELECT ContactId, AccountId FROM Case WHERE Id = :newCase.Id];
        System.assertEquals(null, result.ContactId, 'No email means no matching/creation should run.');
        System.assertEquals(null, result.AccountId, 'No email means no matching/creation should run.');
        System.assertEquals(0, [SELECT COUNT() FROM Contact], 'No Contact should have been created.');
        System.assertEquals(0, [SELECT COUNT() FROM Account], 'No Account should have been created.');
    }

    @isTest
    static void testDuplicateExistingContactsReuseTheEarliestInsteadOfCreatingAnother() {
        Account firstAccount = new Account(Name = 'First Household');
        insert firstAccount;
        Contact earlierContact = new Contact(
            LastName = 'Earlier',
            Email = 'duplicate@example.com',
            AccountId = firstAccount.Id
        );
        insert earlierContact;

        Account secondAccount = new Account(Name = 'Second Household');
        insert secondAccount;
        Contact laterContact = new Contact(
            LastName = 'Later',
            Email = 'duplicate@example.com',
            AccountId = secondAccount.Id
        );
        insert laterContact;

        Case newCase = new Case(Subject = 'Duplicate email enquiry', SuppliedEmail = 'duplicate@example.com');

        Test.startTest();
        insert newCase;
        Test.stopTest();

        Case result = [SELECT ContactId, AccountId FROM Case WHERE Id = :newCase.Id];
        System.assertEquals(earlierContact.Id, result.ContactId, 'The earliest-created matching Contact should be reused.');
        System.assertEquals(2, [SELECT COUNT() FROM Contact], 'No additional Contact should have been created for the duplicate email.');
    }

    @isTest
    static void testBulkCaseInsertHandlesMixOfMatchedAndNewCustomersSafely() {
        Account existingAccount = new Account(Name = 'Bulk Existing Household');
        insert existingAccount;
        Contact existingContact = new Contact(
            LastName = 'BulkExisting',
            Email = 'bulk.existing@example.com',
            AccountId = existingAccount.Id
        );
        insert existingContact;

        List<Case> casesToInsert = new List<Case>();
        for (Integer i = 0; i < 50; i++) {
            casesToInsert.add(new Case(
                Subject = 'Bulk new customer ' + i,
                SuppliedEmail = 'bulk.new.customer' + i + '@example.com',
                SuppliedName = 'Bulk Customer ' + i
            ));
        }
        for (Integer i = 0; i < 50; i++) {
            casesToInsert.add(new Case(Subject = 'Bulk existing customer ' + i, SuppliedEmail = 'bulk.existing@example.com'));
        }
        casesToInsert.add(new Case(Subject = 'Bulk no email'));

        Test.startTest();
        insert casesToInsert;
        Test.stopTest();

        System.assertEquals(50, [SELECT COUNT() FROM Account WHERE Id != :existingAccount.Id], 'Each unique new email should get its own Account.');
        System.assertEquals(50, [SELECT COUNT() FROM Contact WHERE Id != :existingContact.Id], 'Each unique new email should get its own Contact.');

        for (Case result : [SELECT ContactId, AccountId, SuppliedEmail FROM Case WHERE SuppliedEmail = 'bulk.existing@example.com']) {
            System.assertEquals(existingContact.Id, result.ContactId, 'All Cases sharing the existing email should reuse the same Contact.');
            System.assertEquals(existingAccount.Id, result.AccountId);
        }

        Case noEmailCase = [SELECT ContactId, AccountId FROM Case WHERE Subject = 'Bulk no email'];
        System.assertEquals(null, noEmailCase.ContactId);
        System.assertEquals(null, noEmailCase.AccountId);
    }
}
