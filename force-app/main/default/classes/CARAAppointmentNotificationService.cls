public with sharing class CARAAppointmentNotificationService {

    private static final String ICS_LINE_BREAK = '\r\n';
    private static final String DISPLAY_TIME_ZONE = 'Asia/Dubai';

    /*
     * Sends the guest confirmation email with an attached .ics calendar
     * invite for the in-store visit, as a single native email (not routed
     * through Marketing Cloud — that path's actions360 send API has no
     * attachment support, so it can't carry the .ics on the same send;
     * see CARAAppointmentNotificationQueueable for that now-unused route).
     * This is a best-effort side effect — the appointment has already been
     * committed by the time this runs, so a failure here (bad email,
     * deliverability, etc.) must never surface as a booking failure to the
     * caller.
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

        String mapsUrl = 'https://www.google.com/maps/search/?api=1&query=' +
            EncodingUtil.urlEncode(
                String.isNotBlank(storeRecord.Address__c) ? storeRecord.Address__c : '',
                'UTF-8'
            );

        String manageAppointmentUrl = 'mailto:info@cara.ae?subject=' +
            EncodingUtil.urlEncode('Manage Appointment - ' + bookingRecord.Name, 'UTF-8');

        // formatDisplayDateTime() returns "<date> at <time>, Dubai time" as a
        // single string. The design shows Date and Time as separate rows, so
        // that one call is split on its own " at " separator rather than
        // duplicating the date-formatting logic here.
        String fullDisplayDateTime = formatDisplayDateTime(bookingRecord.Appointment_Start__c);
        List<String> displayDateTimeParts = fullDisplayDateTime.split(' at ', 2);
        String displayDate = displayDateTimeParts[0];
        String displayTime = displayDateTimeParts.size() > 1 ? displayDateTimeParts[1] : fullDisplayDateTime;

        String dividerRow = CARAEmailBrandingUtil.divider();

        // Playfair Display approximates the Figma display-serif headline.
        // Gmail and Outlook strip <style> blocks entirely, so this @import
        // is a progressive enhancement only — those clients (and any other
        // that ignores it) silently fall back to the Georgia serif below.
        // Header, footer and nav links come from CARAEmailBrandingUtil, the
        // shared source of truth also used by the payment-link and custom
        // product request confirmation emails.
        // Hero image now comes from CARAEmailBrandingUtil.wrapEmail() (via
        // heroImage()), shared with every other template, rather than this
        // org-specific hardcoded URL.
        String bodyRows =

            // Headline
            '<tr><td align="center" style="padding: 0 30px 20px 30px;">' +
            '<p style="margin: 0; font-family: \'Playfair Display\', Georgia, \'Times New Roman\', serif; font-weight: 700; font-size: 32px; line-height: 40px; text-align: center; text-transform: uppercase; color: #000000;">Your Cara appointment is confirmed</p>' +
            '</td></tr>' +

            // Greeting + intro
            '<tr><td align="center" style="padding: 0 30px 25px 30px;">' +
            '<p style="margin: 0 0 10px 0; font-size: 16px; line-height: 22px; color: #000000;">Hi <b>' + customerName + '</b>,</p>' +
            '<p style="margin: 0; font-size: 16px; line-height: 22px; color: #000000;">Your one-to-one appointment with a Cara expert is confirmed. We look forward to welcoming you.</p>' +
            '</td></tr>' +

            // Appointment band
            '<tr><td style="padding: 0 20px 20px 20px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0"><tr>' +
            '<td align="left" style="background-color: #bfdde4; padding: 14px 16px; font-size: 16px; font-weight: 700; color: #000000;">Your appointment &nbsp;#' + bookingRecord.Name + '</td>' +
            '</tr></table>' +
            '</td></tr>' +

            // Boutique / date & time / interest details
            '<tr><td style="padding: 0 30px 20px 30px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0">' +
            '<tr><td width="110" valign="top" style="padding: 6px 0; font-size: 14px; color: #000000; white-space: nowrap;">Boutique:</td>' +
            '<td align="right" valign="top" style="padding: 6px 0; font-size: 15px; color: #000000;">' + storeRecord.Name + '<br/>' + storeRecord.Address__c + '</td></tr>' +
            '<tr><td width="110" valign="top" style="padding: 6px 0; font-size: 14px; color: #000000; white-space: nowrap;">Date:</td>' +
            '<td align="right" valign="top" style="padding: 6px 0; font-size: 15px; color: #000000;">' + displayDate + '</td></tr>' +
            '<tr><td width="110" valign="top" style="padding: 6px 0; font-size: 14px; color: #000000; white-space: nowrap;">Time:</td>' +
            '<td align="right" valign="top" style="padding: 6px 0; font-size: 15px; color: #000000;">' + displayTime + '</td></tr>' +
            '<tr><td width="110" valign="top" style="padding: 6px 0; font-size: 14px; color: #000000; white-space: nowrap;">Interested in:</td>' +
            '<td align="right" valign="top" style="padding: 6px 0; font-size: 15px; color: #000000;">' + bookingRecord.interested_in__c + '</td></tr>' +
            '</table>' +
            '</td></tr>' +

            // Maps link
            '<tr><td align="center" style="padding: 0 30px 20px 30px;">' +
            '<a href="' + mapsUrl + '" style="font-size: 14px; color: #2a8ca4; text-decoration: underline;">View on Google Maps</a>' +
            '</td></tr>' +

            dividerRow +

            // Arrival note (keeps the in-store-visit / .ics callout)
            '<tr><td align="center" style="padding: 20px 30px 25px 30px;">' +
            '<p style="margin: 0; font-size: 15px; line-height: 21px; color: #000000;">Please arrive a few minutes before your appointment. Our team will be ready to welcome you and assist you throughout your visit. This is an in-store visit — a calendar invite with the store location is attached to this email.</p>' +
            '</td></tr>' +

            // Primary CTA
            '<tr><td align="center" style="padding: 0 30px 35px 30px;">' +
            '<table cellpadding="0" cellspacing="0"><tr>' +
            '<td align="center" style="background-color: #2a8ca4; border-radius: 10px;">' +
            '<a href="' + manageAppointmentUrl + '" style="display: inline-block; padding: 14px 35px; font-size: 16px; color: #ffffff; text-decoration: none; font-weight: 500;">Manage Appointment</a>' +
            '</td></tr></table>' +
            '</td></tr>' +

            dividerRow +

            // Support note (business-specific; kept out of the shared footer)
            '<tr><td align="left" style="padding: 25px 30px 10px 30px;">' +
            '<p style="margin: 0 0 4px 0; font-size: 15px; font-weight: 700; color: #000000;">Questions about your appointment?</p>' +
            '<p style="margin: 0;"><a href="mailto:info@cara.ae" style="font-size: 15px; color: #2a8ca4; text-decoration: underline;">Reach your Cara specialist.</a></p>' +
            '</td></tr>' +

            dividerRow;

        return CARAEmailBrandingUtil.wrapEmail(bodyRows);
    }


    /*
     * The .ics attachment carries the appointment time as an absolute
     * UTC instant, so a recipient's calendar app renders it in whatever
     * timezone that app/device is set to (e.g. Pakistan), while this
     * email body always renders it in the store's timezone (Dubai).
     * Both are "correct" but can look like a mismatch to the recipient,
     * so the Dubai timezone is called out explicitly here.
     */
    private static String formatDisplayDateTime(Datetime dateTimeValue) {

        return dateTimeValue.format('EEEE, d MMMM yyyy', DISPLAY_TIME_ZONE) +
            ' at ' +
            dateTimeValue.format('h:mm a', DISPLAY_TIME_ZONE) +
            ', Dubai time';
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