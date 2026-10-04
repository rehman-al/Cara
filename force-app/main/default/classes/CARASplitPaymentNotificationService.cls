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
            buildDepositEmailBody(firstName, requestName, depositAmount, depositLink)
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
            buildBalanceEmailBody(firstName, orderNumber, remainingAmount, balanceLink)
        );
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


    private static String buildDepositEmailBody(
        String firstName,
        String requestName,
        Decimal depositAmount,
        String depositLink
    ) {
        return '<div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">' +
            '<h2 style="color: #7c5a2e;">Your deposit is ready to pay</h2>' +
            '<p>Hi <b>' + firstName + '</b>,</p>' +
            '<p>Your custom piece <b>' + requestName + '</b> has been approved. ' +
            'Please pay your deposit of <b>' + formatAmount(depositAmount) + '</b> to begin production.</p>' +
            '<p><a href="' + depositLink + '" style="display:inline-block;padding:12px 24px;background:#7c5a2e;color:#fff;' +
            'text-decoration:none;border-radius:4px;">Pay Deposit</a></p>' +
            '<p>If the button does not work, copy and paste this link into your browser:<br/>' + depositLink + '</p>' +
            '<br/><p>Best regards,<br/><b>Cara Jewellers</b></p>' +
            '</div>';
    }


    private static String buildBalanceEmailBody(
        String firstName,
        String orderNumber,
        Decimal remainingAmount,
        String balanceLink
    ) {
        return '<div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">' +
            '<h2 style="color: #7c5a2e;">Your piece is ready</h2>' +
            '<p>Hi <b>' + firstName + '</b>,</p>' +
            '<p>Great news — your order <b>' + orderNumber + '</b> is ready for delivery. ' +
            'Please pay the remaining balance of <b>' + formatAmount(remainingAmount) + '</b> to proceed.</p>' +
            '<p><a href="' + balanceLink + '" style="display:inline-block;padding:12px 24px;background:#7c5a2e;color:#fff;' +
            'text-decoration:none;border-radius:4px;">Pay Balance</a></p>' +
            '<p>If the button does not work, copy and paste this link into your browser:<br/>' + balanceLink + '</p>' +
            '<br/><p>Best regards,<br/><b>Cara Jewellers</b></p>' +
            '</div>';
    }


    private static String formatAmount(Decimal amount) {
        return amount == null ? '' : amount.setScale(2).format();
    }
}