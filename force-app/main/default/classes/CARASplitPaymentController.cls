/*
 * LWC-facing surface for the N-Genius split-payment actions — the
 * "Lightning Web Component button" trigger alongside the Flow-invoked
 * Handlers (CARADepositBasketHandler / CARADeleteBasketHandler /
 * CARABalanceLinkHandler). All three delegate to those same Handlers so
 * there is exactly one enqueue path per action regardless of what
 * triggered it.
 */
public with sharing class CARASplitPaymentController {

    @AuraEnabled
    public static void requestDepositBasket(Id customProductRequestId) {
        try {
            if (customProductRequestId == null) {
                throw userError('A Custom Product Request Id is required.');
            }
            CARADepositBasketHandler.createDepositBaskets(new List<Id>{ customProductRequestId });

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled('Unable to request the deposit basket.', e);
        }
    }


    @AuraEnabled
    public static void cancelDepositBasket(Id customProductRequestId, String reason) {
        try {
            if (customProductRequestId == null) {
                throw userError('A Custom Product Request Id is required.');
            }

            CARADeleteBasketHandler.CancelRequest cancelRequest = new CARADeleteBasketHandler.CancelRequest();
            cancelRequest.customProductRequestId = customProductRequestId;
            cancelRequest.reason = reason;

            CARADeleteBasketHandler.cancelDepositBaskets(new List<CARADeleteBasketHandler.CancelRequest>{ cancelRequest });

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled('Unable to cancel the deposit basket.', e);
        }
    }


    @AuraEnabled
    public static void requestBalanceLink(Id orderId) {
        try {
            if (orderId == null) {
                throw userError('An Order Id is required.');
            }
            CARABalanceLinkHandler.sendBalanceLinks(new List<Id>{ orderId });

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled('Unable to request the balance payment link.', e);
        }
    }


    @TestVisible
    private static AuraHandledException handled(String message, Exception exceptionValue) {
        String fullMessage = message +
            ' | Error Type: ' + exceptionValue.getTypeName() +
            ' | Error: ' + exceptionValue.getMessage();

        System.debug(LoggingLevel.ERROR, fullMessage);

        return userError(fullMessage);
    }


    private static AuraHandledException userError(String message) {
        AuraHandledException exceptionValue = new AuraHandledException(message);
        exceptionValue.setMessage(message);
        return exceptionValue;
    }
}