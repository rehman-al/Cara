/*
 * Single source of truth for the Cara-branded HTML email header/footer,
 * shared by every live customer-facing transactional email (appointment
 * confirmation, deposit/balance payment links, custom product request
 * confirmation) so the branding/navigation only ever needs updating here.
 *
 * Nav URLs are the org's approved footer links (Service Cloud email
 * templates initiative) - do not substitute without updating the approved
 * link list first.
 */
public with sharing class CARAEmailBrandingUtil {

    public static final String APPOINTMENTS_URL = 'https://sfccstg.carajewellers.com/en-AE/appointments';
    public static final String STORE_LOCATOR_URL = 'https://sfccstg.carajewellers.com/en-AE/store-locator';
    public static final String INSTAGRAM_URL = 'https://www.instagram.com/carajewellers/?hl=en';
    public static final String FACEBOOK_URL = 'https://www.facebook.com/carajewellers/';
    public static final String WEBSITE_URL = 'https://carajewellers.com/';

    private static final String HERO_IMAGE_DOCUMENT_NAME = 'CARA_Appointment_Email_Hero';
    private static String cachedHeroImageDocumentId;
    private static Boolean heroImageLookupDone = false;

    /*
     * The hero image is a classic Document, uploaded separately into each
     * org (its Id is org-specific, so it can't be hardcoded). Looked up by
     * Name and cached per transaction, then combined with the running org's
     * own My Domain + org Id so the same code renders correctly in every
     * org it's deployed to, rather than pointing at one org's file domain.
     */
    private static String heroImageUrl() {
        if (!heroImageLookupDone) {
            heroImageLookupDone = true;
            List<Document> docs = [
                SELECT Id FROM Document WHERE Name = :HERO_IMAGE_DOCUMENT_NAME WITH SYSTEM_MODE LIMIT 1
            ];
            cachedHeroImageDocumentId = docs.isEmpty() ? null : docs[0].Id;
        }

        if (String.isBlank(cachedHeroImageDocumentId)) {
            return null;
        }

        String fileDomain = Url.getOrgDomainUrl().toExternalForm().replace('.my.salesforce.com', '.file.force.com');
        return fileDomain + '/servlet/servlet.ImageServer?id=' + cachedHeroImageDocumentId +
            '&oid=' + UserInfo.getOrganizationId();
    }

    /*
     * Shared hero banner row, used by every template's header. Renders
     * nothing (rather than a broken image) if the Document hasn't been
     * uploaded into the current org yet.
     */
    public static String heroImage() {
        String imageUrl = heroImageUrl();
        if (String.isBlank(imageUrl)) {
            return '';
        }

        return '<tr><td align="center">' +
            '<img src="' + imageUrl + '" ' +
            'alt="A Cara jewellery specialist assisting a customer in store" width="600" ' +
            'style="display: block; width: 100%; max-width: 600px; height: auto; border: 0;" />' +
            '</td></tr>';
    }

    public static String divider() {
        return '<tr><td style="padding: 0 30px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0"><tr>' +
            '<td height="1" style="height: 1px; line-height: 1px; font-size: 0; background-color: #000000;">&nbsp;</td>' +
            '</tr></table></td></tr>';
    }

    public static String header() {
        return '<tr><td align="center" style="padding: 40px 20px 30px 20px;">' +
            '<span style="font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 26px; font-weight: 700; letter-spacing: 4px; color: #383737; text-transform: uppercase;">Cara</span>' +
            '</td></tr>';
    }

    public static String footer() {
        return
            // Generic support disclaimer
            '<tr><td align="center" style="padding: 20px 30px 30px 30px;">' +
            '<p style="margin: 0; font-size: 13px; line-height: 19px; color: #000000;">Please do not reply to this message. If you have any questions, please contact us via email at ' +
            '<a href="mailto:info@cara.ae" style="color: #000000; text-decoration: underline;">info@cara.ae</a>' +
            ' or call us at +971 4 347 8089</p>' +
            '</td></tr>' +

            // Teal band: wordmark/tagline + contact details
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

            // Teal band: "we're here to help" row
            '<tr><td style="background-color: #2a8ca4; padding: 0 30px 20px 30px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0"><tr>' +
            '<td valign="top" style="font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 13px; color: #ffffff;">Our team is here, Always to help</td>' +
            '<td valign="top" align="right" style="font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 13px;">' +
            '<a href="mailto:info@cara.ae" style="color: #ffffff; text-decoration: underline;">Contact Us</a>' +
            '</td>' +
            '</tr></table>' +
            '</td></tr>' +

            // Teal band: nav links (approved URLs)
            '<tr><td style="background-color: #2a8ca4; padding: 0 30px 20px 30px;">' +
            '<p style="margin: 0; font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 13px; line-height: 20px; color: #ffffff;">' +
            '<a href="' + APPOINTMENTS_URL + '" style="color: #ffffff; text-decoration: underline;">Book an appointment</a>' +
            ' &nbsp;|&nbsp; ' +
            '<a href="' + STORE_LOCATOR_URL + '" style="color: #ffffff; text-decoration: underline;">Store locations</a>' +
            ' &nbsp;|&nbsp; ' +
            '<a href="' + INSTAGRAM_URL + '" style="color: #ffffff; text-decoration: underline;">Instagram</a>' +
            ' &nbsp;|&nbsp; ' +
            '<a href="' + FACEBOOK_URL + '" style="color: #ffffff; text-decoration: underline;">Facebook</a>' +
            ' &nbsp;|&nbsp; ' +
            '<a href="' + WEBSITE_URL + '" style="color: #ffffff; text-decoration: underline;">carajewellers.com</a>' +
            '</p>' +
            '</td></tr>' +

            // Teal band divider
            '<tr><td style="background-color: #2a8ca4; padding: 0 30px;">' +
            '<table width="100%" cellpadding="0" cellspacing="0"><tr>' +
            '<td height="1" style="height: 1px; line-height: 1px; font-size: 0; background-color: #6fb3c4;">&nbsp;</td>' +
            '</tr></table>' +
            '</td></tr>' +

            // Legal / unsubscribe
            '<tr><td align="center" style="background-color: #2a8ca4; padding: 15px 30px 30px 30px;">' +
            '<p style="margin: 0; font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif; font-size: 11px; line-height: 16px; color: #d9edf1;">' +
            'You\'re receiving this email because you have an account or interacted with CARA<br/>' +
            'Unsubscribe &nbsp;|&nbsp; &copy; 2026 CARA Jewellers' +
            '</p>' +
            '</td></tr>';
    }

    /*
     * Wraps the caller's business-content table rows with the standard
     * 600px Cara email shell + header + footer.
     */
    public static String wrapEmail(String bodyRowsHtml) {
        return '<!DOCTYPE html><html><head><meta charset="UTF-8" />' +
            '<style>@import url(\'https://fonts.googleapis.com/css2?family=Playfair+Display:wght@700&display=swap\');</style>' +
            '</head><body style="margin: 0; padding: 0;">' +
            '<table width="100%" cellpadding="0" cellspacing="0" style="background-color: #ffffff;"><tr><td align="center">' +
            '<table width="600" cellpadding="0" cellspacing="0" style="width: 600px; max-width: 600px; background-color: #ffffff; font-family: \'Helvetica Neue\', Helvetica, Arial, sans-serif;">' +
            header() +
            heroImage() +
            bodyRowsHtml +
            footer() +
            '</table>' +
            '</td></tr></table>' +
            '</body></html>';
    }
}