@RestResource(urlMapping='/cara/appointments/book')
global with sharing class CARAAppointmentBookingRestService {

    @HttpPost
    global static void bookAppointment() {

        try {

            // 1. Read + validate incoming JSON
            BookingRequest payload = deserializeRequest();

            validateRequiredFields(payload);

            String interestLabel = resolveInterestLabel(payload);


            // 2. Idempotency check
            // Same requestId dobara aaye to duplicate booking create nahi hogi.
            Store_Appointment_Booking__c existingBooking =
                findBookingByRequestId(payload.requestId);

            if (existingBooking != null) {

                writeExistingBookingResponse(existingBooking);
                return;
            }


            // 3. Validate Store
            Id storeId = validateId(
                payload.storeId,
                Store__c.SObjectType,
                'storeId'
            );

            List<Store__c> stores = [
                SELECT
                    Id,
                    Name,
                    Address__c,
                    Active__c
                FROM Store__c
                WHERE Id = :storeId
                LIMIT 1
            ];

            if (
                stores.isEmpty() ||
                stores[0].Active__c != true
            ) {
                throw new CARAAppointmentApiSupport.RequestException(
                    'Selected store is invalid or inactive.'
                );
            }

            Store__c selectedStore = stores[0];


            // 4. Validate Slot
            Id slotId = validateId(
                payload.slotId,
                Store_Time_Slot__c.SObjectType,
                'slotId'
            );

            /*
             * FOR UPDATE is important.
             *
             * If 2 customers try to book the same slot
             * at exactly the same time, Salesforce locks
             * this slot while this transaction completes.
             */
            List<Store_Time_Slot__c> slots = [
                SELECT
                    Id,
                    Name,
                    Store__c,
                    Day_of_Week__c,
                    Start_Time__c,
                    End_Time__c,
                    Active__c,
                    Capacity__c
                FROM Store_Time_Slot__c
                WHERE Id = :slotId
                LIMIT 1
                FOR UPDATE
            ];

            if (
                slots.isEmpty() ||
                slots[0].Active__c != true
            ) {
                throw new CARAAppointmentApiSupport.RequestException(
                    'Selected time slot is invalid or inactive.'
                );
            }

            Store_Time_Slot__c selectedSlot = slots[0];


            // 5. CRITICAL:
            // Make sure selected slot actually belongs to selected Store.
            if (selectedSlot.Store__c != selectedStore.Id) {

                throw new CARAAppointmentApiSupport.RequestException(
                    'Selected time slot does not belong to the selected store.'
                );
            }


            // 6. Parse appointment date
            Date appointmentDate;

            try {
                appointmentDate =
                    Date.valueOf(payload.appointmentDate);
            } catch (Exception error) {

                throw new CARAAppointmentApiSupport.RequestException(
                    'appointmentDate must use YYYY-MM-DD format.'
                );
            }


            // 7. Verify Day of Week
            String requestedDay =
                Datetime.newInstance(
                    appointmentDate,
                    Time.newInstance(0, 0, 0, 0)
                ).format('EEEE');

            if (
                String.isBlank(selectedSlot.Day_of_Week__c) ||
                !selectedSlot.Day_of_Week__c.equalsIgnoreCase(
                    requestedDay
                )
            ) {

                throw new CARAAppointmentApiSupport.RequestException(
                    'Selected time slot is not available on the requested date.'
                );
            }


            // 8. Build actual appointment DateTimes
            Datetime appointmentStart =
                Datetime.newInstance(
                    appointmentDate,
                    selectedSlot.Start_Time__c
                );

            Datetime appointmentEnd =
                Datetime.newInstance(
                    appointmentDate,
                    selectedSlot.End_Time__c
                );


            // 9. Holidays / Closures (whole store blocked for this date)
            List<Store_Closure__c> storeClosures = [
                SELECT Id, Reason__c
                FROM Store_Closure__c
                WHERE Store__c = :selectedStore.Id
                    AND Closure_Date__c = :appointmentDate
                    AND Store_Time_Slot__c = null
                LIMIT 1
            ];

            if (!storeClosures.isEmpty()) {

                throw new CARAAppointmentApiSupport.ConflictException(
                    'Store is closed on the selected date.'
                );
            }


            // 10. Blackouts / Restrictions (this specific slot blocked)
            List<Store_Closure__c> slotBlackouts = [
                SELECT Id
                FROM Store_Closure__c
                WHERE Store__c = :selectedStore.Id
                    AND Closure_Date__c = :appointmentDate
                    AND Store_Time_Slot__c = :selectedSlot.Id
                LIMIT 1
            ];

            if (!slotBlackouts.isEmpty()) {

                throw new CARAAppointmentApiSupport.ConflictException(
                    'Selected time slot is unavailable on the selected date.'
                );
            }


            /*
             * 11. Capacity check (re-checked here, while the Store_Time_Slot__c
             * row is locked FOR UPDATE above, so a concurrent request cannot
             * slip in between the earlier availability read and this booking).
             */
            Integer slotCapacity =
                selectedSlot.Capacity__c == null
                    ? 1
                    : Integer.valueOf(selectedSlot.Capacity__c);

            Integer bookedCount = [
                SELECT COUNT()
                FROM Store_Appointment_Booking__c
                WHERE Store_Time_Slot__c = :selectedSlot.Id
                AND Appointment_Start__c = :appointmentStart
                AND Status__c = 'Booked'
            ];

            if (bookedCount >= slotCapacity) {

                throw new CARAAppointmentApiSupport.ConflictException(
                    'Selected time slot is already booked.'
                );
            }


            // 12. Match/Create Contact + Account
            // (mirrors the identity rule already established in
            // CARAOrderRestService.syncCustomer: Contact matched by email,
            // Account derived from/created alongside it.)
            String normalizedEmail =
                payload.email.trim().toLowerCase();

            List<Contact> matchingContacts = [
                SELECT Id, AccountId, Email, FirstName
                FROM Contact
                WHERE Email = :normalizedEmail
                ORDER BY CreatedDate ASC
                LIMIT 2
            ];

            if (matchingContacts.size() > 1) {
                throw new CARAAppointmentApiSupport.RequestException(
                    'Multiple contacts use the provided email address.'
                );
            }

            Contact customerContact =
                matchingContacts.isEmpty() ? null : matchingContacts[0];

            Account customerAccount;

            if (customerContact != null && customerContact.AccountId != null) {

                customerAccount = [
                    SELECT Id, Name, Email__c, Phone
                    FROM Account
                    WHERE Id = :customerContact.AccountId
                    LIMIT 1
                ];

            } else {

                // Fall back to the pre-existing Account.Email__c match so
                // bookings created before Contact syncing remain findable.
                List<Account> matchingAccounts = [
                    SELECT Id, Name, Email__c, Phone
                    FROM Account
                    WHERE Email__c = :normalizedEmail
                    ORDER BY LastModifiedDate DESC
                    LIMIT 1
                ];

                customerAccount =
                    matchingAccounts.isEmpty() ? null : matchingAccounts[0];
            }

            Boolean isNewAccount = customerAccount == null;

            if (isNewAccount) {

                customerAccount = new Account(
                    Name = payload.fullName.trim(),
                    Email__c = normalizedEmail,
                    Phone = String.isBlank(payload.phone)
                        ? null
                        : payload.phone.trim()
                );

                insertBypassingNameDuplicateRules(customerAccount);
            }

            Boolean isNewContact = customerContact == null;

            if (isNewContact) {

                List<String> nameParts = splitName(payload.fullName);

                customerContact = new Contact(
                    AccountId = customerAccount.Id,
                    FirstName = nameParts[0],
                    LastName = nameParts[1],
                    Email = normalizedEmail,
                    Phone = String.isBlank(payload.phone)
                        ? null
                        : payload.phone.trim()
                );

                insertBypassingNameDuplicateRules(customerContact);
            }


            // 13. Create Booking
            Store_Appointment_Booking__c bookingRecord =
                new Store_Appointment_Booking__c(

                    Customer__c =
                        customerAccount.Id,

                    Contact__c =
                        customerContact.Id,

                    Store__c =
                        selectedStore.Id,

                    Store_Time_Slot__c =
                        selectedSlot.Id,

                    Appointment_Start__c =
                        appointmentStart,

                    Appointment_End__c =
                        appointmentEnd,

                    Party_size__c = mapPartySize(payload.partySize),

                    interested_in__c =
                        interestLabel,

                    Additional_Note__c =
                        payload.notes,

                    Status__c =
                        'Booked',

                    External_Request_ID__c =
                        payload.requestId.trim()
                );


            Database.SaveResult result =
                Database.insert(
                    bookingRecord,
                    false
                );


            if (!result.isSuccess()) {

                Database.Error dbError =
                    result.getErrors()[0];

                /*
                 * Unique External Request ID protects us
                 * if SFCC sends the exact same request twice.
                 */
                if (
                    dbError.getStatusCode() ==
                    StatusCode.DUPLICATE_VALUE
                ) {

                    Store_Appointment_Booking__c duplicateBooking =
                        findBookingByRequestId(
                            payload.requestId
                        );

                    if (duplicateBooking != null) {

                        writeExistingBookingResponse(
                            duplicateBooking
                        );

                        return;
                    }
                }

                throw new CARAAppointmentApiSupport.RequestException(
                    dbError.getMessage()
                );
            }


            // Auto Number / Name safely query back
            Store_Appointment_Booking__c savedBooking = [
                SELECT
                    Id,
                    Name,
                    Appointment_Start__c,
                    Appointment_End__c,
                    interested_in__c
                FROM Store_Appointment_Booking__c
                WHERE Id = :result.getId()
                LIMIT 1
            ];


            // 12. Send guest confirmation email + calendar invite
            // (best-effort — never blocks or fails the booking response)
            CARAAppointmentNotificationService.sendBookingConfirmation(
                savedBooking,
                selectedStore,
                customerContact
            );


            // 13. Return finalized SFCC response
            BookingResponse responseBody =
                new BookingResponse();

            responseBody.success = true;

            responseBody.message =
                'Appointment booked successfully.';

            responseBody.appointmentNumber =
                savedBooking.Name;

            responseBody.storeName =
                selectedStore.Name;

            responseBody.appointmentDate =
                String.valueOf(appointmentDate);

            responseBody.startTime =
                formatTime(selectedSlot.Start_Time__c);


            CARAAppointmentApiSupport.writeResponse(
                201,
                responseBody
            );


        } catch (
            CARAAppointmentApiSupport.ConflictException error
        ) {

            // Slot just taken / store closed / blacked out:
            // SFCC should refresh availability and let the
            // customer pick again, not treat this as a bad request.
            CARAAppointmentApiSupport.writeError(
                409,
                error.getMessage()
            );

        } catch (
            CARAAppointmentApiSupport.RequestException error
        ) {

            CARAAppointmentApiSupport.writeError(
                400,
                error.getMessage()
            );

        } catch (Exception error) {

            System.debug(
                LoggingLevel.ERROR,
                'Appointment booking API error: ' +
                error.getMessage()
            );

            CARAAppointmentApiSupport.writeError(
                500,
                'Unable to book appointment.'
            );
        }
    }


    // =========================================================
    // DUPLICATE-RULE-SAFE INSERT
    // =========================================================

    /*
     * Email is our authoritative match key (checked above), so a
     * standard name/company duplicate rule flagging two different
     * customers who share a common name (e.g. "Jane Doe") must not
     * block a legitimate new booking.
     */
    private static void insertBypassingNameDuplicateRules(SObject record) {

        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.duplicateRuleHeader.allowSave = true;

        Database.SaveResult result = Database.insert(record, dmlOptions);

        if (!result.isSuccess()) {

            throw new CARAAppointmentApiSupport.RequestException(
                result.getErrors()[0].getMessage()
            );
        }
    }


    // =========================================================
    // NAME HELPERS
    // =========================================================

    /*
     * Mirrors CARAOrderRestService.splitName so Contact naming
     * stays consistent across both SFCC-facing integrations.
     */
    private static List<String> splitName(String fullName) {

        String normalizedName =
            String.isBlank(fullName) ? 'Customer' : fullName.trim();

        Integer firstSpace = normalizedName.indexOf(' ');

        if (firstSpace <= 0) {
            return new List<String>{ null, normalizedName };
        }

        String firstName = normalizedName.substring(0, firstSpace).trim();
        String lastName = normalizedName.substring(firstSpace + 1).trim();

        if (String.isBlank(lastName)) {
            lastName = firstName;
            firstName = null;
        }

        return new List<String>{ firstName, lastName };
    }


    // =========================================================
    // REQUEST VALIDATION
    // =========================================================

    private static void validateRequiredFields(
        BookingRequest payload
    ) {

        if (String.isBlank(payload.requestId)) {
            throw new CARAAppointmentApiSupport.RequestException(
                'requestId is required.'
            );
        }

        if (String.isBlank(payload.storeId)) {
            throw new CARAAppointmentApiSupport.RequestException(
                'storeId is required.'
            );
        }

        if (String.isBlank(payload.slotId)) {
            throw new CARAAppointmentApiSupport.RequestException(
                'slotId is required.'
            );
        }

        if (String.isBlank(payload.appointmentDate)) {
            throw new CARAAppointmentApiSupport.RequestException(
                'appointmentDate is required.'
            );
        }

        if (String.isBlank(payload.fullName)) {
            throw new CARAAppointmentApiSupport.RequestException(
                'fullName is required.'
            );
        }

        if (String.isBlank(payload.email)) {
            throw new CARAAppointmentApiSupport.RequestException(
                'email is required.'
            );
        }

        if (String.isBlank(payload.partySize)) {
            throw new CARAAppointmentApiSupport.RequestException(
                'partySize is required.'
            );
        }

        if (
            String.isBlank(payload.interestId) &&
            String.isBlank(payload.interest)
        ) {
            throw new CARAAppointmentApiSupport.RequestException(
                'interestId is required.'
            );
        }


        Set<String> validPartySizes =
            new Set<String>{
                '1',
                '2',
                '3',
                '4+'
            };

        if (!validPartySizes.contains(payload.partySize)) {

            throw new CARAAppointmentApiSupport.RequestException(
                'Invalid partySize.'
            );
        }


    }


    /*
     * Resolves the payload's interest category to the English label
     * stored in interested_in__c. Prefers the new stable interestId
     * (e.g. "bridal"); falls back to the legacy free-text interest
     * label so bookings sent by an older storefront build keep working.
     */
    private static String resolveInterestLabel(BookingRequest payload) {

        if (String.isNotBlank(payload.interestId)) {

            String label = CARAAppointmentApiSupport.getInterestLabelById(
                payload.interestId
            );

            if (label == null) {
                throw new CARAAppointmentApiSupport.RequestException(
                    'Invalid interestId.'
                );
            }

            return label;
        }

        Set<String> validInterests =
            new Set<String>{
                'General appointment',
                'Bridal & engagement',
                'High jewellery',
                'Repairs & servicing'
            };

        if (!validInterests.contains(payload.interest)) {

            throw new CARAAppointmentApiSupport.RequestException(
                'Invalid interest.'
            );
        }

        return payload.interest;
    }
    private static String mapPartySize(String partySize) {

    Map<String, String> partySizeMap =
        new Map<String, String>{
            '1'  => 'Just Me',
            '2'  => '2 guests',
            '3'  => '3 guests',
            '4+' => '4+ guests'
        };

    if (
        String.isBlank(partySize) ||
        !partySizeMap.containsKey(partySize)
    ) {
        throw new CARAAppointmentApiSupport.RequestException(
            'Invalid partySize.'
        );
    }

    return partySizeMap.get(partySize);
}


    // =========================================================
    // ID VALIDATION
    // =========================================================

    private static Id validateId(
        String idValue,
        Schema.SObjectType expectedType,
        String fieldName
    ) {

        Id recordId;

        try {

            recordId =
                Id.valueOf(idValue.trim());

        } catch (Exception error) {

            throw new CARAAppointmentApiSupport.RequestException(
                fieldName +
                ' must be a valid Salesforce Id.'
            );
        }


        if (
            recordId.getSObjectType() !=
            expectedType
        ) {

            throw new CARAAppointmentApiSupport.RequestException(
                fieldName +
                ' references the wrong object.'
            );
        }


        return recordId;
    }


    // =========================================================
    // IDEMPOTENCY LOOKUP
    // =========================================================

    private static Store_Appointment_Booking__c
        findBookingByRequestId(
            String requestId
        ) {

        if (String.isBlank(requestId)) {
            return null;
        }

        List<Store_Appointment_Booking__c> bookings = [
            SELECT
                Id,
                Name,
                Store_Time_Slot__c,
                Appointment_Start__c
            FROM Store_Appointment_Booking__c
            WHERE External_Request_ID__c =
                :requestId.trim()
            LIMIT 1
        ];

        return bookings.isEmpty()
            ? null
            : bookings[0];
    }


    // =========================================================
    // DUPLICATE REQUEST RESPONSE
    // =========================================================

    private static void writeExistingBookingResponse(
        Store_Appointment_Booking__c booking
    ) {

        Store_Time_Slot__c slotRecord = [
            SELECT
                Id,
                Store__c,
                Start_Time__c
            FROM Store_Time_Slot__c
            WHERE Id = :booking.Store_Time_Slot__c
            LIMIT 1
        ];


        Store__c storeRecord = [
            SELECT
                Id,
                Name
            FROM Store__c
            WHERE Id = :slotRecord.Store__c
            LIMIT 1
        ];


        BookingResponse responseBody =
            new BookingResponse();

        responseBody.success = true;

        responseBody.message =
            'Appointment request was already processed.';

        responseBody.appointmentNumber =
            booking.Name;

        responseBody.storeName =
            storeRecord.Name;

        responseBody.appointmentDate =
            booking.Appointment_Start__c
                .format('yyyy-MM-dd');

        responseBody.startTime =
            formatTime(slotRecord.Start_Time__c);


        CARAAppointmentApiSupport.writeResponse(
            200,
            responseBody
        );
    }


    // =========================================================
    // TIME FORMAT
    // =========================================================

    private static String formatTime(
        Time timeValue
    ) {

        String hourValue =
            timeValue.hour() < 10
                ? '0' + String.valueOf(
                    timeValue.hour()
                )
                : String.valueOf(
                    timeValue.hour()
                );

        String minuteValue =
            timeValue.minute() < 10
                ? '0' + String.valueOf(
                    timeValue.minute()
                )
                : String.valueOf(
                    timeValue.minute()
                );

        return hourValue + ':' + minuteValue;
    }


    // =========================================================
    // JSON DESERIALIZATION
    // =========================================================

    private static BookingRequest deserializeRequest() {

        if (
            RestContext.request == null ||
            RestContext.request.requestBody == null ||
            String.isBlank(
                RestContext.request
                    .requestBody
                    .toString()
            )
        ) {

            throw new CARAAppointmentApiSupport.RequestException(
                'A JSON request body is required.'
            );
        }


        try {

            BookingRequest payload =
                (BookingRequest)
                JSON.deserialize(
                    RestContext.request
                        .requestBody
                        .toString(),
                    BookingRequest.class
                );

            if (payload == null) {

                throw new CARAAppointmentApiSupport.RequestException(
                    'A valid JSON request body is required.'
                );
            }

            return payload;

        } catch (
            CARAAppointmentApiSupport.RequestException error
        ) {

            throw error;

        } catch (Exception error) {

            throw new CARAAppointmentApiSupport.RequestException(
                'Invalid JSON request body.'
            );
        }
    }


    // =========================================================
    // JSON WRAPPERS
    // =========================================================

    private class BookingRequest {

        public String requestId;
        public String storeId;
        public String slotId;
        public String appointmentDate;

        public String fullName;
        public String email;
        public String phone;

        public String partySize;
        public String interestId;
        public String interest;
        public String notes;
    }


    private class BookingResponse {

        public Boolean success;
        public String message;

        public String appointmentNumber;
        public String storeName;
        public String appointmentDate;
        public String startTime;
    }
}