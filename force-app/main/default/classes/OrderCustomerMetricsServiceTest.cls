@IsTest
private class OrderCustomerMetricsServiceTest {
    @TestSetup
    static void seedPricebook() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        Product2 product = new Product2(Name = 'Test Product', IsActive = true);
        insert product;

        insert new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
    }

    // ---------- helpers ----------

    private static Id pricebookEntryId() {
        return [SELECT Id FROM PricebookEntry LIMIT 1].Id;
    }

    private static Account newAccount(String name) {
        Account account = new Account(Name = name);
        insert account;
        return account;
    }

    /** Inserts a Draft order plus one line item; does NOT activate it. */
    private static Order newDraftOrder(Id accountId, Date effectiveDate, Decimal quantity, Decimal unitPrice) {
        Order order = new Order(
            AccountId = accountId,
            Status = 'Draft',
            EffectiveDate = effectiveDate,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert order;

        insert new OrderItem(
            OrderId = order.Id,
            PricebookEntryId = pricebookEntryId(),
            Quantity = quantity,
            UnitPrice = unitPrice
        );
        return order;
    }

    /** Inserts a Draft order with a line item, then activates it. */
    private static Order newActivatedOrder(Id accountId, Date effectiveDate, Decimal quantity, Decimal unitPrice) {
        Order order = newDraftOrder(accountId, effectiveDate, quantity, unitPrice);
        order.Status = 'Activated';
        update order;
        return order;
    }

    /**
     * Deactivates an order. The org does not grant the "Delete Activated
     * Orders" permission, so tests that delete or reparent an order must
     * deactivate it first, same as a real user would have to.
     */
    private static void deactivate(Order order) {
        order.Status = 'Draft';
        update order;
    }

    private static Account reloadAccount(Id accountId) {
        return [
            SELECT Customer_Lifetime_Spend__c, Number_of_Orders__c, Average_Order_Value__c,
                   First_Order_Date__c, Last_Order_Date__c, Customer_Tier__c, Loyalty_Tier_Benefits__c
            FROM Account
            WHERE Id = :accountId
        ];
    }

    // ---------- tests ----------

    @IsTest
    static void singleActivatedOrderPopulatesEveryMetric() {
        Account account = newAccount('Single Order Co');

        Test.startTest();
        newActivatedOrder(account.Id, Date.newInstance(2026, 1, 15), 2, 100);
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual(200, result.Customer_Lifetime_Spend__c);
        Assert.areEqual(1, result.Number_of_Orders__c);
        Assert.areEqual(200, result.Average_Order_Value__c);
        Assert.areEqual(Date.newInstance(2026, 1, 15), result.First_Order_Date__c);
        Assert.areEqual(Date.newInstance(2026, 1, 15), result.Last_Order_Date__c);
        Assert.areEqual('Bronze', result.Customer_Tier__c);
        Assert.isNull(result.Loyalty_Tier_Benefits__c);
    }

    @IsTest
    static void spendJustBelowSilverStaysBronzeWithNoBenefits() {
        Account account = newAccount('Almost Silver Co');

        Test.startTest();
        newActivatedOrder(account.Id, Date.newInstance(2026, 1, 1), 1, 9999.99);
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual('Bronze', result.Customer_Tier__c);
        Assert.isNull(result.Loyalty_Tier_Benefits__c);
    }

    @IsTest
    static void spendAtSilverThresholdUnlocksSilverBenefits() {
        Account account = newAccount('Silver Co');

        Test.startTest();
        newActivatedOrder(account.Id, Date.newInstance(2026, 1, 1), 1, 10000);
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual('Silver', result.Customer_Tier__c);
        Assert.areEqual(
            'Complimentary delivery; Early access to selected launches; Exclusive member offers',
            result.Loyalty_Tier_Benefits__c
        );
    }

    @IsTest
    static void spendAtGoldThresholdUnlocksGoldBenefits() {
        Account account = newAccount('Gold Co');

        Test.startTest();
        newActivatedOrder(account.Id, Date.newInstance(2026, 1, 1), 1, 50000);
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual('Gold', result.Customer_Tier__c);
        Assert.areEqual(
            'Complimentary delivery; Priority access to new collections; Exclusive member offers; Priority client service',
            result.Loyalty_Tier_Benefits__c
        );
    }

    @IsTest
    static void spendAtPlatinumThresholdUnlocksPlatinumBenefits() {
        Account account = newAccount('Platinum Co');

        Test.startTest();
        newActivatedOrder(account.Id, Date.newInstance(2026, 1, 1), 1, 100000);
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual('Platinum', result.Customer_Tier__c);
        Assert.areEqual(
            'Complimentary delivery; First access to new collections; Exclusive Platinum member offers; '
                + 'Priority client service; Private shopping experiences',
            result.Loyalty_Tier_Benefits__c
        );
    }

    @IsTest
    static void losingTheLastQualifyingOrderResetsTierToBronze() {
        Account account = newAccount('Downgrade Co');
        Order order = newActivatedOrder(account.Id, Date.newInstance(2026, 1, 1), 1, 100000);
        Assert.areEqual('Platinum', reloadAccount(account.Id).Customer_Tier__c);

        Test.startTest();
        order.Status = 'Draft'; // deactivate, no longer a qualifying order
        update order;
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual('Bronze', result.Customer_Tier__c);
        Assert.isNull(result.Loyalty_Tier_Benefits__c);
    }

    @IsTest
    static void multipleActivatedOrdersAreAggregated() {
        Account account = newAccount('Repeat Buyer Co');

        Test.startTest();
        newActivatedOrder(account.Id, Date.newInstance(2026, 1, 10), 2, 100); // 200
        newActivatedOrder(account.Id, Date.newInstance(2026, 3, 5), 1, 100); // 100
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual(300, result.Customer_Lifetime_Spend__c);
        Assert.areEqual(2, result.Number_of_Orders__c);
        Assert.areEqual(150, result.Average_Order_Value__c);
        Assert.areEqual(Date.newInstance(2026, 1, 10), result.First_Order_Date__c);
        Assert.areEqual(Date.newInstance(2026, 3, 5), result.Last_Order_Date__c);
    }

    @IsTest
    static void draftOrdersAreExcluded() {
        Account account = newAccount('Draft Only Co');

        Test.startTest();
        newDraftOrder(account.Id, Date.newInstance(2026, 2, 1), 5, 100); // never activated
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual(0, result.Customer_Lifetime_Spend__c);
        Assert.areEqual(0, result.Number_of_Orders__c);
        Assert.areEqual(0, result.Average_Order_Value__c);
        Assert.isNull(result.First_Order_Date__c);
        Assert.isNull(result.Last_Order_Date__c);
    }

    @IsTest
    static void deletingTheLastQualifyingOrderClearsMetrics() {
        Account account = newAccount('Cancels Everything Co');
        Order order = newActivatedOrder(account.Id, Date.newInstance(2026, 4, 1), 1, 250);

        Assert.areEqual(250, reloadAccount(account.Id).Customer_Lifetime_Spend__c);

        Test.startTest();
        deactivate(order); // orders must be deactivated before they can be deleted
        delete order;
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual(0, result.Customer_Lifetime_Spend__c);
        Assert.areEqual(0, result.Number_of_Orders__c);
        Assert.areEqual(0, result.Average_Order_Value__c);
        Assert.isNull(result.First_Order_Date__c);
        Assert.isNull(result.Last_Order_Date__c);
    }

    @IsTest
    static void deletingOneOfManyOrdersRecalculates() {
        Account account = newAccount('Partial Cancel Co');
        newActivatedOrder(account.Id, Date.newInstance(2026, 1, 10), 2, 100); // 200, keep
        Order laterOrder = newActivatedOrder(account.Id, Date.newInstance(2026, 3, 5), 1, 100); // 100, delete

        Test.startTest();
        deactivate(laterOrder); // orders must be deactivated before they can be deleted
        delete laterOrder;
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual(200, result.Customer_Lifetime_Spend__c);
        Assert.areEqual(1, result.Number_of_Orders__c);
        Assert.areEqual(200, result.Average_Order_Value__c);
        Assert.areEqual(Date.newInstance(2026, 1, 10), result.First_Order_Date__c);
        Assert.areEqual(Date.newInstance(2026, 1, 10), result.Last_Order_Date__c);
    }

    @IsTest
    static void undeletingAnOrderRestoresMetrics() {
        Account account = newAccount('Restore Co');
        Order order = newActivatedOrder(account.Id, Date.newInstance(2026, 5, 20), 3, 100); // 300
        deactivate(order); // orders must be deactivated before they can be deleted
        delete order;
        Assert.areEqual(0, reloadAccount(account.Id).Customer_Lifetime_Spend__c);

        Test.startTest();
        undelete order;
        order.Status = 'Activated'; // undelete restores it as Draft; reactivate to qualify again
        update order;
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.areEqual(300, result.Customer_Lifetime_Spend__c);
        Assert.areEqual(1, result.Number_of_Orders__c);
        Assert.areEqual(Date.newInstance(2026, 5, 20), result.First_Order_Date__c);
    }

    @IsTest
    static void reparentingAnOrderMovesMetricsBetweenAccounts() {
        Account fromAccount = newAccount('Losing Account Co');
        Account toAccount = newAccount('Gaining Account Co');
        Order order = newActivatedOrder(fromAccount.Id, Date.newInstance(2026, 6, 1), 4, 100); // 400

        Assert.areEqual(400, reloadAccount(fromAccount.Id).Customer_Lifetime_Spend__c);

        Test.startTest();
        deactivate(order); // AccountId can't be edited on an activated order
        update new Order(Id = order.Id, AccountId = toAccount.Id, Status = 'Activated');
        Test.stopTest();

        Account losing = reloadAccount(fromAccount.Id);
        Assert.areEqual(0, losing.Customer_Lifetime_Spend__c);
        Assert.areEqual(0, losing.Number_of_Orders__c);
        Assert.isNull(losing.First_Order_Date__c);

        Account gaining = reloadAccount(toAccount.Id);
        Assert.areEqual(400, gaining.Customer_Lifetime_Spend__c);
        Assert.areEqual(1, gaining.Number_of_Orders__c);
        Assert.areEqual(Date.newInstance(2026, 6, 1), gaining.First_Order_Date__c);
    }

    @IsTest
    static void bypassFlagSkipsRecalculation() {
        Account account = newAccount('Bypassed Co');

        Test.startTest();
        OrderCustomerMetricsService.bypass = true;
        newActivatedOrder(account.Id, Date.newInstance(2026, 7, 1), 2, 100);
        OrderCustomerMetricsService.bypass = false;
        Test.stopTest();

        Account result = reloadAccount(account.Id);
        Assert.isNull(result.Customer_Lifetime_Spend__c);
        Assert.isNull(result.Number_of_Orders__c);
    }

    @IsTest
    static void metricsAreMaintainedForBulkActivation() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(Name = 'Bulk Co ' + i));
        }
        insert accounts;

        Id pbeId = pricebookEntryId();
        Id standardPricebookId = Test.getStandardPricebookId();

        List<Order> orders = new List<Order>();
        for (Account account : accounts) {
            orders.add(new Order(
                AccountId = account.Id,
                Status = 'Draft',
                EffectiveDate = Date.newInstance(2026, 8, 1),
                Pricebook2Id = standardPricebookId
            ));
        }
        insert orders;

        List<OrderItem> items = new List<OrderItem>();
        for (Order order : orders) {
            items.add(new OrderItem(
                OrderId = order.Id,
                PricebookEntryId = pbeId,
                Quantity = 1,
                UnitPrice = 50
            ));
        }
        insert items;

        for (Order order : orders) {
            order.Status = 'Activated';
        }

        Test.startTest();
        update orders;
        Test.stopTest();

        List<Account> results = [
            SELECT Customer_Lifetime_Spend__c, Number_of_Orders__c
            FROM Account
            WHERE Id IN :accounts
        ];
        Assert.areEqual(200, results.size());
        for (Account result : results) {
            Assert.areEqual(50, result.Customer_Lifetime_Spend__c);
            Assert.areEqual(1, result.Number_of_Orders__c);
        }
    }
}