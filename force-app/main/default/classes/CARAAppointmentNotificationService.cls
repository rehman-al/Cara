public with sharing class CARAAppointmentNotificationService {

    private static final String ICS_LINE_BREAK = '\r\n';
    private static final String DISPLAY_TIME_ZONE = 'Asia/Dubai';

    /*
     * Sends the guest confirmation email with an attached .ics calendar
     * invite for the in-store visit. This is a best-effort side effect —
     * the appointment has already been committed by the time this runs,
     * so a failure here (bad email, deliverability, etc.) must never
     * surface as a booking failure to the caller.
     *
     * The outcome is always written back to Confirmation_Email_Status__c /
     * Confirmation_Email_Error__c so a send failure is visible on the
     * record itself — debug logs expire, this doesn't.
     */
    public static void sendBookingConfirmation(
        Store_Appointment_Booking__c bookingRecord,
        Store__c storeRecord,
        Contact customerContact
    ) {

        String status;
        String errorDetail;

        try {

            if (customerContact == null || String.isBlank(customerContact.Email)) {

                status = 'Skipped - No Email';

            } else {

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

                // Addressed via the Contact (not raw setToAddresses) so the
                // email correctly logs as an Activity against the Contact,
                // and Salesforce resolves the recipient itself.
                mail.setTargetObjectId(customerContact.Id);
                mail.setSaveAsActivity(true);

                mail.setSubject(
                    'Your Cara Jewellers Appointment is Confirmed - ' + bookingRecord.Name
                );
                mail.setHtmlBody(
                    buildEmailBody(bookingRecord, storeRecord, customerContact)
                );

                Messaging.EmailFileAttachment icsAttachment =
                    new Messaging.EmailFileAttachment();

                icsAttachment.setFileName('Cara-Jewellers-Appointment.ics');
                icsAttachment.setContentType('text/calendar; charset=UTF-8; method=PUBLISH');
                icsAttachment.setBody(
                    Blob.valueOf(buildIcsContent(bookingRecord, storeRecord))
                );

                mail.setFileAttachments(
                    new Messaging.EmailFileAttachment[]{ icsAttachment }
                );

                Messaging.sendEmail(
                    new Messaging.SingleEmailMessage[]{ mail }
                );

                status = 'Sent';
            }

        } catch (Exception error) {

            status = 'Failed';
            errorDetail = error.getTypeName() + ': ' + error.getMessage();

            System.debug(
                LoggingLevel.ERROR,
                'Appointment confirmation email failed for booking ' +
                bookingRecord.Id + ': ' + errorDetail
            );
        }

        recordOutcome(bookingRecord.Id, status, errorDetail);
    }


    /*
     * Separate, equally defensive try/catch: recording the outcome must
     * never be able to surface an error either.
     */
    private static void recordOutcome(
        Id bookingId,
        String status,
        String errorDetail
    ) {

        try {

            update new Store_Appointment_Booking__c(
                Id = bookingId,
                Confirmation_Email_Status__c = status,
                Confirmation_Email_Error__c = errorDetail
            );

        } catch (Exception updateError) {

            System.debug(
                LoggingLevel.ERROR,
                'Failed to record confirmation email status for booking ' +
                bookingId + ': ' + updateError.getMessage()
            );
        }
    }


    // =========================================================
    // EMAIL BODY
    // =========================================================

    @TestVisible
    private static String buildEmailBody(
        Store_Appointment_Booking__c bookingRecord,
        Store__c storeRecord,
        Contact customerContact
    ) {

        String customerName = String.isNotBlank(customerContact.FirstName)
            ? customerContact.FirstName
            : 'there';

        return '<div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">' +
            '<h2 style="color: #7c5a2e;">Your appointment is confirmed</h2>' +
            '<p>Hi <b>' + customerName + '</b>,</p>' +
            '<p>We look forward to seeing you in store. Here are your appointment details:</p>' +
            '<hr style="border: none; border-top: 1px solid #eee;" />' +
            '<ul>' +
            '<li><b>Appointment #:</b> ' + bookingRecord.Name + '</li>' +
            '<li><b>Store:</b> ' + storeRecord.Name + '</li>' +
            '<li><b>Address:</b> ' + storeRecord.Address__c + '</li>' +
            '<li><b>Date &amp; Time:</b> ' + formatDisplayDateTime(bookingRecord.Appointment_Start__c) + '</li>' +
            '<li><b>Interested in:</b> ' + bookingRecord.interested_in__c + '</li>' +
            '</ul>' +
            '<p>This is an in-store visit — a calendar invite with the store location is attached to this email.</p>' +
            '<p>If you need to reschedule or cancel, please contact us.</p>' +
            '<br/><p>Best regards,<br/><b>Cara Jewellers</b></p>' +
            '</div>';
    }


    private static String formatDisplayDateTime(Datetime dateTimeValue) {

        return dateTimeValue.format('EEEE, d MMMM yyyy', DISPLAY_TIME_ZONE) +
            ' at ' +
            dateTimeValue.format('h:mm a', DISPLAY_TIME_ZONE);
    }


    // =========================================================
    // CALENDAR INVITE (.ics)
    //
    // On-site visit only: LOCATION carries the store address and
    // nothing here sets a conferencing/meeting URL, per the explicit
    // "on-site visit, not Google Meet" requirement.
    // =========================================================

    @TestVisible
    private static String buildIcsContent(
        Store_Appointment_Booking__c bookingRecord,
        Store__c storeRecord
    ) {

        String uid = bookingRecord.Id + '@carajewellers.com';

        String description = 'In-store appointment at ' + storeRecord.Name +
            '. Appointment #' + bookingRecord.Name + '.';

        List<String> lines = new List<String>{
            'BEGIN:VCALENDAR',
            'VERSION:2.0',
            'PRODID:-//Cara Jewellers//Appointment Booking//EN',
            'CALSCALE:GREGORIAN',
            'METHOD:PUBLISH',
            'BEGIN:VEVENT',
            'UID:' + uid,
            'DTSTAMP:' + formatIcsDateTime(Datetime.now()),
            'DTSTART:' + formatIcsDateTime(bookingRecord.Appointment_Start__c),
            'DTEND:' + formatIcsDateTime(bookingRecord.Appointment_End__c),
            'SUMMARY:' + escapeIcsText('Cara Jewellers Appointment - ' + storeRecord.Name),
            'DESCRIPTION:' + escapeIcsText(description),
            'LOCATION:' + escapeIcsText(storeRecord.Address__c),
            'STATUS:CONFIRMED',
            'TRANSP:OPAQUE',
            'END:VEVENT',
            'END:VCALENDAR'
        };

        return String.join(lines, ICS_LINE_BREAK);
    }


    private static String formatIcsDateTime(Datetime dateTimeValue) {

        return dateTimeValue.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
    }


    private static String escapeIcsText(String value) {

        if (String.isBlank(value)) {
            return '';
        }

        return value
            .replace('\\', '\\\\')
            .replace(';', '\\;')
            .replace(',', '\\,')
            .replace('\n', '\\n');
    }
}