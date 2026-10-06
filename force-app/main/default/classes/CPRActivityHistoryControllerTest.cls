@IsTest
private class CPRActivityHistoryControllerTest {

    @TestSetup
    static void setupData() {
        update new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);
    }


    private static Custom_Product_Request__c buildRequest(Id orderId, String basketLog) {
        Account acc = new Account(Name = 'History Test Customer');
        insert acc;
        Contact contactRecord = new Contact(
            AccountId = acc.Id, FirstName = 'Jane', LastName = 'Doe', Email = 'jane@example.com'
        );
        insert contactRecord;

        Case caseRecord = new Case(
            Subject = 'Custom ring', Origin = 'Phone', Status = 'New',
            AccountId = acc.Id, ContactId = contactRecord.Id, Related_Order__c = orderId
        );
        insert caseRecord;

        // Kept out of 'Approved' so the approval Flow does not enqueue a deposit callout.
        Custom_Product_Request__c requestRecord = new Custom_Product_Request__c(
            Case__c = caseRecord.Id,
            Product_Name__c = 'Halo Ring',
            Quantity__c = 1,
            Status__c = 'Under Review',
            Selling_Price__c = 400,
            Deposit_Amount__c = 100,
            Order_Total__c = 400,
            Deposit_Link__c = '/en-AE/pay/deposit?basketId=abc',
            Basket_Status__c = 'Created',
            Basket_Log__c = basketLog
        );
        insert requestRecord;
        return [SELECT Id, Name FROM Custom_Product_Request__c WHERE Id = :requestRecord.Id];
    }


    private static Order buildOrder(Decimal remaining, String balanceLog) {
        Account acc = new Account(Name = 'Order Account');
        insert acc;
        Order orderRecord = new Order(
            AccountId = acc.Id,
            Status = 'On Hold',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            OrderReferenceNumber = '00000187',
            Storefront_Site_ID__c = 'CARA_AE',
            Balance_Remaining__c = remaining,
            Balance_Link_Status__c = 'Sent',
            Balance_Link_Log__c = balanceLog
        );
        insert orderRecord;
        return orderRecord;
    }


    private static Integer countByTitle(List<CPRActivityHistoryController.HistoryEvent> events, String title) {
        Integer count = 0;
        for (CPRActivityHistoryController.HistoryEvent historyEvent : events) {
            if (historyEvent.title == title) {
                count++;
            }
        }
        return count;
    }


    @IsTest
    static void buildsTimelineAndPaymentSummaryFromLogsAndOrder() {
        Order orderRecord = buildOrder(
            300,
            '2026-10-05 12:38:53 — [PAYLOAD_ERROR] Cannot request balance link — missing Order Reference Number or Customer Email.\n' +
            '2026-10-05 12:51:30 — Balance link retrieved. remaining=300, alreadyPaid=false\n' +
            '2026-10-05 12:51:30 — Balance link notification: Sent to jane@example.com'
        );
        Custom_Product_Request__c requestRecord = buildRequest(
            orderRecord.Id,
            '2026-10-05 12:32:37 — Deposit basket created. basketId=abc\n' +
            '2026-10-05 12:32:37 — Deposit link notification: Sent to jane@example.com'
        );

        Test.startTest();
        CPRActivityHistoryController.HistoryResult result = CPRActivityHistoryController.getHistory(requestRecord.Id);
        Test.stopTest();

        Assert.areEqual(requestRecord.Name, result.requestName);
        Assert.areEqual(1, countByTitle(result.events, 'Request created'));
        Assert.areEqual(1, countByTitle(result.events, 'Deposit payment link created'));
        Assert.areEqual(1, countByTitle(result.events, 'Deposit link email sent'));
        Assert.areEqual(1, countByTitle(result.events, 'Deposit paid'));
        Assert.areEqual(1, countByTitle(result.events, 'Balance link failed'));
        Assert.areEqual(1, countByTitle(result.events, 'Balance payment link created'));
        Assert.areEqual(1, countByTitle(result.events, 'Balance link email sent'));

        CPRActivityHistoryController.Summary summary = result.summary;
        Assert.areEqual(1, summary.depositEmailsSent);
        Assert.areEqual(1, summary.balanceEmailsSent);
        Assert.isTrue(summary.depositPaid, 'A linked Order means the deposit was paid.');
        Assert.isFalse(summary.balancePaid);
        Assert.areEqual(300, summary.amountRemaining);
        Assert.areEqual(100, summary.amountPaid);
        Assert.areEqual('Waiting for the customer to pay the balance.', summary.nextStep);

        // Newest first.
        for (Integer i = 1; i < result.events.size(); i++) {
            Assert.isTrue(result.events[i - 1].occurredAt >= result.events[i].occurredAt, 'Events must be newest first.');
        }
    }


    @IsTest
    static void prefersEmailMessageRecordsOverLogLinesForDepositSends() {
        Custom_Product_Request__c requestRecord = buildRequest(
            null,
            '2026-10-05 12:32:37 — Deposit basket created. basketId=abc\n' +
            '2026-10-05 12:32:37 — Deposit link notification: Sent to jane@example.com\n' +
            '2026-10-05 13:00:00 — Deposit link notification: Skipped - No Email'
        );
        insert new List<EmailMessage>{
            new EmailMessage(
                Subject = CPRActivityHistoryController.DEPOSIT_EMAIL_SUBJECT_PREFIX + requestRecord.Name,
                ToAddress = 'jane@example.com', Status = '3', MessageDate = Datetime.now().addHours(-2)
            ),
            new EmailMessage(
                Subject = CPRActivityHistoryController.DEPOSIT_EMAIL_SUBJECT_PREFIX + requestRecord.Name,
                ToAddress = 'jane@example.com', Status = '3', MessageDate = Datetime.now().addHours(-1)
            )
        };

        CPRActivityHistoryController.HistoryResult result = CPRActivityHistoryController.getHistory(requestRecord.Id);

        Assert.areEqual(1, countByTitle(result.events, 'Deposit link email sent'));
        Assert.areEqual(1, countByTitle(result.events, 'Deposit link email re-sent'));
        Assert.areEqual(1, countByTitle(result.events, 'Deposit link email not sent'));
        Assert.areEqual(2, result.summary.depositEmailsSent);
        Assert.isFalse(result.summary.depositPaid);
        Assert.areEqual(0, result.summary.amountPaid);
        Assert.areEqual(400, result.summary.amountRemaining);
    }


    @IsTest
    static void recognisesBalancePaymentAndFullyPaidOrder() {
        Order orderRecord = buildOrder(
            0,
            '2026-10-05 12:51:30 — Balance link retrieved. remaining=300, alreadyPaid=false\n' +
            '2026-10-06 09:00:00 — Balance payment confirmed by SFCC. reference=PAY-1, amount=300 AED'
        );
        orderRecord.Balance_Already_Paid__c = true;
        orderRecord.Balance_Link_Status__c = 'Paid';
        update orderRecord;
        Custom_Product_Request__c requestRecord = buildRequest(orderRecord.Id, null);

        CPRActivityHistoryController.HistoryResult result = CPRActivityHistoryController.getHistory(requestRecord.Id);

        Assert.areEqual(1, countByTitle(result.events, 'Balance paid'));
        Assert.isTrue(result.summary.balancePaid);
        Assert.areEqual(0, result.summary.amountRemaining);
        Assert.areEqual('Fully paid — nothing left to collect.', result.summary.nextStep);
    }


    @IsTest
    static void fieldHistoryRowsAreMappedAndNoiseIsDropped() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Custom_Product_Request__c.fields.getMap();
        Datetime changedAt = Datetime.now();

        CPRActivityHistoryController.HistoryEvent statusEvent = CPRActivityHistoryController.toFieldEvent(
            'Status__c', 'Draft', 'Approved', changedAt, 'Agent', fieldMap
        );
        Assert.areEqual('Status changed to Approved', statusEvent.title);
        Assert.areEqual('Agent', statusEvent.actor);

        CPRActivityHistoryController.HistoryEvent priceEvent = CPRActivityHistoryController.toFieldEvent(
            'Selling_Price__c', null, 100, changedAt, 'Agent', fieldMap
        );
        Assert.areEqual(CPRActivityHistoryController.CATEGORY_UPDATE, priceEvent.category);

        Assert.isNull(CPRActivityHistoryController.toFieldEvent('created', null, null, changedAt, 'Agent', fieldMap));
        Assert.isNull(CPRActivityHistoryController.toFieldEvent('Basket_Id__c', null, 'abc', changedAt, 'Agent', fieldMap));
        Assert.isNull(CPRActivityHistoryController.toFieldEvent(
            'Product__c', null, '01tFV009EOk8bR2YYI', changedAt, 'Agent', fieldMap
        ));
    }


    @IsTest
    static void nextStepCoversEachStage() {
        CPRActivityHistoryController.Summary summary = new CPRActivityHistoryController.Summary();
        summary.status = 'Draft';
        Assert.isTrue(CPRActivityHistoryController.nextStep(summary).startsWith('Finalise'));

        summary.status = 'Failed';
        Assert.isTrue(CPRActivityHistoryController.nextStep(summary).startsWith('Deposit link failed'));

        summary.status = 'Rejected';
        Assert.isTrue(CPRActivityHistoryController.nextStep(summary).startsWith('Request was rejected'));

        summary.status = 'Approved';
        summary.isApproved = true;
        Assert.isTrue(CPRActivityHistoryController.nextStep(summary).startsWith('Deposit link is being generated'));

        summary.depositLinkCreated = true;
        Assert.isTrue(CPRActivityHistoryController.nextStep(summary).contains('no email'));

        summary.depositEmailsSent = 1;
        Assert.isTrue(CPRActivityHistoryController.nextStep(summary).contains('pay the deposit'));

        summary.depositPaid = true;
        Assert.isTrue(CPRActivityHistoryController.nextStep(summary).contains('send the balance link'));
    }


    @IsTest
    static void parsesMultiLineLogEntries() {
        List<CPRActivityHistoryController.LogLine> lines = CPRActivityHistoryController.parseLog(
            '2026-10-05 12:00:00 — first line\ncontinued here\n\n2026-10-05 12:05:00 — second'
        );
        Assert.areEqual(2, lines.size());
        Assert.areEqual('first line continued here', lines[0].message);
    }


    @IsTest
    static void rejectsMissingId() {
        try {
            CPRActivityHistoryController.getHistory(null);
            Assert.fail('Expected an error for a missing Id.');
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains('required'));
        }
    }
}