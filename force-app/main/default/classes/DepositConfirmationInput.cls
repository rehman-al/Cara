public class DepositConfirmationInput {
    @AuraEnabled public String FirstName { get; set; }
    @AuraEnabled public String orderNumber { get; set; }
    @AuraEnabled public String paymentDate { get; set; }
    @AuraEnabled public String cardType { get; set; }
    @AuraEnabled public String last4 { get; set; }
    @AuraEnabled public String transactionId { get; set; }
    @AuraEnabled public Decimal depositAmount { get; set; }
    @AuraEnabled public Decimal remainingBalance { get; set; }

    // Yeh dono khud calculate ho jayengi — SFCC inhe set nahi karega
    @AuraEnabled public Decimal depositPercent {
        get {
            Decimal total = depositAmount + remainingBalance;
            if (total == null || total == 0) return 0;
            return (depositAmount / total * 100).setScale(0);
        }
    }

    @AuraEnabled public Decimal balancePercent {
        get {
            return 100 - depositPercent;
        }
    }
}