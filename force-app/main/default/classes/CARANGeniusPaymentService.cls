public with sharing class CARANGeniusPaymentService {

    /*
     * N-Genius's actual API (endpoint, authentication, and the exact
     * void/refund request/response shape) has not been supplied. This is
     * deliberately NOT guessed — a payment-gateway integration built on an
     * assumed contract could silently misreport a void/refund as
     * successful when it wasn't, which is worse than not having the
     * integration at all.
     *
     * Wire the real callout into these two methods once the contract is
     * available. Every caller already handles NGeniusNotConfiguredException
     * safely: the Case is left at 'Awaiting Gateway', is never closed, and
     * nothing is ever reported to SFCC as a successful refund.
     */

    public class NGeniusNotConfiguredException extends Exception {
    }

    public class NGeniusResult {
        public Boolean success;
        public String gatewayReference;
        public String errorMessage;
    }

    public static NGeniusResult voidAuthorization(Order orderRecord) {
        throw new NGeniusNotConfiguredException(
            'N-Genius void/auth-reverse is not yet configured — endpoint, ' +
            'authentication, and request/response contract are required ' +
            'before this can run.'
        );
    }

    public static NGeniusResult refundPayment(Order orderRecord) {
        throw new NGeniusNotConfiguredException(
            'N-Genius refund is not yet configured — endpoint, ' +
            'authentication, and request/response contract are required ' +
            'before this can run.'
        );
    }
}