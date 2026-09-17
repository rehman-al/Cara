public class OrderEmailController {

    @InvocableMethod(label='Send Personalized Order Email' description='Sends order confirmation email with dynamic fields from SFCC order.')
    public static void sendOrderEmail(List<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) return;
        
        // Yahan API Name 'customer_email__c' kar diya hai
        List<Order> orderList = [
            SELECT Id, OrderNumber, CreatedDate, Account.Name, customer_email__c, TotalAmount 
            FROM Order 
            WHERE Id IN :orderIds
        ];
        
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        
        for (Order ord : orderList) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            
            // Yahan bhi wahi API Name use hoga
            String recipientEmail = ord.customer_email__c; 
            if (String.isBlank(recipientEmail)) continue;
            
            mail.setToAddresses(new String[] { recipientEmail });
            mail.setSubject('Order Confirmation - #' + ord.OrderNumber);
            mail.setSaveAsActivity(true);
            
            // Full Personalized HTML Body
            String htmlBody = '<div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">' +
                '<h2 style="color: #2b6cb0;">Thank you for your order!</h2>' +
                '<p>Hi <b>' + (ord.Account != null ? ord.Account.Name : 'Valued Customer') + '</b>,</p>' +
                '<p>We have successfully received your order from our store.</p>' +
                '<hr style="border: none; border-top: 1px solid #eee;" />' +
                '<h3>Order Details:</h3>' +
                '<ul>' +
                '<li><b>Order Number:</b> ' + ord.OrderNumber + '</li>' +
                '<li><b>Order Date:</b> ' + ord.CreatedDate.format() + '</li>' +
                '<li><b>Total Amount:</b> $' + ord.TotalAmount + '</li>' +
                '</ul>' +
                '<p>We will notify you once your items are shipped.</p>' +
                '<br/><p>Best regards,<br/><b>CARA Team</b></p>' +
                '</div>';
                
            mail.setHtmlBody(htmlBody);
            emailsToSend.add(mail);
        }
        
        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend);
        }
    }
}