@RestResource(urlMapping='/cara/appointments/slots')
global with sharing class CARAAppointmentSlotsRestService {

    private static final List<String> DAYS_OF_WEEK =
        new List<String>{
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
            'Sunday'
        };

    @HttpGet
    global static void getSlots() {

        try {

            RestRequest requestRecord = RestContext.request;

            Id storeId = validateStoreId(
                requestRecord.params.get('storeId')
            );

            Date appointmentDate = parseDate(
                requestRecord.params.get('date')
            );

            Boolean useArabic = isArabic(
                requestRecord.params.get('lang')
            );


            // =================================================
            // 1. READ STORE & PATTERN CONFIG
            // =================================================

            List<Store__c> stores = [
                SELECT Id, Name, Address__c, Name_AR__c, Active__c
                FROM Store__c
                WHERE Id = :storeId
                LIMIT 1
            ];

            if (stores.isEmpty() || stores[0].Active__c != true) {
                throw new CARAAppointmentApiSupport.RequestException(
                    'Selected store is invalid or inactive.'
                );
            }

            Store__c storeRecord = stores[0];

            String dayOfWeek = getDayOfWeek(appointmentDate);


            // =================================================
            // 2. HOLIDAYS / CLOSURES (whole store blocked)
            // =================================================

            List<Store_Closure__c> storeClosures = [
                SELECT Id, Reason__c, Type__c
                FROM Store_Closure__c
                WHERE Store__c = :storeId
                    AND Closure_Date__c = :appointmentDate
                    AND Store_Time_Slot__c = null
                LIMIT 1
            ];

            SlotsResponse responseBody = new SlotsResponse();
            responseBody.success = true;
            responseBody.storeId = String.valueOf(storeRecord.Id);
            responseBody.storeName = useArabic
                ? firstNonBlank(storeRecord.Name_AR__c, storeRecord.Name)
                : storeRecord.Name;
            responseBody.appointmentDate = String.valueOf(appointmentDate);
            responseBody.slots = new List<SlotDetail>();

            if (!storeClosures.isEmpty()) {

                responseBody.closed = true;
                responseBody.closureReason = String.isBlank(
                    storeClosures[0].Reason__c
                )
                    ? storeClosures[0].Type__c
                    : storeClosures[0].Reason__c;

                CARAAppointmentApiSupport.writeResponse(200, responseBody);
                return;
            }

            responseBody.closed = false;


            // =================================================
            // 3. DYNAMIC SLOT CALCULATION for the store + day
            // =================================================

            List<Store_Time_Slot__c> slots = [
                SELECT Id, Start_Time__c, End_Time__c, Capacity__c
                FROM Store_Time_Slot__c
                WHERE Store__c = :storeId
                    AND Day_of_Week__c = :dayOfWeek
                    AND Active__c = true
                ORDER BY Start_Time__c
            ];

            if (slots.isEmpty()) {
                CARAAppointmentApiSupport.writeResponse(200, responseBody);
                return;
            }

            Set<Id> slotIds = new Map<Id, Store_Time_Slot__c>(slots).keySet();


            // =================================================
            // 4. BLACKOUTS / RESTRICTIONS (specific slots blocked)
            // =================================================

            Set<Id> blackedOutSlotIds = new Set<Id>();

            for (Store_Closure__c blackout : [
                SELECT Store_Time_Slot__c
                FROM Store_Closure__c
                WHERE Store__c = :storeId
                    AND Closure_Date__c = :appointmentDate
                    AND Store_Time_Slot__c IN :slotIds
            ]) {
                blackedOutSlotIds.add(blackout.Store_Time_Slot__c);
            }


            // =================================================
            // 5. AGGREGATE ACTIVE APPOINTMENTS FOR THE DATE
            // =================================================

            Datetime rangeStart = Datetime.newInstance(
                appointmentDate,
                Time.newInstance(0, 0, 0, 0)
            );

            Datetime rangeEnd = Datetime.newInstance(
                appointmentDate.addDays(1),
                Time.newInstance(0, 0, 0, 0)
            );

            Map<Id, Integer> bookedCountBySlot = new Map<Id, Integer>();

            for (AggregateResult aggregateRow : [
                SELECT Store_Time_Slot__c slotId, COUNT(Id) bookedCount
                FROM Store_Appointment_Booking__c
                WHERE Store_Time_Slot__c IN :slotIds
                    AND Status__c = 'Booked'
                    AND Appointment_Start__c >= :rangeStart
                    AND Appointment_Start__c < :rangeEnd
                GROUP BY Store_Time_Slot__c
            ]) {
                bookedCountBySlot.put(
                    (Id) aggregateRow.get('slotId'),
                    (Integer) aggregateRow.get('bookedCount')
                );
            }


            // =================================================
            // 6. COMPUTE AVAILABILITY (Capacity - Bookings)
            // =================================================

            for (Store_Time_Slot__c slot : slots) {

                if (blackedOutSlotIds.contains(slot.Id)) {
                    continue;
                }

                Integer capacity = slot.Capacity__c == null
                    ? 1
                    : Integer.valueOf(slot.Capacity__c);

                Integer bookedCount = bookedCountBySlot.containsKey(slot.Id)
                    ? bookedCountBySlot.get(slot.Id)
                    : 0;

                Integer remaining = capacity - bookedCount;

                if (remaining <= 0) {
                    continue;
                }

                SlotDetail slotDetail = new SlotDetail();
                slotDetail.slotId = String.valueOf(slot.Id);
                slotDetail.startTime = formatTime(slot.Start_Time__c);
                slotDetail.endTime = formatTime(slot.End_Time__c);
                slotDetail.capacity = capacity;
                slotDetail.remainingCapacity = remaining;

                responseBody.slots.add(slotDetail);
            }

            CARAAppointmentApiSupport.writeResponse(200, responseBody);

        } catch (CARAAppointmentApiSupport.RequestException error) {

            CARAAppointmentApiSupport.writeError(400, error.getMessage());

        } catch (Exception error) {

            System.debug(
                LoggingLevel.ERROR,
                'Appointment slots API error: ' + error.getMessage()
            );

            CARAAppointmentApiSupport.writeError(
                500,
                'Unable to retrieve available slots.'
            );
        }
    }


    // =========================================================
    // LOCALIZATION HELPERS
    // =========================================================

    private static Boolean isArabic(String langValue) {
        return String.isNotBlank(langValue)
            && langValue.trim().equalsIgnoreCase('ar');
    }


    private static String firstNonBlank(String preferredValue, String fallbackValue) {
        return String.isNotBlank(preferredValue) ? preferredValue : fallbackValue;
    }


    // =========================================================
    // VALIDATION HELPERS
    // =========================================================

    private static Id validateStoreId(String storeIdValue) {

        if (String.isBlank(storeIdValue)) {
            throw new CARAAppointmentApiSupport.RequestException(
                'storeId is required.'
            );
        }

        Id storeId;

        try {
            storeId = Id.valueOf(storeIdValue.trim());
        } catch (Exception error) {
            throw new CARAAppointmentApiSupport.RequestException(
                'storeId must be a valid Salesforce Id.'
            );
        }

        if (storeId.getSObjectType() != Store__c.SObjectType) {
            throw new CARAAppointmentApiSupport.RequestException(
                'storeId references the wrong object.'
            );
        }

        return storeId;
    }


    private static Date parseDate(String dateValue) {

        if (String.isBlank(dateValue)) {
            throw new CARAAppointmentApiSupport.RequestException(
                'date is required.'
            );
        }

        try {
            return Date.valueOf(dateValue.trim());
        } catch (Exception error) {
            throw new CARAAppointmentApiSupport.RequestException(
                'date must use YYYY-MM-DD format.'
            );
        }
    }


    // =========================================================
    // DATE / TIME HELPERS
    // =========================================================

    private static String getDayOfWeek(Date dateValue) {

        Date knownMonday = Date.newInstance(2024, 1, 1);

        Integer difference = knownMonday.daysBetween(dateValue);
        Integer dayIndex = Math.mod(difference, 7);

        if (dayIndex < 0) {
            dayIndex += 7;
        }

        return DAYS_OF_WEEK[dayIndex];
    }


    private static String formatTime(Time timeValue) {

        if (timeValue == null) {
            return null;
        }

        return twoDigits(timeValue.hour()) + ':' + twoDigits(timeValue.minute());
    }


    private static String twoDigits(Integer numberValue) {

        if (numberValue < 10) {
            return '0' + String.valueOf(numberValue);
        }

        return String.valueOf(numberValue);
    }


    // =========================================================
    // RESPONSE WRAPPERS
    // =========================================================

    public class SlotsResponse {
        public Boolean success;
        public String storeId;
        public String storeName;
        public String appointmentDate;
        public Boolean closed;
        public String closureReason;
        public List<SlotDetail> slots;
    }


    public class SlotDetail {
        public String slotId;
        public String startTime;
        public String endTime;
        public Integer capacity;
        public Integer remainingCapacity;
    }
}