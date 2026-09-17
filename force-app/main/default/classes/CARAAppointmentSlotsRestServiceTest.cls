@IsTest
private class CARAAppointmentSlotsRestServiceTest {

    private static final Date SLOT_DATE = Date.newInstance(2026, 9, 18); // Friday

    @TestSetup
    static void setupData() {

        Store__c storeRecord = new Store__c(
            Name = 'Cara Slots Test Store',
            Address__c = 'Dubai, UAE',
            Name_AR__c = 'متجر كارا للاختبار',
            Active__c = true
        );
        insert storeRecord;

        List<Store_Time_Slot__c> slots = new List<Store_Time_Slot__c>{
            new Store_Time_Slot__c(
                Store__c = storeRecord.Id,
                Day_of_Week__c = 'Friday',
                Start_Time__c = Time.newInstance(11, 0, 0, 0),
                End_Time__c = Time.newInstance(12, 0, 0, 0),
                Active__c = true,
                Capacity__c = 1
            ),
            new Store_Time_Slot__c(
                Store__c = storeRecord.Id,
                Day_of_Week__c = 'Friday',
                Start_Time__c = Time.newInstance(12, 0, 0, 0),
                End_Time__c = Time.newInstance(13, 0, 0, 0),
                Active__c = true,
                Capacity__c = 1
            )
        };
        insert slots;

        // Fully book the first slot
        insert new Store_Appointment_Booking__c(
            Store_Time_Slot__c = slots[0].Id,
            Appointment_Start__c = Datetime.newInstance(SLOT_DATE, Time.newInstance(11, 0, 0, 0)),
            Appointment_End__c = Datetime.newInstance(SLOT_DATE, Time.newInstance(12, 0, 0, 0)),
            Status__c = 'Booked',
            External_Request_ID__c = 'TEST-SLOTS-SETUP-001'
        );
    }


    private static RestRequest buildRequest(String storeId, String dateValue) {
        return buildRequest(storeId, dateValue, null);
    }


    private static RestRequest buildRequest(String storeId, String dateValue, String langValue) {

        RestRequest requestRecord = new RestRequest();
        requestRecord.requestUri = '/services/apexrest/cara/appointments/slots';
        requestRecord.httpMethod = 'GET';
        if (storeId != null) {
            requestRecord.addParameter('storeId', storeId);
        }
        if (dateValue != null) {
            requestRecord.addParameter('date', dateValue);
        }
        if (langValue != null) {
            requestRecord.addParameter('lang', langValue);
        }

        RestContext.request = requestRecord;
        RestContext.response = new RestResponse();

        return requestRecord;
    }


    @IsTest
    static void returnsOnlyRemainingCapacitySlots() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];

        buildRequest(storeRecord.Id, String.valueOf(SLOT_DATE));

        Test.startTest();
        CARAAppointmentSlotsRestService.getSlots();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );

        System.assertEquals(false, responseMap.get('closed'));

        List<Object> slots = (List<Object>) responseMap.get('slots');
        System.assertEquals(1, slots.size());

        Map<String, Object> slot = (Map<String, Object>) slots[0];
        System.assertEquals('12:00', (String) slot.get('startTime'));
    }


    @IsTest
    static void holidayReturnsClosedStoreWithNoSlots() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];

        insert new Store_Closure__c(
            Store__c = storeRecord.Id,
            Closure_Date__c = SLOT_DATE,
            Type__c = 'Holiday',
            Reason__c = 'National Holiday'
        );

        buildRequest(storeRecord.Id, String.valueOf(SLOT_DATE));

        Test.startTest();
        CARAAppointmentSlotsRestService.getSlots();
        Test.stopTest();

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );

        System.assertEquals(true, responseMap.get('closed'));
        System.assertEquals('National Holiday', (String) responseMap.get('closureReason'));

        List<Object> slots = (List<Object>) responseMap.get('slots');
        System.assertEquals(0, slots.size());
    }


    @IsTest
    static void blackoutRemovesOnlyThatSlot() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];
        Store_Time_Slot__c secondSlot = [
            SELECT Id FROM Store_Time_Slot__c
            WHERE Start_Time__c = :Time.newInstance(12, 0, 0, 0)
            LIMIT 1
        ];

        insert new Store_Closure__c(
            Store__c = storeRecord.Id,
            Closure_Date__c = SLOT_DATE,
            Store_Time_Slot__c = secondSlot.Id,
            Type__c = 'Blackout'
        );

        buildRequest(storeRecord.Id, String.valueOf(SLOT_DATE));

        Test.startTest();
        CARAAppointmentSlotsRestService.getSlots();
        Test.stopTest();

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );

        List<Object> slots = (List<Object>) responseMap.get('slots');
        System.assertEquals(0, slots.size());
    }


    @IsTest
    static void invalidStoreReturnsBadRequest() {

        buildRequest(UserInfo.getUserId(), String.valueOf(SLOT_DATE));

        Test.startTest();
        CARAAppointmentSlotsRestService.getSlots();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }


    @IsTest
    static void invalidDateReturnsBadRequest() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];

        buildRequest(storeRecord.Id, 'not-a-date');

        Test.startTest();
        CARAAppointmentSlotsRestService.getSlots();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }


    @IsTest
    static void returnsArabicStoreNameWhenRequested() {

        Store__c storeRecord = [SELECT Id FROM Store__c LIMIT 1];

        buildRequest(storeRecord.Id, String.valueOf(SLOT_DATE), 'ar');

        Test.startTest();
        CARAAppointmentSlotsRestService.getSlots();
        Test.stopTest();

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );

        System.assertEquals('متجر كارا للاختبار', (String) responseMap.get('storeName'));
    }
}