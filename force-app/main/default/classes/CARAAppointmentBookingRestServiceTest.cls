@IsTest
private class CARAAppointmentBookingRestServiceTest {

    private static final Date SLOT_DATE = Date.newInstance(2026, 9, 18); // Friday

    @TestSetup
    static void setupData() {

        Store__c storeRecord = new Store__c(
            Name = 'Cara Booking Test Store',
            Address__c = 'Dubai, UAE',
            Active__c = true
        );
        insert storeRecord;

        Store_Time_Slot__c capacityOneSlot = new Store_Time_Slot__c(
            Store__c = storeRecord.Id,
            Day_of_Week__c = 'Friday',
            Start_Time__c = Time.newInstance(11, 0, 0, 0),
            End_Time__c = Time.newInstance(12, 0, 0, 0),
            Active__c = true,
            Capacity__c = 1
        );

        Store_Time_Slot__c capacityTwoSlot = new Store_Time_Slot__c(
            Store__c = storeRecord.Id,
            Day_of_Week__c = 'Friday',
            Start_Time__c = Time.newInstance(13, 0, 0, 0),
            End_Time__c = Time.newInstance(14, 0, 0, 0),
            Active__c = true,
            Capacity__c = 2
        );

        insert new List<Store_Time_Slot__c>{ capacityOneSlot, capacityTwoSlot };
    }


    private static RestRequest buildRequest(Map<String, Object> payload) {

        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/appointments/book';
        requestRecord.httpMethod = 'POST';
        requestRecord.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();

        return requestRecord;
    }


    private static Map<String, Object> basePayload(
        Id storeId,
        Id slotId,
        String requestId,
        String email
    ) {
        return new Map<String, Object>{
            'requestId' => requestId,
            'storeId' => storeId,
            'slotId' => slotId,
            'appointmentDate' => String.valueOf(SLOT_DATE),
            'fullName' => 'Jane Doe',
            'email' => email,
            'phone' => '555-1234',
            'partySize' => '2',
            'interestId' => 'general'
        };
    }


    @IsTest
    static void bookingSucceedsAndCreatesNewContactAndAccount() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        buildRequest(
            basePayload(
                storeRecord.Id,
                slotRecord.Id,
                'REQ-NEW-001',
                'jane.new@example.com'
            )
        );

        Test.startTest();
        CARAAppointmentBookingRestService.bookAppointment();

        System.assertEquals(
            1,
            Limits.getEmailInvocations(),
            'A successful booking should queue exactly one confirmation email.'
        );

        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode);

        List<Store_Appointment_Booking__c> bookings = [
            SELECT Id, Contact__c, Customer__c, Store__c
            FROM Store_Appointment_Booking__c
            WHERE External_Request_ID__c = 'REQ-NEW-001'
        ];
        System.assertEquals(1, bookings.size());
        System.assertNotEquals(null, bookings[0].Contact__c);
        System.assertNotEquals(null, bookings[0].Customer__c);
        System.assertEquals(storeRecord.Id, bookings[0].Store__c);

        List<Contact> contacts = [
            SELECT Id, Email, AccountId FROM Contact WHERE Email = 'jane.new@example.com'
        ];
        System.assertEquals(1, contacts.size());
        System.assertEquals(bookings[0].Customer__c, contacts[0].AccountId);
    }


    @IsTest
    static void bookingReusesExistingContactAndAccount() {

        Account existingAccount = new Account(
            Name = 'Existing Customer',
            Email__c = 'existing@example.com'
        );
        insert existingAccount;

        Contact existingContact = new Contact(
            AccountId = existingAccount.Id,
            FirstName = 'Existing',
            LastName = 'Customer',
            Email = 'existing@example.com'
        );
        insert existingContact;

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        buildRequest(
            basePayload(
                storeRecord.Id,
                slotRecord.Id,
                'REQ-EXISTING-001',
                'existing@example.com'
            )
        );

        Test.startTest();
        CARAAppointmentBookingRestService.bookAppointment();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode);

        Store_Appointment_Booking__c booking = [
            SELECT Contact__c, Customer__c, Confirmation_Email_Status__c, Confirmation_Email_Error__c
            FROM Store_Appointment_Booking__c
            WHERE External_Request_ID__c = 'REQ-EXISTING-001'
        ];
        System.assertEquals(existingContact.Id, booking.Contact__c);
        System.assertEquals(existingAccount.Id, booking.Customer__c);

        // Regression coverage: the existing-contact match previously
        // queried Contact without FirstName, which threw the moment the
        // confirmation email tried to personalize the greeting.
        System.assertEquals(
            'Sent',
            booking.Confirmation_Email_Status__c,
            'Confirmation email must succeed when matching an existing Contact, not just a new one: ' +
            booking.Confirmation_Email_Error__c
        );

        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Email = 'existing@example.com']);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Email__c = 'existing@example.com']);
    }


    @IsTest
    static void secondBookingOnCapacityOneSlotIsRejectedAsConflict() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        // Request A - succeeds
        buildRequest(
            basePayload(storeRecord.Id, slotRecord.Id, 'REQ-RACE-A', 'customerA@example.com')
        );

        Test.startTest();
        CARAAppointmentBookingRestService.bookAppointment();
        System.assertEquals(201, RestContext.response.statusCode);

        // Request B - same slot/date, different customer -> must be rejected
        buildRequest(
            basePayload(storeRecord.Id, slotRecord.Id, 'REQ-RACE-B', 'customerB@example.com')
        );

        CARAAppointmentBookingRestService.bookAppointment();
        Test.stopTest();

        System.assertEquals(409, RestContext.response.statusCode);

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Store_Appointment_Booking__c
                WHERE Store_Time_Slot__c = :slotRecord.Id
                AND Status__c = 'Booked'
            ]
        );
    }


    @IsTest
    static void capacityTwoSlotAllowsTwoBookingsThenRejectsThird() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 2 LIMIT 1
        ];

        Test.startTest();

        buildRequest(
            basePayload(storeRecord.Id, slotRecord.Id, 'REQ-CAP2-A', 'cap2a@example.com')
        );
        CARAAppointmentBookingRestService.bookAppointment();
        System.assertEquals(201, RestContext.response.statusCode);

        buildRequest(
            basePayload(storeRecord.Id, slotRecord.Id, 'REQ-CAP2-B', 'cap2b@example.com')
        );
        CARAAppointmentBookingRestService.bookAppointment();
        System.assertEquals(201, RestContext.response.statusCode);

        buildRequest(
            basePayload(storeRecord.Id, slotRecord.Id, 'REQ-CAP2-C', 'cap2c@example.com')
        );
        CARAAppointmentBookingRestService.bookAppointment();
        System.assertEquals(409, RestContext.response.statusCode);

        Test.stopTest();

        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Store_Appointment_Booking__c
                WHERE Store_Time_Slot__c = :slotRecord.Id
                AND Status__c = 'Booked'
            ]
        );
    }


    @IsTest
    static void duplicateRequestIdReturnsSameBookingInstead() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        Test.startTest();

        buildRequest(
            basePayload(storeRecord.Id, slotRecord.Id, 'REQ-IDEMPOTENT', 'idempotent@example.com')
        );
        CARAAppointmentBookingRestService.bookAppointment();
        System.assertEquals(201, RestContext.response.statusCode);

        buildRequest(
            basePayload(storeRecord.Id, slotRecord.Id, 'REQ-IDEMPOTENT', 'idempotent@example.com')
        );
        CARAAppointmentBookingRestService.bookAppointment();
        System.assertEquals(200, RestContext.response.statusCode);

        System.assertEquals(
            1,
            Limits.getEmailInvocations(),
            'A retried request must not send a second confirmation email.'
        );

        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Store_Appointment_Booking__c WHERE External_Request_ID__c = 'REQ-IDEMPOTENT']
        );
    }


    @IsTest
    static void holidayClosureBlocksBooking() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        insert new Store_Closure__c(
            Store__c = storeRecord.Id,
            Closure_Date__c = SLOT_DATE,
            Type__c = 'Holiday',
            Reason__c = 'National Holiday'
        );

        buildRequest(
            basePayload(storeRecord.Id, slotRecord.Id, 'REQ-HOLIDAY', 'holiday@example.com')
        );

        Test.startTest();
        CARAAppointmentBookingRestService.bookAppointment();
        Test.stopTest();

        System.assertEquals(409, RestContext.response.statusCode);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Store_Appointment_Booking__c WHERE External_Request_ID__c = 'REQ-HOLIDAY']
        );
    }


    @IsTest
    static void blackoutBlocksSpecificSlotOnly() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c blackedOutSlot = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];
        Store_Time_Slot__c openSlot = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 2 LIMIT 1
        ];

        insert new Store_Closure__c(
            Store__c = storeRecord.Id,
            Closure_Date__c = SLOT_DATE,
            Store_Time_Slot__c = blackedOutSlot.Id,
            Type__c = 'Blackout',
            Reason__c = 'Staff training'
        );

        Test.startTest();

        buildRequest(
            basePayload(storeRecord.Id, blackedOutSlot.Id, 'REQ-BLACKOUT', 'blackout@example.com')
        );
        CARAAppointmentBookingRestService.bookAppointment();
        System.assertEquals(409, RestContext.response.statusCode);

        buildRequest(
            basePayload(storeRecord.Id, openSlot.Id, 'REQ-NOT-BLACKED-OUT', 'notblacked@example.com')
        );
        CARAAppointmentBookingRestService.bookAppointment();
        System.assertEquals(201, RestContext.response.statusCode);

        Test.stopTest();
    }


    @IsTest
    static void invalidStoreIsRejected() {

        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        buildRequest(
            basePayload(
                UserInfo.getUserId(), // valid Id format, wrong SObjectType
                slotRecord.Id,
                'REQ-INVALID-STORE',
                'invalidstore@example.com'
            )
        );

        Test.startTest();
        CARAAppointmentBookingRestService.bookAppointment();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }


    @IsTest
    static void slotNotBelongingToStoreIsRejected() {

        Store__c otherStore = new Store__c(
            Name = 'Other Store',
            Address__c = 'Abu Dhabi, UAE',
            Active__c = true
        );
        insert otherStore;

        Store__c storeRecord = [SELECT Id FROM Store__c WHERE Id != :otherStore.Id LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        buildRequest(
            basePayload(otherStore.Id, slotRecord.Id, 'REQ-MISMATCH', 'mismatch@example.com')
        );

        Test.startTest();
        CARAAppointmentBookingRestService.bookAppointment();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }


    @IsTest
    static void missingRequiredFieldIsRejected() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        Map<String, Object> payload = basePayload(
            storeRecord.Id,
            slotRecord.Id,
            'REQ-MISSING',
            'missing@example.com'
        );
        payload.remove('fullName');

        buildRequest(payload);

        Test.startTest();
        CARAAppointmentBookingRestService.bookAppointment();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }


    @IsTest
    static void legacyInterestLabelStillAccepted() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        Map<String, Object> payload = basePayload(
            storeRecord.Id,
            slotRecord.Id,
            'REQ-LEGACY-INTEREST',
            'legacy@example.com'
        );
        payload.remove('interestId');
        payload.put('interest', 'Bridal & engagement');

        buildRequest(payload);

        Test.startTest();
        CARAAppointmentBookingRestService.bookAppointment();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode);

        Store_Appointment_Booking__c booking = [
            SELECT interested_in__c
            FROM Store_Appointment_Booking__c
            WHERE External_Request_ID__c = 'REQ-LEGACY-INTEREST'
        ];
        System.assertEquals('Bridal & engagement', booking.interested_in__c);
    }


    @IsTest
    static void invalidInterestIdIsRejected() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c slotRecord = [
            SELECT Id FROM Store_Time_Slot__c WHERE Capacity__c = 1 LIMIT 1
        ];

        Map<String, Object> payload = basePayload(
            storeRecord.Id,
            slotRecord.Id,
            'REQ-BAD-INTEREST',
            'badinterest@example.com'
        );
        payload.put('interestId', 'not-a-real-category');

        buildRequest(payload);

        Test.startTest();
        CARAAppointmentBookingRestService.bookAppointment();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }
}