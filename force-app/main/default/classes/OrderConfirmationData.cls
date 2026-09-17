public with sharing class OrderConfirmationData {
    @AuraEnabled public String ContactPointEmail { get; set; }
    @AuraEnabled public String FirstName { get; set; }
    @AuraEnabled public String LastName { get; set; }
    @AuraEnabled public String OrderNumber { get; set; }
    @AuraEnabled public String OrderDate { get; set; }
    @AuraEnabled public String ItemName { get; set; }
    @AuraEnabled public Integer ItemQuantity { get; set; }
    @AuraEnabled public Decimal ItemPrice { get; set; }
    @AuraEnabled public String PaymentMethod { get; set; }
    @AuraEnabled public Decimal TotalAmount { get; set; }
}