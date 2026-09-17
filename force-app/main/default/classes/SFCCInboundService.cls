@RestResource(urlMapping='/v1/sfcc/transactions/*')
global with sharing class SFCCInboundService {

    @HttpPost
    global static String handleTransaction() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            String jsonBody = req.requestBody.toString();
            System.debug('Received JSON: ' + jsonBody);
            
            // JSON parsing for wrapper structure {"data": [...]}
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
            List<Object> dataList = (List<Object>) root.get('data');
            
            List<SFCC_Transaction__c> transactionsToInsert = new List<SFCC_Transaction__c>();
            
            for (Object obj : dataList) {
                Map<String, Object> item = (Map<String, Object>) obj;
                
                SFCC_Transaction__c txn = new SFCC_Transaction__c();
                txn.Name = (String) item.get('OrderId'); // Using OrderId as Record Name
                
                // Fields Mapping
                txn.SubscriberKey__c = (String) item.get('SubscriberKey');
                txn.Email__c = (String) item.get('Email');
                txn.FirstName__c = (String) item.get('FirstName');
                txn.LastName__c = (String) item.get('LastName');
                txn.CartID__c = (String) item.get('CartID');
                txn.OrderId__c = (String) item.get('OrderId');
                txn.OrderStatus__c = (String) item.get('OrderStatus');
                
                // Safe type casting for OrderTotal (Number)
                if(item.get('OrderTotal') != null) {
                    txn.OrderTotal__c = Decimal.valueOf(String.valueOf(item.get('OrderTotal')));
                }
                
                // Handling Date Field: CreationDate__c (Strictly Date type)
                if(item.get('CreationDate') != null) {
                    String dtStr = String.valueOf(item.get('CreationDate'));
                    if(dtStr.length() >= 10) {
                        dtStr = dtStr.substring(0, 10); // Extracts 'YYYY-MM-DD'
                    }
                    txn.CreationDate__c = Date.valueOf(dtStr);
                }
                
                // Handling Date Field: OrderDate__c (Strictly Date type)
                if(item.get('OrderDate') != null) {
                    String odStr = String.valueOf(item.get('OrderDate'));
                    if(odStr.length() >= 10) {
                        odStr = odStr.substring(0, 10); // Extracts 'YYYY-MM-DD'
                    }
                    txn.OrderDate__c = Date.valueOf(odStr);
                }
                
                // Handling Date Field: ShippingDate__c (Strictly Date type)
                Object shipObj = item.get('ShippingDate') != null ? item.get('ShippingDate') : item.get('ShippingDate__c');
                if(shipObj != null) {
                    String sdStr = String.valueOf(shipObj);
                    if(sdStr.length() >= 10) {
                        sdStr = sdStr.substring(0, 10); // Extracts 'YYYY-MM-DD'
                    }
                    txn.ShippingDate__c = Date.valueOf(sdStr);
                }
                
                transactionsToInsert.add(txn);
            }
            
            if (!transactionsToInsert.isEmpty()) {
                insert transactionsToInsert;
            }
            
            res.statusCode = 200;
            return 'Success: ' + transactionsToInsert.size() + ' records saved successfully in Salesforce!';
            
        } catch (Exception e) {
            res.statusCode = 400;
            return 'Error: ' + e.getMessage() + ' at line ' + e.getLineNumber();
        }
    }
}