trigger CaseNumberingTrigger on Case (before insert) {
    
    // 1. Get Record Type IDs for ALL THREE types

    Id geRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('General_Enquiry_1').getRecordTypeId();
    Id compRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Compliance_1').getRecordTypeId();
    Id salesRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Sales_Follow_ups').getRecordTypeId();

    // 2. Initialize a Map to track the maximum sequence for each Record Type
    Map<Id, Decimal> maxSeqMap = new Map<Id, Decimal>();
    maxSeqMap.put(geRecordTypeId, 0);
    maxSeqMap.put(compRecordTypeId, 0);
    maxSeqMap.put(salesRecordTypeId, 0); // Added Sales Follow-up to the map

    // 3. Aggregate SOQL Query to get current maximums from the Database (Bulkified)
    for (AggregateResult ar : [SELECT RecordTypeId, MAX(Category_Sequence__c) maxVal 
                               FROM Case 
                               WHERE RecordTypeId IN :maxSeqMap.keySet() 
                               GROUP BY RecordTypeId]) {
                                   
        Id recTypeId = (Id) ar.get('RecordTypeId');
        Decimal maxSeq = (Decimal) ar.get('maxVal');
        maxSeqMap.put(recTypeId, maxSeq == null ? 0 : maxSeq);
    }

    // 4. Assign new values to the incoming records
    for (Case newCase : Trigger.new) {
        System.debug('CURRENT RECORD TYPE ID IS: ' + newCase.RecordTypeId);
		System.debug('EXPECTED GE ID IS: ' + geRecordTypeId);
        
        // Check if the case is one of our 3 specific record types
        if (maxSeqMap.containsKey(newCase.RecordTypeId)) {
            
            Decimal currentMax = maxSeqMap.get(newCase.RecordTypeId);
            Decimal nextSeq = currentMax + 1;
            
            // Assign the mathematical sequence
            newCase.Category_Sequence__c = nextSeq;
            
            // Assign the correct Prefix based on Record Type
            if (newCase.RecordTypeId == geRecordTypeId) {
                newCase.Category_Prefix__c = 'GE_';
            } else if (newCase.RecordTypeId == compRecordTypeId) {
                newCase.Category_Prefix__c = 'COMP_';
            } else if (newCase.RecordTypeId == salesRecordTypeId) {
                newCase.Category_Prefix__c = 'SALES_';
            } else {
                newCase.Category_Prefix__c = 'ERR_'; // Is se pata chalega k condition fail hui
            }
            
            // Critical Step: Update the map in memory for the next record in the loop
            maxSeqMap.put(newCase.RecordTypeId, nextSeq);
        }
    }
}