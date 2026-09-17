@IsTest
private class CARAAppointmentNotificationServiceTest {

    @IsTest
    static void sendsConfirmationEmailWithIcsAttachment() {

        Store__c storeRecord = new Store__c(
            Name = 'Cara — Gold & Diamond Park',
            Address__c = 'Building No. 1, Near Equiti Metro Station, Dubai',
            Active__c = true
        );
        insert storeRecord;

        Account customerAccount = new Account(Name = 'Notification Test Customer');
        insert customerAccount;

        Contact customerContact = new Contact(
            AccountId = customerAccount.Id,
            FirstName = 'Layla',
            LastName = 'Test',
            Email = 'layla.notificationtest@example.com'
        );
        insert customerContact;

        Store_Time_Slot__c slotRecord = new Store_Time_Slot__c(
            Store__c = storeRecord.Id,
            Day_of_Week__c = 'Friday',
            Start_Time__c = Time.newInstance(10, 0, 0, 0),
            End_Time__c = Time.newInstance(11, 0, 0, 0),
            Active__c = true,
            Capacity__c = 1
        );
        insert slotRecord;

        Store_Appointment_Booking__c bookingRecord = new Store_Appointment_Booking__c(
            Store__c = storeRecord.Id,
            Store_Time_Slot__c = slotRecord.Id,
            Contact__c = customerContact.Id,
            Customer__c = customerAccount.Id,
            Appointment_Start__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(10, 0, 0, 0)),
            Appointment_End__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(11, 0, 0, 0)),
            interested_in__c = 'Bridal & engagement',
            Status__c = 'Booked',
            External_Request_ID__c = 'REQ-NOTIFY-001'
        );
        insert bookingRecord;

        Test.startTest();

        CARAAppointmentNotificationService.sendBookingConfirmation(
            bookingRecord,
            storeRecord,
            customerContact
        );

        // Must assert inside the startTest/stopTest block — it runs with
        // its own isolated governor limits, so checking after stopTest()
        // would read the outer context instead and always see 0.
        System.assertEquals(
            1,
            Limits.getEmailInvocations(),
            'Expected exactly one email to be queued.'
        );

        Test.stopTest();

        Store_Appointment_Booking__c updatedBooking = [
            SELECT Confirmation_Email_Status__c, Confirmation_Email_Error__c
            FROM Store_Appointment_Booking__c
            WHERE Id = :bookingRecord.Id
        ];
        System.assertEquals('Sent', updatedBooking.Confirmation_Email_Status__c);
        System.assertEquals(null, updatedBooking.Confirmation_Email_Error__c);
    }


    @IsTest
    static void skipsSendWhenContactHasNoEmail() {

        Store__c storeRecord = new Store__c(
            Name = 'Cara — Dubai Hills',
            Address__c = 'Shop No. FF-290, Dubai Hills Mall, Dubai',
            Active__c = true
        );
        insert storeRecord;

        Account customerAccount = new Account(Name = 'No Email Customer');
        insert customerAccount;

        Contact customerContact = new Contact(
            AccountId = customerAccount.Id,
            FirstName = 'NoEmail',
            LastName = 'Customer'
        );
        insert customerContact;

        Store_Appointment_Booking__c bookingRecord = new Store_Appointment_Booking__c(
            Store__c = storeRecord.Id,
            Contact__c = customerContact.Id,
            Customer__c = customerAccount.Id,
            Appointment_Start__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(10, 0, 0, 0)),
            Appointment_End__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(11, 0, 0, 0)),
            interested_in__c = 'General appointment',
            Status__c = 'Booked',
            External_Request_ID__c = 'REQ-NOTIFY-002'
        );
        insert bookingRecord;

        Test.startTest();

        CARAAppointmentNotificationService.sendBookingConfirmation(
            bookingRecord,
            storeRecord,
            customerContact
        );

        System.assertEquals(
            0,
            Limits.getEmailInvocations(),
            'No email should be queued when the contact has no email address.'
        );

        Test.stopTest();

        Store_Appointment_Booking__c updatedBooking = [
            SELECT Confirmation_Email_Status__c
            FROM Store_Appointment_Booking__c
            WHERE Id = :bookingRecord.Id
        ];
        System.assertEquals('Skipped - No Email', updatedBooking.Confirmation_Email_Status__c);
    }


    @IsTest
    static void sendFailureIsRecordedOnTheBooking() {

        Store__c storeRecord = new Store__c(
            Name = 'Cara — Failure Test Store',
            Address__c = 'Test Address, Dubai',
            Active__c = true
        );
        insert storeRecord;

        Store_Appointment_Booking__c bookingRecord = new Store_Appointment_Booking__c(
            Store__c = storeRecord.Id,
            Appointment_Start__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(10, 0, 0, 0)),
            Appointment_End__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(11, 0, 0, 0)),
            interested_in__c = 'General appointment',
            Status__c = 'Booked',
            External_Request_ID__c = 'REQ-NOTIFY-005'
        );
        insert bookingRecord;

        // A well-formed but non-existent Contact Id — setTargetObjectId
        // resolves against real data at send time, so this reliably
        // reproduces a genuine Messaging.sendEmail failure.
        Contact fakeContact = new Contact(
            Id = '003000000000000AAA',
            FirstName = 'Fake',
            LastName = 'Contact',
            Email = 'fake.contact@example.com'
        );

        Test.startTest();

        CARAAppointmentNotificationService.sendBookingConfirmation(
            bookingRecord,
            storeRecord,
            fakeContact
        );

        Test.stopTest();

        Store_Appointment_Booking__c updatedBooking = [
            SELECT Confirmation_Email_Status__c, Confirmation_Email_Error__c
            FROM Store_Appointment_Booking__c
            WHERE Id = :bookingRecord.Id
        ];
        System.assertEquals('Failed', updatedBooking.Confirmation_Email_Status__c);
        System.assertNotEquals(null, updatedBooking.Confirmation_Email_Error__c);
    }


    @IsTest
    static void icsContentDescribesOnSiteVisitNotVideoMeeting() {

        Store__c storeRecord = new Store__c(
            Name = 'Cara — Abu Dhabi (Yas Mall)',
            Address__c = 'Unit L1-143, Yas Mall, Yas Island - YS1, Abu Dhabi',
            Active__c = true
        );
        insert storeRecord;

        Store_Appointment_Booking__c bookingRecord = new Store_Appointment_Booking__c(
            Store__c = storeRecord.Id,
            Appointment_Start__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(10, 0, 0, 0)),
            Appointment_End__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(11, 0, 0, 0)),
            interested_in__c = 'Repairs & servicing',
            Status__c = 'Booked',
            External_Request_ID__c = 'REQ-NOTIFY-003'
        );
        insert bookingRecord;

        String icsContent = CARAAppointmentNotificationService.buildIcsContent(
            bookingRecord,
            storeRecord
        );

        System.assert(
            icsContent.contains('LOCATION:Unit L1-143\\, Yas Mall\\, Yas Island - YS1\\, Abu Dhabi'),
            'ICS should carry the physical store address as the LOCATION.'
        );
        System.assert(
            !icsContent.toLowerCase().contains('meet.google.com'),
            'ICS must not contain a video conferencing link.'
        );
        System.assert(
            !icsContent.toLowerCase().contains('zoom.us'),
            'ICS must not contain a video conferencing link.'
        );
        System.assert(
            !icsContent.contains('X-GOOGLE-CONFERENCE'),
            'ICS must not carry conferencing metadata — this is an in-store visit.'
        );
        System.assert(
            icsContent.contains('BEGIN:VEVENT') && icsContent.contains('END:VEVENT'),
            'ICS must be a well-formed VEVENT.'
        );
    }


    @IsTest
    static void emailBodyIncludesAppointmentDetails() {

        Store__c storeRecord = new Store__c(
            Name = 'Cara — Ras Al Khaimah',
            Address__c = 'Unit 4, Shop No. G-R 16, Al Jazeera Al Hamra, Al Hamra Mall, Ras Al Khaimah',
            Active__c = true
        );
        insert storeRecord;

        Account customerAccount = new Account(Name = 'Body Test Customer');
        insert customerAccount;

        Contact customerContact = new Contact(
            AccountId = customerAccount.Id,
            FirstName = 'Omar',
            LastName = 'Body',
            Email = 'omar.bodytest@example.com'
        );
        insert customerContact;

        Store_Appointment_Booking__c bookingRecord = new Store_Appointment_Booking__c(
            Store__c = storeRecord.Id,
            Contact__c = customerContact.Id,
            Customer__c = customerAccount.Id,
            Appointment_Start__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(16, 0, 0, 0)),
            Appointment_End__c = Datetime.newInstance(Date.newInstance(2026, 9, 22), Time.newInstance(17, 0, 0, 0)),
            interested_in__c = 'High jewellery',
            Status__c = 'Booked',
            External_Request_ID__c = 'REQ-NOTIFY-004'
        );
        insert bookingRecord;

        // Auto-number Name isn't reflected on the in-memory sObject
        // after insert — requery it, same as the real service does.
        bookingRecord = [
            SELECT Id, Name, Appointment_Start__c, interested_in__c
            FROM Store_Appointment_Booking__c
            WHERE Id = :bookingRecord.Id
        ];

        String emailBody = CARAAppointmentNotificationService.buildEmailBody(
            bookingRecord,
            storeRecord,
            customerContact
        );

        System.assert(emailBody.contains('Omar'), 'Should greet the customer by first name.');
        System.assert(emailBody.contains(bookingRecord.Name), 'Should include the appointment number.');
        System.assert(emailBody.contains('Cara — Ras Al Khaimah'), 'Should include the store name.');
        System.assert(emailBody.contains('High jewellery'), 'Should include the interest category.');
        System.assert(emailBody.contains('in-store visit'), 'Should make clear this is an in-store visit.');
    }
}