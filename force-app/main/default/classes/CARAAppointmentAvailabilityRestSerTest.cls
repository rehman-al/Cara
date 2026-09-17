@IsTest
private class CARAAppointmentAvailabilityRestSerTest {

    @TestSetup
    static void setupData() {

        // Store
        Store__c storeRecord = new Store__c(
            Name = 'Cara Test Store',
            Address__c = 'Dubai, UAE',
            Active__c = true
        );
        insert storeRecord;


        // Friday slots
        List<Store_Time_Slot__c> slots =
            new List<Store_Time_Slot__c>();

        slots.add(
            new Store_Time_Slot__c(
                Store__c = storeRecord.Id,
                Day_of_Week__c = 'Friday',
                Start_Time__c = Time.newInstance(11, 0, 0, 0),
                End_Time__c = Time.newInstance(12, 0, 0, 0),
                Active__c = true
            )
        );

        slots.add(
            new Store_Time_Slot__c(
                Store__c = storeRecord.Id,
                Day_of_Week__c = 'Friday',
                Start_Time__c = Time.newInstance(12, 0, 0, 0),
                End_Time__c = Time.newInstance(13, 0, 0, 0),
                Active__c = true
            )
        );

        insert slots;


        // Book first slot
        insert new Store_Appointment_Booking__c(
            Store_Time_Slot__c = slots[0].Id,
            Appointment_Start__c =
                Datetime.newInstance(
                    Date.newInstance(2026, 9, 18),
                    Time.newInstance(11, 0, 0, 0)
                ),
            Appointment_End__c =
                Datetime.newInstance(
                    Date.newInstance(2026, 9, 18),
                    Time.newInstance(12, 0, 0, 0)
                ),
            Status__c = 'Booked',
            External_Request_ID__c =
                'TEST-AVAILABILITY-001'
        );
    }


    @IsTest
    static void returnsOnlyAvailableSlots() {

        RestRequest requestRecord =
            new RestRequest();

        requestRecord.requestUri =
            '/services/apexrest/cara/appointments/availability';

        requestRecord.httpMethod = 'GET';

        requestRecord.addParameter(
            'fromDate',
            '2026-09-18'
        );

        requestRecord.addParameter(
            'days',
            '1'
        );

        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();


        Test.startTest();

        CARAAppointmentAvailabilityRestService.getAvailability();

        Test.stopTest();


        System.assertEquals(
            200,
            RestContext.response.statusCode
        );


        Map<String, Object> responseMap =
            (Map<String, Object>)
            JSON.deserializeUntyped(
                RestContext.response
                    .responseBody
                    .toString()
            );


        System.assertEquals(
            true,
            responseMap.get('success')
        );


        List<Object> stores =
            (List<Object>)
            responseMap.get('stores');

        System.assertEquals(
            1,
            stores.size()
        );


        Map<String, Object> store =
            (Map<String, Object>) stores[0];

        List<Object> dates =
            (List<Object>)
            store.get('availableDates');

        System.assertEquals(
            1,
            dates.size()
        );


        Map<String, Object> dateRecord =
            (Map<String, Object>) dates[0];

        List<Object> availableSlots =
            (List<Object>)
            dateRecord.get('timeSlots');


        // One slot booked,
        // therefore only one remains.
        System.assertEquals(
            1,
            availableSlots.size()
        );


        Map<String, Object> availableSlot =
            (Map<String, Object>)
            availableSlots[0];

        System.assertEquals(
            '12:00',
            (String) availableSlot.get(
                'startTime'
            )
        );

        System.assertEquals(
            '13:00',
            (String) availableSlot.get(
                'endTime'
            )
        );
    }


    @IsTest
    static void rejectsInvalidDays() {

        RestRequest requestRecord =
            new RestRequest();

        requestRecord.requestUri =
            '/services/apexrest/cara/appointments/availability';

        requestRecord.httpMethod = 'GET';

        requestRecord.addParameter(
            'fromDate',
            '2026-09-18'
        );

        requestRecord.addParameter(
            'days',
            '100'
        );

        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();


        Test.startTest();

		CARAAppointmentAvailabilityRestService.getAvailability();

        Test.stopTest();


        System.assertEquals(
            400,
            RestContext.response.statusCode
        );
    }
}