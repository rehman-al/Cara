@RestResource(urlMapping='/cara/appointments/availability')
global with sharing class CARAAppointmentAvailabilityRestService {

    private static final Integer DEFAULT_DAYS = 30;
    private static final Integer MAX_DAYS = 60;

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
    global static void getAvailability() {

        try {

            RestRequest requestRecord = RestContext.request;

            String fromDateValue =
                requestRecord.params.get('fromDate');

            String daysValue =
                requestRecord.params.get('days');

            Date fromDate =
                parseFromDate(fromDateValue);

            Integer numberOfDays =
                parseDays(daysValue);


            // =================================================
            // 1. ACTIVE STORES
            // =================================================

            List<Store__c> stores = [
                SELECT
                    Id,
                    Name,
                    Address__c,
                    Active__c
                FROM Store__c
                WHERE Active__c = true
                ORDER BY Name
            ];

            Set<Id> storeIds = new Set<Id>();

            for (Store__c storeRecord : stores) {
                storeIds.add(storeRecord.Id);
            }


            // =================================================
            // 2. ACTIVE STORE TIME SLOTS
            // =================================================

            List<Store_Time_Slot__c> slots =
                new List<Store_Time_Slot__c>();

            if (!storeIds.isEmpty()) {

                slots = [
                    SELECT
                        Id,
                        Name,
                        Store__c,
                        Day_of_Week__c,
                        Start_Time__c,
                        End_Time__c,
                        Active__c
                    FROM Store_Time_Slot__c
                    WHERE
                        Active__c = true
                        AND Store__c IN :storeIds
                    ORDER BY Store__c, Start_Time__c
                ];
            }


            // Store -> Day -> Slots
            Map<Id, Map<String, List<Store_Time_Slot__c>>>
                slotsByStoreAndDay =
                new Map<
                    Id,
                    Map<String, List<Store_Time_Slot__c>>
                >();

            Set<Id> slotIds = new Set<Id>();

            for (Store_Time_Slot__c slot : slots) {

                slotIds.add(slot.Id);

                if (
                    !slotsByStoreAndDay.containsKey(
                        slot.Store__c
                    )
                ) {

                    slotsByStoreAndDay.put(
                        slot.Store__c,
                        new Map<
                            String,
                            List<Store_Time_Slot__c>
                        >()
                    );
                }

                Map<String, List<Store_Time_Slot__c>>
                    slotsByDay =
                    slotsByStoreAndDay.get(
                        slot.Store__c
                    );

                if (
                    !slotsByDay.containsKey(
                        slot.Day_of_Week__c
                    )
                ) {

                    slotsByDay.put(
                        slot.Day_of_Week__c,
                        new List<Store_Time_Slot__c>()
                    );
                }

                slotsByDay
                    .get(slot.Day_of_Week__c)
                    .add(slot);
            }


            // =================================================
            // 3. EXISTING BOOKINGS
            // =================================================

            Set<String> bookedSlotKeys =
                new Set<String>();

            if (!slotIds.isEmpty()) {

                Datetime rangeStart =
                    Datetime.newInstance(
                        fromDate,
                        Time.newInstance(
                            0,
                            0,
                            0,
                            0
                        )
                    );

                Datetime rangeEnd =
                    Datetime.newInstance(
                        fromDate.addDays(numberOfDays),
                        Time.newInstance(
                            0,
                            0,
                            0,
                            0
                        )
                    );

                List<Store_Appointment_Booking__c>
                    bookings = [

                        SELECT
                            Id,
                            Store_Time_Slot__c,
                            Appointment_Start__c,
                            Appointment_End__c,
                            Status__c

                        FROM Store_Appointment_Booking__c

                        WHERE
                            Store_Time_Slot__c IN :slotIds
                            AND Status__c = 'Booked'
                            AND Appointment_Start__c >= :rangeStart
                            AND Appointment_Start__c < :rangeEnd
                    ];

                for (
                    Store_Appointment_Booking__c
                        booking : bookings
                ) {

                    if (
                        booking.Store_Time_Slot__c != null &&
                        booking.Appointment_Start__c != null
                    ) {

                        String bookedKey =
                            buildBookingKey(
                                booking.Store_Time_Slot__c,
                                booking
                                    .Appointment_Start__c
                                    .date()
                            );

                        bookedSlotKeys.add(
                            bookedKey
                        );
                    }
                }
            }


            // =================================================
            // 4. BUILD JSON RESPONSE
            // =================================================

            AvailabilityResponse responseBody =
                new AvailabilityResponse();

            responseBody.success = true;
            responseBody.stores =
                new List<StoreResponse>();


            for (Store__c storeRecord : stores) {

                StoreResponse storeResponse =
                    new StoreResponse();

                storeResponse.storeId =
                    String.valueOf(storeRecord.Id);

                storeResponse.storeName =
                    storeRecord.Name;

                storeResponse.address =
                    storeRecord.Address__c;

                storeResponse.availableDates =
                    new List<Map<String, Object>>();


                Map<String, List<Store_Time_Slot__c>>
                    storeSlotsByDay =
                    new Map<
                        String,
                        List<Store_Time_Slot__c>
                    >();


                if (
                    slotsByStoreAndDay.containsKey(
                        storeRecord.Id
                    )
                ) {

                    storeSlotsByDay =
                        slotsByStoreAndDay.get(
                            storeRecord.Id
                        );
                }


                for (
                    Integer dayOffset = 0;
                    dayOffset < numberOfDays;
                    dayOffset++
                ) {

                    Date appointmentDate =
                        fromDate.addDays(dayOffset);

                    String dayOfWeek =
                        getDayOfWeek(
                            appointmentDate
                        );


                    if (
                        !storeSlotsByDay.containsKey(
                            dayOfWeek
                        )
                    ) {
                        continue;
                    }


                    List<TimeSlotResponse>
                        availableTimeSlots =
                        new List<TimeSlotResponse>();


                    for (
                        Store_Time_Slot__c slot :
                        storeSlotsByDay.get(
                            dayOfWeek
                        )
                    ) {

                        String bookingKey =
                            buildBookingKey(
                                slot.Id,
                                appointmentDate
                            );


                        // Already booked slot
                        if (
                            bookedSlotKeys.contains(
                                bookingKey
                            )
                        ) {
                            continue;
                        }


                        TimeSlotResponse slotResponse =
                            new TimeSlotResponse();

                        slotResponse.slotId =
                            String.valueOf(slot.Id);

                        slotResponse.startTime =
                            formatTime(
                                slot.Start_Time__c
                            );

                        slotResponse.endTime =
                            formatTime(
                                slot.End_Time__c
                            );

                        availableTimeSlots.add(
                            slotResponse
                        );
                    }


                    // Only return date if at least
                    // one slot is available
                    if (
                        !availableTimeSlots.isEmpty()
                    ) {

                        Map<String, Object>
                            availableDate =
                            new Map<String, Object>();

                        availableDate.put(
                            'date',
                            String.valueOf(
                                appointmentDate
                            )
                        );

                        availableDate.put(
                            'timeSlots',
                            availableTimeSlots
                        );

                        storeResponse
                            .availableDates
                            .add(availableDate);
                    }
                }


                responseBody.stores.add(
                    storeResponse
                );
            }


            CARAAppointmentApiSupport.writeResponse(
                200,
                responseBody
            );

        }
        catch (
            CARAAppointmentApiSupport.RequestException error
        ) {

            CARAAppointmentApiSupport.writeError(
                400,
                error.getMessage()
            );

        }
        catch (Exception error) {

            System.debug(
                LoggingLevel.ERROR,
                'Appointment availability API error: '
                + error.getMessage()
            );

            CARAAppointmentApiSupport.writeError(
                500,
                'Unable to retrieve appointment availability.'
            );
        }
    }


    // =========================================================
    // REQUEST PARAMETER HELPERS
    // =========================================================

    private static Date parseFromDate(
        String fromDateValue
    ) {

        if (String.isBlank(fromDateValue)) {
            return Date.today();
        }

        try {

            return Date.valueOf(
                fromDateValue.trim()
            );

        }
        catch (Exception error) {

            throw new
                CARAAppointmentApiSupport.RequestException(
                    'fromDate must use YYYY-MM-DD format.'
                );
        }
    }


    private static Integer parseDays(
        String daysValue
    ) {

        if (String.isBlank(daysValue)) {
            return DEFAULT_DAYS;
        }

        Integer numberOfDays;

        try {

            numberOfDays =
                Integer.valueOf(
                    daysValue.trim()
                );

        }
        catch (Exception error) {

            throw new
                CARAAppointmentApiSupport.RequestException(
                    'days must be a valid number.'
                );
        }

        if (
            numberOfDays < 1 ||
            numberOfDays > MAX_DAYS
        ) {

            throw new
                CARAAppointmentApiSupport.RequestException(
                    'days must be between 1 and 60.'
                );
        }

        return numberOfDays;
    }


    // =========================================================
    // DATE / TIME HELPERS
    // =========================================================

    private static String getDayOfWeek(
        Date dateValue
    ) {

        // 1 Jan 2024 = Monday
        Date knownMonday =
            Date.newInstance(
                2024,
                1,
                1
            );

        Integer difference =
            knownMonday.daysBetween(
                dateValue
            );

        Integer dayIndex =
            Math.mod(
                difference,
                7
            );

        if (dayIndex < 0) {
            dayIndex += 7;
        }

        return DAYS_OF_WEEK[
            dayIndex
        ];
    }


    private static String formatTime(
        Time timeValue
    ) {

        if (timeValue == null) {
            return null;
        }

        return twoDigits(
            timeValue.hour()
        )
        +
        ':'
        +
        twoDigits(
            timeValue.minute()
        );
    }


    private static String twoDigits(
        Integer numberValue
    ) {

        if (numberValue < 10) {
            return '0'
                + String.valueOf(
                    numberValue
                );
        }

        return String.valueOf(
            numberValue
        );
    }


    private static String buildBookingKey(
        Id slotId,
        Date appointmentDate
    ) {

        return String.valueOf(slotId)
            + '|'
            + String.valueOf(
                appointmentDate
            );
    }


    // =========================================================
    // RESPONSE WRAPPERS
    // =========================================================

    public class AvailabilityResponse {

        public Boolean success;

        public List<StoreResponse> stores;
    }


    public class StoreResponse {

        public String storeId;

        public String storeName;

        public String address;

        public List<Map<String, Object>>
            availableDates;
    }


    public class TimeSlotResponse {

        public String slotId;

        public String startTime;

        public String endTime;
    }
}