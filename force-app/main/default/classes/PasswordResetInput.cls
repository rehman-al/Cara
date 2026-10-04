public class PasswordResetInput {
    @AuraEnabled public String firstName { get; set; }
    @AuraEnabled public String resetLink { get; set; }
    @AuraEnabled public String expiryTime { get; set; }
}