/*
 * Customer notifications for the N-Genius split-payment links (deposit /
 * balance). Follows the same best-effort shape as
 * CARAAppointmentNotificationService: a failed send must never fail the
 * caller's transaction, since the basket/balance-link has already been
 * created successfully in SFCC/MRT by the time this runs.
 *
 * SMS is intentionally not implemented — this org has no SMS
 * gateway/Named Credential configured anywhere (only callout:SFSC_Order_Ops
 * exists). Per the same "don't guess a contract that isn't there" rule
 * behind CARANGeniusPaymentService, wiring a fabricated SMS integration
 * would be worse than not having one. Email is sent on every call; add SMS
 * here once a provider is chosen.
 *
 * Unlike CARAAppointmentNotificationService, this returns an outcome to the
 * caller rather than writing its own status field — the Queueables append
 * it to the same Basket_Log__c / Balance_Link_Log__c audit trail already
 * used for the callout result, so each record has one log instead of two.
 */
public with sharing class CARASplitPaymentNotificationService {

    public class NotificationOutcome {
        public Boolean sent = false;
        public String detail;
    }


    /*
     * Deposit link (Link 1) — the Custom Product Request's Case always has
     * a real Contact, so this logs as an Activity against it.
     */
    public static NotificationOutcome sendDepositLink(
        Contact customerContact,
        String requestName,
        Decimal depositAmount,
        String depositLink
    ) {
        String firstName = customerContact != null && String.isNotBlank(customerContact.FirstName)
            ? customerContact.FirstName
            : 'there';

        return send(
            customerContact != null ? customerContact.Id : null,
            customerContact != null ? customerContact.Email : null,
            'Complete Your Deposit - ' + requestName,
            buildDepositEmailBody(firstName, requestName, depositAmount, buildStorefrontUrl(depositLink))
        );
    }


    /*
     * Balance link (Link 2) — Order has no reliable Contact lookup in this
     * org's schema, only Customer_Email__c / Customer_Name__c, so this
     * sends by raw address rather than via a Contact Id.
     */
    public static NotificationOutcome sendBalanceLink(
        String customerEmail,
        String customerName,
        String orderNumber,
        Decimal remainingAmount,
        String balanceLink
    ) {
        String firstName = String.isNotBlank(customerName) ? customerName : 'there';

        return send(
            null,
            customerEmail,
            'Your Piece is Ready - Balance Payment Due for Order ' + orderNumber,
            buildBalanceEmailBody(firstName, orderNumber, remainingAmount, buildStorefrontUrl(balanceLink))
        );
    }


    /*
     * SFCC/MRT's deposit-basket and balance-link responses are not
     * guaranteed to return an absolute URL — a relative path has no
     * storefront domain to resolve against once it is dropped into an
     * email. Prepends the admin-configured storefront base (Split_Payment_
     * Setting__mdt.Storefront_Base_URI__c, e.g. https://sfccdev.
     * carajewellers.com/en-ae) to any relative link; an already-absolute
     * link is left untouched. SFCC usually returns the path with its own
     * locale (/en-AE/pay/deposit?...), so in that case only the base's
     * domain is used — otherwise the locale ends up twice (/en-ae/en-AE/).
     */
    @TestVisible
    private static String buildStorefrontUrl(String rawLink) {
        if (String.isBlank(rawLink)) {
            return rawLink;
        }
        if (rawLink.toLowerCase().startsWith('http://') || rawLink.toLowerCase().startsWith('https://')) {
            return rawLink;
        }

        String baseUri = CARASplitPaymentSettings.getStorefrontBaseUri();
        if (String.isBlank(baseUri)) {
            return rawLink;
        }

        String normalizedBase = baseUri.endsWith('/') ? baseUri.removeEnd('/') : baseUri;
        String normalizedPath = rawLink.startsWith('/') ? rawLink : '/' + rawLink;
        if (Pattern.matches('^/[a-zA-Z]{2}-[a-zA-Z]{2}/.*', normalizedPath)) {
            Url baseUrl = new Url(normalizedBase);
            normalizedBase = baseUrl.getProtocol() + '://' + baseUrl.getAuthority();
        }
        return normalizedBase + normalizedPath;
    }


    private static NotificationOutcome send(Id contactId, String email, String subject, String htmlBody) {
        NotificationOutcome outcome = new NotificationOutcome();

        try {
            if (String.isBlank(email)) {
                outcome.sent = false;
                outcome.detail = 'Skipped - No Email';
                return outcome;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

            if (contactId != null) {
                // Addressed via the Contact so it correctly logs as an
                // Activity against it, same convention as
                // CARAAppointmentNotificationService.
                mail.setTargetObjectId(contactId);
                mail.setSaveAsActivity(true);
            } else {
                mail.setToAddresses(new String[]{ email });
                mail.setSaveAsActivity(false);
            }

            mail.setSubject(subject);
            mail.setHtmlBody(htmlBody);

            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });

            outcome.sent = true;
            outcome.detail = 'Sent to ' + email;

        } catch (Exception error) {
            outcome.sent = false;
            outcome.detail = 'Failed: ' + error.getTypeName() + ': ' + error.getMessage();

            System.debug(
                LoggingLevel.ERROR,
                'Split-payment notification failed for ' + email + ': ' + outcome.detail
            );
        }

        return outcome;
    }


    /*
     * Header/footer/nav links come from CARAEmailBrandingUtil, the same
     * shared source of truth used by the appointment confirmation and
     * custom product request confirmation emails.
     */
    @TestVisible
    private static String buildDepositEmailBody(
        String firstName,
        String requestName,
        Decimal depositAmount,
        String depositLink
    ) {
        String bodyRows =
            '<tr><td align="center" style="padding: 0 30px 20px 30px;">' +
            '<p style="margin: 0; font-family: \'Playfair Display\', Georgia, \'Times New Roman\', serif; font-weight: 700; font-size: 28px; line-height: 36px; text-align: center; text-transform: uppercase; color: #000000;">Your deposit is ready to pay</p>' +
            '</td></tr>' +

            '<tr><td align="center" style="padding: 0 30px 25px 30px;">' +
            '<p style="margin: 0 0 10px 0; font-size: 16px; line-height: 22px; color: #000000;">Hi <b>' + firstName + '</b>,</p>' +
            '<p style="margin: 0; font-size: 16px; line-height: 22px; color: #000000;">Your custom piece <b>' + requestName + '</b> has been approved. Please pay your deposit of <b>' + formatAmount(depositAmount) + '</b> to begin production.</p>' +
            '</td></tr>' +

            '<tr><td align="center" style="padding: 0 30px 15px 30px;">' +
            '<table cellpadding="0" cellspacing="0"><tr>' +
            '<td align="center" style="background-color: #2a8ca4; border-radius: 10px;">' +
            '<a href="' + depositLink + '" style="display: inline-block; padding: 14px 35px; font-size: 16px; color: #ffffff; text-decoration: none; font-weight: 500;">Pay Deposit</a>' +
            '</td></tr></table>' +
            '</td></tr>' +

            '<tr><td align="center" style="padding: 0 30px 25px 30px;">' +
            '<p style="margin: 0; font-size: 13px; line-height: 19px; color: #000000;">If the button does not work, copy and paste this link into your browser:<br/>' + depositLink + '</p>' +
            '</td></tr>' +

            CARAEmailBrandingUtil.divider();

        return CARAEmailBrandingUtil.wrapEmail(bodyRows);
    }


    @TestVisible
    private static String buildBalanceEmailBody(
        String firstName,
        String orderNumber,
        Decimal remainingAmount,
        String balanceLink
    ) {
        String bodyRows =
            '<tr><td align="center" style="padding: 0 30px 20px 30px;">' +
            '<p style="margin: 0; font-family: \'Playfair Display\', Georgia, \'Times New Roman\', serif; font-weight: 700; font-size: 28px; line-height: 36px; text-align: center; text-transform: uppercase; color: #000000;">Your piece is ready</p>' +
            '</td></tr>' +

            '<tr><td align="center" style="padding: 0 30px 25px 30px;">' +
            '<p style="margin: 0 0 10px 0; font-size: 16px; line-height: 22px; color: #000000;">Hi <b>' + firstName + '</b>,</p>' +
            '<p style="margin: 0; font-size: 16px; line-height: 22px; color: #000000;">Great news — your order <b>' + orderNumber + '</b> is ready for delivery. Please pay the remaining balance of <b>' + formatAmount(remainingAmount) + '</b> to proceed.</p>' +
            '</td></tr>' +

            '<tr><td align="center" style="padding: 0 30px 15px 30px;">' +
            '<table cellpadding="0" cellspacing="0"><tr>' +
            '<td align="center" style="background-color: #2a8ca4; border-radius: 10px;">' +
            '<a href="' + balanceLink + '" style="display: inline-block; padding: 14px 35px; font-size: 16px; color: #ffffff; text-decoration: none; font-weight: 500;">Pay Balance</a>' +
            '</td></tr></table>' +
            '</td></tr>' +

            '<tr><td align="center" style="padding: 0 30px 25px 30px;">' +
            '<p style="margin: 0; font-size: 13px; line-height: 19px; color: #000000;">If the button does not work, copy and paste this link into your browser:<br/>' + balanceLink + '</p>' +
            '</td></tr>' +

            CARAEmailBrandingUtil.divider();

        return CARAEmailBrandingUtil.wrapEmail(bodyRows);
    }


    private static String formatAmount(Decimal amount) {
        return amount == null ? '' : amount.setScale(2).format();
    }
}