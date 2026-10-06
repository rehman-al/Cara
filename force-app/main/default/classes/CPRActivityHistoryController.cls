/*
 * One read-only view, for CSRs, of everything that has happened to a
 * Custom Product Request: which payment-link emails went out (and for how
 * much), what has been paid, what is still outstanding, and every status
 * change / callout outcome in between.
 *
 * Nothing new is persisted — it stitches together the audit trails that
 * already exist:
 *   - Custom_Product_Request__History (field history: who changed what)
 *   - Custom_Product_Request__c.Basket_Log__c (deposit basket callouts +
 *     notification outcomes, see CARADepositBasketQueueable)
 *   - EmailMessage (deposit emails are sent with saveAsActivity, subject
 *     'Complete Your Deposit - <CPR Number>')
 *   - the Case's Related_Order__c Order: its creation (= deposit paid in
 *     SFCC) and Balance_Link_Log__c (balance link + balance payment, see
 *     CARABalanceLinkQueueable / CARABalancePaymentService)
 */
public with sharing class CPRActivityHistoryController {

    public static final String CATEGORY_EMAIL = 'Email';
    public static final String CATEGORY_PAYMENT = 'Payment';
    public static final String CATEGORY_STATUS = 'Status';
    public static final String CATEGORY_UPDATE = 'Update';
    public static final String CATEGORY_SYSTEM = 'System';
    public static final String CATEGORY_ERROR = 'Error';

    @TestVisible
    private static final String DEPOSIT_EMAIL_SUBJECT_PREFIX = 'Complete Your Deposit - ';

    /*
     * Written by the split-payment Queueables alongside the callout result —
     * already represented by the 'Deposit basket created' log line, so
     * listing them again as separate field edits would only add noise.
     */
    private static final Set<String> SYSTEM_MANAGED_FIELDS = new Set<String>{
        'basket_id__c',
        'basket_status__c',
        'deposit_link__c',
        'deposit_amount__c',
        'order_total__c'
    };

    private static final Pattern LOG_LINE_PATTERN =
        Pattern.compile('^(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\s*[—-]\\s*(.*)$');
    private static final Pattern REMAINING_PATTERN = Pattern.compile('remaining=([0-9.]+)');
    private static final Pattern AMOUNT_PATTERN = Pattern.compile('amount=([0-9.]+)');

    private static Integer nextSequence = 0;

    private static final Map<String, Integer> TIE_BREAK_RANK = new Map<String, Integer>{
        CATEGORY_STATUS => 1,
        CATEGORY_UPDATE => 1,
        CATEGORY_SYSTEM => 2,
        CATEGORY_ERROR => 3,
        CATEGORY_EMAIL => 3,
        CATEGORY_PAYMENT => 4
    };


    @AuraEnabled
    public static HistoryResult getHistory(Id requestId) {
        try {
            if (requestId == null) {
                throw userError('A Custom Product Request Id is required.');
            }

            List<Custom_Product_Request__c> requests = [
                SELECT
                    Id, Name, Status__c, Basket_Status__c, Basket_Log__c,
                    Selling_Price__c, Deposit_Amount__c, Order_Total__c, Deposit_Link__c,
                    CreatedDate, CreatedBy.Name,
                    Case__c, Case__r.CaseNumber, Case__r.Related_Order__c,
                    Case__r.ContactId, Case__r.Contact.Email
                FROM Custom_Product_Request__c
                WHERE Id = :requestId
                LIMIT 1
            ];

            if (requests.isEmpty()) {
                throw userError('The custom product request was not found.');
            }

            Custom_Product_Request__c requestRecord = requests[0];
            Order relatedOrder = queryRelatedOrder(requestRecord);

            HistoryResult result = new HistoryResult();
            result.requestName = requestRecord.Name;
            result.currencyCode = relatedOrder != null && String.isNotBlank(relatedOrder.CurrencyIsoCode__c)
                ? relatedOrder.CurrencyIsoCode__c
                : UserInfo.getDefaultCurrency();

            List<EmailMessage> depositEmails = queryDepositEmails(requestRecord);

            List<HistoryEvent> events = new List<HistoryEvent>();
            events.add(createdEvent(requestRecord));
            events.addAll(fieldHistoryEvents(requestRecord.Id));
            events.addAll(depositEmailEvents(requestRecord, depositEmails));
            events.addAll(basketLogEvents(requestRecord, !depositEmails.isEmpty()));
            if (relatedOrder != null) {
                events.addAll(orderEvents(requestRecord, relatedOrder));
            }

            events.sort();
            result.events = events;
            result.summary = buildSummary(requestRecord, relatedOrder, events);
            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            String message = 'Unable to load the request history. | Error Type: ' + e.getTypeName() +
                ' | Error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, message);
            throw userError(message);
        }
    }


    private static Order queryRelatedOrder(Custom_Product_Request__c requestRecord) {
        Id orderId = requestRecord.Case__r != null ? requestRecord.Case__r.Related_Order__c : null;
        if (orderId == null) {
            return null;
        }

        List<Order> orders = [
            SELECT
                Id, OrderNumber, OrderReferenceNumber, CreatedDate, TotalAmount, CurrencyIsoCode__c,
                Payment_Status__c, Balance_Link_Status__c, Balance_Remaining__c,
                Balance_Already_Paid__c, Balance_Payment_Reference__c, Balance_Link_Log__c,
                Customer_Email__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
        return orders.isEmpty() ? null : orders[0];
    }


    private static List<EmailMessage> queryDepositEmails(Custom_Product_Request__c requestRecord) {
        String subject = DEPOSIT_EMAIL_SUBJECT_PREFIX + requestRecord.Name;
        return [
            SELECT Id, Subject, ToAddress, MessageDate, CreatedDate, CreatedBy.Name
            FROM EmailMessage
            WHERE Subject = :subject
            ORDER BY CreatedDate ASC
            LIMIT 200
        ];
    }


    private static HistoryEvent createdEvent(Custom_Product_Request__c requestRecord) {
        HistoryEvent created = new HistoryEvent(
            requestRecord.CreatedDate,
            CATEGORY_STATUS,
            'Request created',
            requestRecord.Case__r != null ? 'Case ' + requestRecord.Case__r.CaseNumber : null
        );
        created.actor = requestRecord.CreatedBy != null ? requestRecord.CreatedBy.Name : null;
        return created;
    }


    private static List<HistoryEvent> fieldHistoryEvents(Id requestId) {
        List<HistoryEvent> events = new List<HistoryEvent>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Custom_Product_Request__c.fields.getMap();

        for (Custom_Product_Request__History historyRow : [
            SELECT Field, OldValue, NewValue, CreatedDate, CreatedBy.Name
            FROM Custom_Product_Request__History
            WHERE ParentId = :requestId
            ORDER BY CreatedDate ASC
            LIMIT 500
        ]) {
            HistoryEvent historyEvent = toFieldEvent(
                historyRow.Field,
                historyRow.OldValue,
                historyRow.NewValue,
                historyRow.CreatedDate,
                historyRow.CreatedBy != null ? historyRow.CreatedBy.Name : null,
                fieldMap
            );
            if (historyEvent != null) {
                events.add(historyEvent);
            }
        }
        return events;
    }


    @TestVisible
    private static HistoryEvent toFieldEvent(
        String fieldName,
        Object oldValue,
        Object newValue,
        Datetime changedAt,
        String actor,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        if (String.isBlank(fieldName) || fieldName == 'created') {
            return null; // the 'Request created' event already covers this
        }
        if (SYSTEM_MANAGED_FIELDS.contains(fieldName.toLowerCase())) {
            return null;
        }
        // Lookup history writes two rows (record name + raw Id); keep the readable one.
        if (isRecordId(oldValue) || isRecordId(newValue)) {
            return null;
        }

        Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());
        String label = field != null ? field.getDescribe().getLabel() : fieldName;
        String fromText = oldValue == null ? '—' : String.valueOf(oldValue);
        String toText = newValue == null ? '—' : String.valueOf(newValue);

        HistoryEvent historyEvent;
        if (fieldName == 'Status__c') {
            historyEvent = new HistoryEvent(changedAt, CATEGORY_STATUS, 'Status changed to ' + toText, 'From ' + fromText);
        } else {
            historyEvent = new HistoryEvent(changedAt, CATEGORY_UPDATE, label + ' updated', fromText + ' → ' + toText);
        }
        historyEvent.actor = actor;
        return historyEvent;
    }


    private static List<HistoryEvent> depositEmailEvents(
        Custom_Product_Request__c requestRecord,
        List<EmailMessage> depositEmails
    ) {
        List<HistoryEvent> events = new List<HistoryEvent>();
        Integer sendNumber = 0;
        for (EmailMessage emailRecord : depositEmails) {
            sendNumber++;
            HistoryEvent emailEvent = new HistoryEvent(
                emailRecord.MessageDate != null ? emailRecord.MessageDate : emailRecord.CreatedDate,
                CATEGORY_EMAIL,
                sendNumber == 1 ? 'Deposit link email sent' : 'Deposit link email re-sent',
                'To ' + emailRecord.ToAddress
            );
            emailEvent.amount = requestRecord.Deposit_Amount__c;
            emailEvent.amountLabel = 'Deposit requested';
            emailEvent.link = requestRecord.Deposit_Link__c;
            emailEvent.recordId = emailRecord.Id;
            emailEvent.actor = emailRecord.CreatedBy != null ? emailRecord.CreatedBy.Name : null;
            events.add(emailEvent);
        }
        return events;
    }


    /*
     * Basket_Log__c lines look like 'yyyy-MM-dd HH:mm:ss — message', stamped
     * in the running user's time zone. When the deposit EmailMessage records
     * are available they are the richer source for the sends, so the log's
     * own 'Sent to …' notification lines are dropped to avoid listing each
     * email twice; skipped/failed sends are always kept.
     */
    @TestVisible
    private static List<HistoryEvent> basketLogEvents(Custom_Product_Request__c requestRecord, Boolean hasEmailRecords) {
        List<HistoryEvent> events = new List<HistoryEvent>();
        for (LogLine line : parseLog(requestRecord.Basket_Log__c)) {
            String message = line.message;

            if (message.startsWith('Deposit basket created')) {
                HistoryEvent created = new HistoryEvent(
                    line.stampedAt, CATEGORY_SYSTEM, 'Deposit payment link created', message
                );
                created.amount = requestRecord.Deposit_Amount__c;
                created.amountLabel = 'Deposit';
                events.add(created);

            } else if (message.startsWith('Deposit link notification:')) {
                String outcome = message.removeStart('Deposit link notification:').trim();
                if (outcome.startsWith('Sent')) {
                    if (hasEmailRecords) {
                        continue;
                    }
                    HistoryEvent emailEvent = new HistoryEvent(
                        line.stampedAt, CATEGORY_EMAIL, 'Deposit link email sent', outcome
                    );
                    emailEvent.amount = requestRecord.Deposit_Amount__c;
                    emailEvent.amountLabel = 'Deposit requested';
                    emailEvent.link = requestRecord.Deposit_Link__c;
                    events.add(emailEvent);
                } else {
                    events.add(new HistoryEvent(
                        line.stampedAt, CATEGORY_ERROR, 'Deposit link email not sent', outcome
                    ));
                }

            } else if (message.startsWith('[')) {
                events.add(new HistoryEvent(line.stampedAt, CATEGORY_ERROR, 'Deposit link failed', message));

            } else if (message.containsIgnoreCase('cancel') || message.containsIgnoreCase('delete')) {
                events.add(new HistoryEvent(line.stampedAt, CATEGORY_SYSTEM, 'Deposit basket cancelled', message));

            } else {
                events.add(new HistoryEvent(line.stampedAt, CATEGORY_SYSTEM, 'Deposit basket update', message));
            }
        }
        return events;
    }


    @TestVisible
    private static List<HistoryEvent> orderEvents(Custom_Product_Request__c requestRecord, Order orderRecord) {
        List<HistoryEvent> events = new List<HistoryEvent>();
        String orderLabel = String.isNotBlank(orderRecord.OrderReferenceNumber)
            ? orderRecord.OrderReferenceNumber
            : orderRecord.OrderNumber;

        // SFCC only places the order once the deposit has been paid.
        HistoryEvent depositPaid = new HistoryEvent(
            orderRecord.CreatedDate,
            CATEGORY_PAYMENT,
            'Deposit paid',
            'Order ' + orderLabel + ' created'
        );
        depositPaid.amount = requestRecord.Deposit_Amount__c;
        depositPaid.amountLabel = 'Paid';
        depositPaid.recordId = orderRecord.Id;
        events.add(depositPaid);

        Decimal lastRemaining = orderRecord.Balance_Remaining__c;
        for (LogLine line : parseLog(orderRecord.Balance_Link_Log__c)) {
            String message = line.message;

            if (message.startsWith('Balance link retrieved')) {
                Matcher remainingMatcher = REMAINING_PATTERN.matcher(message);
                if (remainingMatcher.find()) {
                    lastRemaining = Decimal.valueOf(remainingMatcher.group(1));
                }
                HistoryEvent linkEvent = new HistoryEvent(
                    line.stampedAt, CATEGORY_SYSTEM, 'Balance payment link created', message
                );
                linkEvent.amount = lastRemaining;
                linkEvent.amountLabel = 'Balance';
                events.add(linkEvent);

            } else if (message.startsWith('Balance link notification:')) {
                String outcome = message.removeStart('Balance link notification:').trim();
                if (outcome.startsWith('Sent')) {
                    HistoryEvent emailEvent = new HistoryEvent(
                        line.stampedAt, CATEGORY_EMAIL, 'Balance link email sent', outcome
                    );
                    emailEvent.amount = lastRemaining;
                    emailEvent.amountLabel = 'Balance requested';
                    events.add(emailEvent);
                } else {
                    events.add(new HistoryEvent(
                        line.stampedAt, CATEGORY_ERROR, 'Balance link email not sent', outcome
                    ));
                }

            } else if (message.startsWith('[')) {
                events.add(new HistoryEvent(line.stampedAt, CATEGORY_ERROR, 'Balance link failed', message));

            } else if (message.startsWith('Balance payment confirmed')) {
                HistoryEvent paidEvent = new HistoryEvent(
                    line.stampedAt, CATEGORY_PAYMENT, 'Balance paid', message
                );
                Matcher amountMatcher = AMOUNT_PATTERN.matcher(message);
                paidEvent.amount = amountMatcher.find() ? Decimal.valueOf(amountMatcher.group(1)) : lastRemaining;
                paidEvent.amountLabel = 'Paid';
                events.add(paidEvent);

            } else if (message.startsWith('Balance payment confirmation received with non-success')) {
                events.add(new HistoryEvent(line.stampedAt, CATEGORY_ERROR, 'Balance payment not successful', message));

            } else {
                events.add(new HistoryEvent(line.stampedAt, CATEGORY_SYSTEM, 'Balance link update', message));
            }
        }
        return events;
    }


    private static Summary buildSummary(
        Custom_Product_Request__c requestRecord,
        Order orderRecord,
        List<HistoryEvent> events
    ) {
        Summary summary = new Summary();
        summary.status = requestRecord.Status__c;
        summary.basketStatus = requestRecord.Basket_Status__c;
        summary.sellingPrice = requestRecord.Selling_Price__c;
        summary.depositAmount = requestRecord.Deposit_Amount__c;
        summary.orderTotal = requestRecord.Order_Total__c != null
            ? requestRecord.Order_Total__c
            : requestRecord.Selling_Price__c;
        summary.depositLink = requestRecord.Deposit_Link__c;

        for (HistoryEvent historyEvent : events) {
            if (historyEvent.category != CATEGORY_EMAIL) {
                continue;
            }
            if (historyEvent.title.startsWith('Deposit')) {
                summary.depositEmailsSent++;
                summary.lastDepositEmailAt = historyEvent.occurredAt;
            } else if (historyEvent.title.startsWith('Balance')) {
                summary.balanceEmailsSent++;
                summary.lastBalanceEmailAt = historyEvent.occurredAt;
            }
        }

        summary.isApproved = requestRecord.Status__c == 'Approved';
        summary.depositLinkCreated = String.isNotBlank(requestRecord.Deposit_Link__c)
            || requestRecord.Basket_Status__c == 'Created';
        summary.depositPaid = orderRecord != null;

        if (orderRecord != null) {
            summary.orderId = orderRecord.Id;
            summary.orderNumber = String.isNotBlank(orderRecord.OrderReferenceNumber)
                ? orderRecord.OrderReferenceNumber
                : orderRecord.OrderNumber;
            if (orderRecord.TotalAmount != null && orderRecord.TotalAmount > 0) {
                summary.orderTotal = orderRecord.TotalAmount;
            }
            summary.balanceLinkStatus = orderRecord.Balance_Link_Status__c;
            summary.balancePaid = orderRecord.Balance_Already_Paid__c == true
                || orderRecord.Balance_Link_Status__c == 'Paid';
            summary.balanceLinkSent = summary.balanceEmailsSent > 0
                || orderRecord.Balance_Link_Status__c == 'Sent';
        }

        Decimal total = summary.orderTotal != null ? summary.orderTotal : 0;
        if (summary.balancePaid) {
            summary.amountPaid = total;
            summary.amountRemaining = 0;
        } else if (orderRecord != null && orderRecord.Balance_Remaining__c != null) {
            summary.amountRemaining = orderRecord.Balance_Remaining__c;
            summary.amountPaid = (total - orderRecord.Balance_Remaining__c);
        } else if (summary.depositPaid) {
            Decimal deposit = summary.depositAmount != null ? summary.depositAmount : 0;
            summary.amountPaid = deposit;
            summary.amountRemaining = total - deposit;
        } else {
            summary.amountPaid = 0;
            summary.amountRemaining = total;
        }
        summary.balanceAmount = summary.balancePaid
            ? (total - (summary.depositAmount != null ? summary.depositAmount : 0))
            : summary.amountRemaining;

        summary.nextStep = nextStep(summary);
        return summary;
    }


    @TestVisible
    private static String nextStep(Summary summary) {
        if (summary.balancePaid) {
            return 'Fully paid — nothing left to collect.';
        }
        // Once the deposit is in, only the balance matters — status/basket fields are history.
        if (summary.depositPaid) {
            return summary.balanceLinkSent
                ? 'Waiting for the customer to pay the balance.'
                : 'Deposit received — send the balance link when the piece is ready.';
        }
        if (summary.status == 'Rejected') {
            return 'Request was rejected — no payment will be collected.';
        }
        if (summary.status == 'Failed' || summary.basketStatus == 'Error') {
            return 'Deposit link failed — fix the issue shown in the history, then re-approve the request.';
        }
        if (!summary.isApproved) {
            return 'Finalise the product and approve the request to send the deposit link.';
        }
        if (!summary.depositLinkCreated) {
            return 'Deposit link is being generated.';
        }
        return summary.depositEmailsSent > 0
            ? 'Waiting for the customer to pay the deposit.'
            : 'Deposit link created but no email has been sent yet.';
    }


    @TestVisible
    private static List<LogLine> parseLog(String rawLog) {
        List<LogLine> lines = new List<LogLine>();
        if (String.isBlank(rawLog)) {
            return lines;
        }
        for (String rawLine : rawLog.split('\n')) {
            String trimmed = rawLine.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            Matcher lineMatcher = LOG_LINE_PATTERN.matcher(trimmed);
            if (lineMatcher.matches()) {
                lines.add(new LogLine(Datetime.valueOf(lineMatcher.group(1)), lineMatcher.group(2).trim()));
            } else if (!lines.isEmpty()) {
                // Continuation of a multi-line message.
                LogLine previous = lines[lines.size() - 1];
                previous.message += ' ' + trimmed;
            }
        }
        return lines;
    }


    private static Boolean isRecordId(Object value) {
        if (!(value instanceof String)) {
            return false;
        }
        String text = (String) value;
        if ((text.length() != 15 && text.length() != 18) || !text.isAlphanumeric() || !text.containsAny('0123456789')) {
            return false;
        }
        try {
            Id.valueOf(text);
            return true;
        } catch (Exception notAnId) {
            return false;
        }
    }


    private static AuraHandledException userError(String message) {
        AuraHandledException exceptionValue = new AuraHandledException(message);
        exceptionValue.setMessage(message);
        return exceptionValue;
    }


    @TestVisible
    private class LogLine {
        public Datetime stampedAt;
        public String message;

        LogLine(Datetime stampedAt, String message) {
            this.stampedAt = stampedAt;
            this.message = message;
        }
    }


    public class HistoryResult {
        @AuraEnabled public String requestName;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Summary summary;
        @AuraEnabled public List<HistoryEvent> events;
    }


    public class Summary {
        @AuraEnabled public String status;
        @AuraEnabled public String basketStatus;
        @AuraEnabled public String nextStep;
        @AuraEnabled public Decimal sellingPrice;
        @AuraEnabled public Decimal orderTotal;
        @AuraEnabled public Decimal depositAmount;
        @AuraEnabled public Decimal balanceAmount;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public Decimal amountRemaining;
        @AuraEnabled public String depositLink;
        @AuraEnabled public Integer depositEmailsSent = 0;
        @AuraEnabled public Integer balanceEmailsSent = 0;
        @AuraEnabled public Datetime lastDepositEmailAt;
        @AuraEnabled public Datetime lastBalanceEmailAt;
        @AuraEnabled public Boolean isApproved = false;
        @AuraEnabled public Boolean depositLinkCreated = false;
        @AuraEnabled public Boolean depositPaid = false;
        @AuraEnabled public Boolean balanceLinkSent = false;
        @AuraEnabled public Boolean balancePaid = false;
        @AuraEnabled public String balanceLinkStatus;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
    }


    public class HistoryEvent implements Comparable {
        @AuraEnabled public String key;
        @AuraEnabled public Datetime occurredAt;
        @AuraEnabled public String category;
        @AuraEnabled public String title;
        @AuraEnabled public String detail;
        @AuraEnabled public String actor;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String amountLabel;
        @AuraEnabled public String link;
        @AuraEnabled public Id recordId;
        private Integer sequence;

        public HistoryEvent(Datetime occurredAt, String category, String title, String detail) {
            this.occurredAt = occurredAt;
            this.category = category;
            this.title = title;
            this.detail = detail;
            this.sequence = nextSequence++;
            this.key = 'event-' + this.sequence;
        }

        // Newest first.
        public Integer compareTo(Object other) {
            HistoryEvent otherEvent = (HistoryEvent) other;
            Long mine = occurredAt != null ? occurredAt.getTime() : 0;
            Long theirs = otherEvent.occurredAt != null ? otherEvent.occurredAt.getTime() : 0;
            if (mine == theirs) {
                // Same second (e.g. link created, then emailed): show the step that follows on top.
                Integer myRank = TIE_BREAK_RANK.get(category);
                Integer theirRank = TIE_BREAK_RANK.get(otherEvent.category);
                if (myRank != theirRank) {
                    return myRank > theirRank ? -1 : 1;
                }
                return sequence > otherEvent.sequence ? -1 : (sequence < otherEvent.sequence ? 1 : 0);
            }
            return mine > theirs ? -1 : 1;
        }
    }
}