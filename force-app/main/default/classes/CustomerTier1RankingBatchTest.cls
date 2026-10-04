@IsTest
private class CustomerTier1RankingBatchTest {

    // ---------- helpers ----------

    private static Account newEligibleAccount(String name, Decimal spend) {
        return new Account(Name = name, Is_Guest__c = false, Customer_Lifetime_Spend__c = spend);
    }

    private static List<Account> reload(List<Account> accounts) {
        return [
            SELECT Id, Name, Customer_Lifetime_Spend__c, Is_Guest__c, Tier_1_Customer__c, Customer_Tier__c
            FROM Account
            WHERE Id IN :accounts
            ORDER BY Customer_Lifetime_Spend__c DESC NULLS LAST, Id ASC
        ];
    }

    private static void runBatch() {
        Test.startTest();
        Database.executeBatch(new CustomerTier1RankingBatch(), 50);
        Test.stopTest();
    }

    // ---------- tests ----------

    @IsTest
    static void topTenPercentFlaggedAndRestCleared() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 1; i <= 20; i++) {
            accounts.add(newEligibleAccount('Eligible ' + i, i * 1000));
        }
        insert accounts;

        runBatch();

        List<Account> results = reload(accounts);
        // cutoff = CEIL(20 * 0.10) = 2 -> only the two highest spenders qualify.
        Integer tier1Count = 0;
        for (Integer i = 0; i < results.size(); i++) {
            Boolean expected = i < 2;
            Assert.areEqual(expected, results[i].Tier_1_Customer__c,
                'Unexpected Tier-1 flag at rank ' + i + ' for ' + results[i].Name);
            if (results[i].Tier_1_Customer__c) {
                tier1Count++;
            }
        }
        Assert.areEqual(2, tier1Count);
    }

    @IsTest
    static void ineligibleAccountsAreNeverFlaggedTier1() {
        Account guestWithHighSpend = new Account(
            Name = 'Guest Big Spender', Is_Guest__c = true, Customer_Lifetime_Spend__c = 1000000
        );
        Account zeroSpend = newEligibleAccount('Zero Spend', 0);
        Account nullSpend = new Account(Name = 'Null Spend', Is_Guest__c = false);
        Account genuineEligible = newEligibleAccount('Genuine Customer', 500);

        List<Account> accounts = new List<Account>{ guestWithHighSpend, zeroSpend, nullSpend, genuineEligible };
        insert accounts;

        runBatch();

        Map<Id, Account> results = new Map<Id, Account>(reload(accounts));
        Assert.isFalse(results.get(guestWithHighSpend.Id).Tier_1_Customer__c, 'Guest account must not be Tier-1');
        Assert.isFalse(results.get(zeroSpend.Id).Tier_1_Customer__c, 'Zero spend account must not be Tier-1');
        Assert.isFalse(results.get(nullSpend.Id).Tier_1_Customer__c, 'Null spend account must not be Tier-1');
        // Only one eligible account exists, so CEIL(1 * 0.10) = 1 -> it qualifies.
        Assert.isTrue(results.get(genuineEligible.Id).Tier_1_Customer__c, 'Only eligible account should be Tier-1');
    }

    @IsTest
    static void tieAtBoundaryIsBrokenByAccountIdAscending() {
        List<Account> accounts = new List<Account>();
        // 10 eligible accounts -> cutoff = CEIL(10 * 0.10) = 1. Two accounts
        // tie for the top spot; the one inserted (and therefore created) first
        // has the lower Id and must win deterministically.
        accounts.add(newEligibleAccount('Tie First', 100000));
        accounts.add(newEligibleAccount('Tie Second', 100000));
        for (Integer i = 1; i <= 8; i++) {
            accounts.add(newEligibleAccount('Filler ' + i, 1000));
        }
        insert accounts;

        runBatch();

        Account tieFirst = [SELECT Tier_1_Customer__c FROM Account WHERE Id = :accounts[0].Id];
        Account tieSecond = [SELECT Tier_1_Customer__c FROM Account WHERE Id = :accounts[1].Id];
        Assert.isTrue(tieFirst.Tier_1_Customer__c, 'Lower Id should win the tie at the boundary');
        Assert.isFalse(tieSecond.Tier_1_Customer__c, 'Higher Id should lose the tie at the boundary');
    }

    @IsTest
    static void populationGrowthRecalculatesTier1Membership() {
        // Simulate the result of an earlier run: with only the original 10
        // accounts, the top spender (10000) would have been the sole Tier-1
        // customer (CEIL(10 * 0.10) = 1). Seed that stale state directly so
        // the whole scenario fits in a single executeBatch call, since a test
        // method may invoke Database.executeBatch only once.
        List<Account> original = new List<Account>();
        for (Integer i = 1; i <= 10; i++) {
            Account acct = newEligibleAccount('Original ' + i, i * 1000);
            acct.Tier_1_Customer__c = (i == 10);
            original.add(acct);
        }
        insert original;

        List<Account> newcomers = new List<Account>();
        for (Integer i = 1; i <= 10; i++) {
            newcomers.add(newEligibleAccount('Newcomer ' + i, 50000 + i));
        }
        insert newcomers;

        runBatch();

        // 20 eligible accounts now -> cutoff = CEIL(20 * 0.10) = 2, both newcomers' top spenders.
        Account formerTopOriginal = [SELECT Tier_1_Customer__c FROM Account WHERE Id = :original[9].Id];
        Assert.isFalse(formerTopOriginal.Tier_1_Customer__c, 'Original top spender should drop out once outranked');

        List<Account> topNewcomers = [
            SELECT Tier_1_Customer__c FROM Account WHERE Id IN :newcomers ORDER BY Customer_Lifetime_Spend__c DESC LIMIT 2
        ];
        for (Account acct : topNewcomers) {
            Assert.isTrue(acct.Tier_1_Customer__c, 'Top two newcomers should now be Tier-1');
        }
    }

    @IsTest
    static void spendIncreaseCanMoveCustomerIntoTier1() {
        // Seed the stale "before" state directly (account 10 was previously
        // the lone Tier-1 holder) so the whole scenario needs only a single
        // executeBatch call.
        List<Account> accounts = new List<Account>();
        for (Integer i = 1; i <= 10; i++) {
            Account acct = newEligibleAccount('Acct ' + i, i * 1000);
            acct.Tier_1_Customer__c = (i == 10);
            accounts.add(acct);
        }
        insert accounts;

        accounts[0].Customer_Lifetime_Spend__c = 999999;
        update accounts[0];

        runBatch();

        Account promoted = [SELECT Tier_1_Customer__c FROM Account WHERE Id = :accounts[0].Id];
        Assert.isTrue(promoted.Tier_1_Customer__c, 'Account should move into Tier-1 after a large spend increase');

        Account demoted = [SELECT Tier_1_Customer__c FROM Account WHERE Id = :accounts[9].Id];
        Assert.isFalse(demoted.Tier_1_Customer__c, 'Previous top spender should drop out once outranked');
    }

    @IsTest
    static void staleTier1FlagIsClearedWhenAccountBecomesIneligible() {
        // Seed an account that already carries a stale Tier_1_Customer__c =
        // true flag (e.g. left over from before it was reclassified as a
        // guest) directly, so the scenario needs only one executeBatch call.
        Account acct = newEligibleAccount('Was Eligible', 50000);
        acct.Tier_1_Customer__c = true;
        acct.Is_Guest__c = true; // no longer eligible
        insert acct;

        runBatch();

        Assert.isFalse(
            [SELECT Tier_1_Customer__c FROM Account WHERE Id = :acct.Id].Tier_1_Customer__c,
            'Account must be demoted once it becomes ineligible'
        );
    }

    @IsTest
    static void bulkPopulationIsProcessedCorrectly() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 1; i <= 250; i++) {
            accounts.add(newEligibleAccount('Bulk ' + i, i * 10));
        }
        insert accounts;

        Test.startTest();
        Database.executeBatch(new CustomerTier1RankingBatch(), 300);
        Test.stopTest();

        // cutoff = CEIL(250 * 0.10) = 25.
        Integer tier1Count = [SELECT COUNT() FROM Account WHERE Id IN :accounts AND Tier_1_Customer__c = true];
        Assert.areEqual(25, tier1Count);

        List<Account> top25 = [
            SELECT Id FROM Account WHERE Id IN :accounts ORDER BY Customer_Lifetime_Spend__c DESC, Id ASC LIMIT 25
        ];
        Integer matching = [
            SELECT COUNT() FROM Account WHERE Id IN :top25 AND Tier_1_Customer__c = true
        ];
        Assert.areEqual(25, matching, 'The flagged accounts must be exactly the top 25 by spend');
    }

    @IsTest
    static void batchDoesNotTouchUnrelatedCustomerMetricFields() {
        Account acct = newEligibleAccount('Untouched Fields', 75000);
        acct.Customer_Tier__c = 'Gold'; // set independently, as OrderCustomerMetricsService would
        insert acct;

        runBatch();

        Account result = [SELECT Customer_Tier__c, Customer_Lifetime_Spend__c FROM Account WHERE Id = :acct.Id];
        Assert.areEqual('Gold', result.Customer_Tier__c, 'Ranking batch must not alter unrelated loyalty tier fields');
        Assert.areEqual(75000, result.Customer_Lifetime_Spend__c, 'Ranking batch must not alter Lifetime Spend');
    }

    @IsTest
    static void schedulerEnqueuesTheRankingBatch() {
        Account acct = newEligibleAccount('Scheduled Run', 10000);
        insert acct;

        Test.startTest();
        new CustomerTier1RankingScheduler().execute(null);
        Test.stopTest();

        Assert.isTrue(
            [SELECT Tier_1_Customer__c FROM Account WHERE Id = :acct.Id].Tier_1_Customer__c,
            'Scheduler should have enqueued the batch and flagged the only eligible account'
        );
    }
}