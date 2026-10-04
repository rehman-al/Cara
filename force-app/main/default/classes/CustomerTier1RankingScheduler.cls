/**
 * Scheduled entry point for CustomerTier1RankingBatch so the Tier-1 flag is
 * periodically recalculated as Lifetime Spend and the eligible customer
 * population change. Schedule with, for example:
 *   System.schedule('Customer Tier-1 Ranking - Nightly', '0 0 2 * * ?',
 *       new CustomerTier1RankingScheduler());
 */
public with sharing class CustomerTier1RankingScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CustomerTier1RankingBatch());
    }
}