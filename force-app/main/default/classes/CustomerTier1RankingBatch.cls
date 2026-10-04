/**
 * Ranks eligible customers by Customer_Lifetime_Spend__c and sets
 * Tier_1_Customer__c = true for the top 10%, which Data Cloud consumes as the
 * Tier-1 segment qualification flag.
 *
 * Eligibility: Is_Guest__c = false AND Customer_Lifetime_Spend__c > 0. Guest
 * checkout placeholder accounts and accounts with no qualifying spend never
 * occupy a Tier-1 position.
 *
 * Top-10% boundary: cutoff = CEIL(eligible count * 0.10), so any eligible
 * population of 1 or more always yields at least one Tier-1 customer (for
 * example 101 eligible customers -> CEIL(10.1) = 11). Ties at the boundary are
 * broken by Account Id ascending so the result is deterministic and stable
 * between runs.
 *
 * Rerunning this batch recalculates the full population from scratch: it both
 * promotes newly-qualifying accounts and demotes accounts that drop out of the
 * top 10% or stop being eligible, so the flag never permanently locks anyone
 * into Tier-1.
 */
public with sharing class CustomerTier1RankingBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Set<Id> tier1AccountIds = new Set<Id>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        List<Account> eligible = [
            SELECT Id
            FROM Account
            WHERE Is_Guest__c = false
              AND Customer_Lifetime_Spend__c > 0
            ORDER BY Customer_Lifetime_Spend__c DESC, Id ASC
        ];

        Integer cutoff = (Integer) Math.ceil(eligible.size() * 0.10);
        for (Integer i = 0; i < cutoff; i++) {
            tier1AccountIds.add(eligible[i].Id);
        }

        // Scope covers every account that could need its flag changed: current
        // Tier-1 holders (may need to drop out) plus every eligible account
        // (may need to newly qualify).
        return Database.getQueryLocator([
            SELECT Id, Tier_1_Customer__c
            FROM Account
            WHERE Tier_1_Customer__c = true
               OR (Is_Guest__c = false AND Customer_Lifetime_Spend__c > 0)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        List<Account> toUpdate = new List<Account>();
        for (Account acct : scope) {
            Boolean shouldBeTier1 = tier1AccountIds.contains(acct.Id);
            if (acct.Tier_1_Customer__c != shouldBeTier1) {
                toUpdate.add(new Account(Id = acct.Id, Tier_1_Customer__c = shouldBeTier1));
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}