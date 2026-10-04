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

        String mapsUrl = 'https://www.google.com/maps/search/?api=1&query=' +
            EncodingUtil.urlEncode(
                String.isNotBlank(storeRecord.Address__c) ? storeRecord.Address__c : '',
                'UTF-8'
            );

        String manageAppointmentUrl = 'mailto:info@cara.ae?subject=' +
            EncodingUtil.urlEncode('Manage Appointment - ' + bookingRecord.Name, 'UTF-8');

        String dividerRow = '<tr><td style="padding: 0 30px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0"><tr>' +
            '<td height="1" style="height: 1px; line-height: 1px; font-size: 0; background-color: #000000;">&nbsp;</td>' +
            '</tr></table></td></tr>';

        return '<table width="100%" cellpadding="0" cellspacing="0" style="background-color: #ffffff;"><tr><td align="center">' +
            '<table width="600" cellpadding="0" cellspacing="0" style="width: 600px; max-width: 600px; background-color: #ffffff; font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif;">' +

            // Header wordmark
            '<tr><td align="center" style="padding: 40px 20px 30px 20px;">' +
            '<span style="font-family: Georgia, \'Times New Roman\', serif; font-size: 26px; font-weight: 700; letter-spacing: 4px; color: #383737; text-transform: uppercase;">Cara</span>' +
            '</td></tr>' +

            // Hero image
            '<tr><td align="center">' +
            '<img src="https://carajewellers--caradev.sandbox.file.force.com/servlet/servlet.ImageServer?id=015FV005jSYsu9QYQR&amp;oid=00DFV0029Wxhzfo2QA" ' +
            'alt="A Cara jewellery specialist assisting a customer in store" width="600" ' +
            'style="display: block; width: 100%; max-width: 600px; height: auto; border: 0;" />' +
            '</td></tr>' +

            // Headline
            '<tr><td align="center" style="padding: 0 30px 20px 30px;">' +
            '<p style="margin: 0; font-family: Georgia, \'Times New Roman\', serif; font-weight: 400; font-size: 32px; line-height: 40px; text-align: center; text-transform: uppercase; color: #000000;">Your Cara appointment is confirmed</p>' +
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
            '<tr><td width="110" valign="top" style="padding: 6px 0; font-size: 14px; color: #000000; white-space: nowrap;">Date &amp; Time:</td>' +
            '<td align="right" valign="top" style="padding: 6px 0; font-size: 15px; color: #000000;">' + formatDisplayDateTime(bookingRecord.Appointment_Start__c) + '</td></tr>' +
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

            // Support note
            '<tr><td align="center" style="padding: 25px 30px 10px 30px;">' +
            '<p style="margin: 0; font-size: 15px; font-weight: 700; color: #000000;">Questions about your appointment? Reach your Cara specialist.</p>' +
            '</td></tr>' +

            dividerRow +

            // Support disclaimer
            '<tr><td align="center" style="padding: 20px 30px 30px 30px;">' +
            '<p style="margin: 0; font-size: 13px; line-height: 19px; color: #000000;">Please do not reply to this message. If you have any questions, please contact us via email at ' +
            '<a href="mailto:info@cara.ae" style="color: #000000; text-decoration: underline;">info@cara.ae</a>' +
            ' or call us at +971 4 347 8089</p>' +
            '</td></tr>' +

            // Footer band — wordmark/tagline + contact details
            '<tr><td style="background-color: #2a8ca4; padding: 35px 30px 20px 30px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0"><tr>' +
            '<td valign="top" style="font-family: Georgia, \'Times New Roman\', serif; font-size: 20px; font-weight: 700; letter-spacing: 3px; color: #ffffff; text-transform: uppercase;">Cara' +
            '<div style="margin-top: 4px; font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 12px; font-weight: 400; letter-spacing: 0.5px; color: #e0f0f3; text-transform: none;">Your Everyday Rituals</div>' +
            '</td>' +
            '<td valign="top" align="right" style="font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 13px; line-height: 19px; color: #ffffff;">' +
            '123 Main Street, Downtown, Dubai, UAE<br/>' +
            '<a href="tel:+97143478089" style="color: #ffffff; text-decoration: none;">+971 4 347 8089</a><br/>' +
            '<a href="mailto:info@cara.ae" style="color: #ffffff; text-decoration: none;">info@cara.ae</a>' +
            '</td>' +
            '</tr></table>' +
            '</td></tr>' +

            // Footer band — "we're here to help" row
            '<tr><td style="background-color: #2a8ca4; padding: 0 30px 20px 30px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0"><tr>' +
            '<td valign="top" style="font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 13px; color: #ffffff;">Our team is here, Always to help</td>' +
            '<td valign="top" align="right" style="font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 13px;">' +
            '<a href="mailto:info@cara.ae" style="color: #ffffff; text-decoration: underline;">Contact Us</a>' +
            '</td>' +
            '</tr></table>' +
            '</td></tr>' +

            // Footer band — nav links
            '<tr><td style="background-color: #2a8ca4; padding: 0 30px 20px 30px;">' +
            '<p style="margin: 0; font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 13px; line-height: 20px; color: #ffffff;">' +
            'Book an appointment &nbsp;|&nbsp; Store locations &nbsp;|&nbsp; Instagram &nbsp;|&nbsp; LinkedIn &nbsp;|&nbsp; ' +
            '<a href="https://cara.ae" style="color: #ffffff; text-decoration: underline;">cara.ae</a>' +
            '</p>' +
            '</td></tr>' +

            // Footer band — divider
            '<tr><td style="background-color: #2a8ca4; padding: 0 30px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0"><tr>' +
            '<td height="1" style="height: 1px; line-height: 1px; font-size: 0; background-color: #6fb3c4;">&nbsp;</td>' +
            '</tr></table>' +
            '</td></tr>' +

            // Footer band — legal / unsubscribe
            '<tr><td align="center" style="background-color: #2a8ca4; padding: 15px 30px 30px 30px;">' +
            '<p style="margin: 0; font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 11px; line-height: 16px; color: #d9edf1;">' +
            'You\'re receiving this email because you have an account or interacted with CARA<br/>' +
            'Unsubscribe &nbsp;|&nbsp; &copy; 2026 CARA Jewellers' +
            '</p>' +
            '</td></tr>' +

            '</table>' +
            '</td></tr></table>';
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