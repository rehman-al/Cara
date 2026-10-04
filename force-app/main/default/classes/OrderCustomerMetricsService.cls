/**
 * Recalculates roll-up customer metrics on Account from its child Orders.
 *
 * Maintains on Account:
 *   - Customer_Lifetime_Spend__c = SUM(Order.TotalAmount)
 *   - Number_of_Orders__c        = COUNT(Order)
 *   - Average_Order_Value__c     = spend / count
 *   - First_Order_Date__c        = MIN(Order.EffectiveDate)
 *   - Last_Order_Date__c         = MAX(Order.EffectiveDate)
 *   - Customer_Tier__c           = loyalty tier for Customer_Lifetime_Spend__c
 *   - Loyalty_Tier_Benefits__c   = benefits text for that tier
 *
 * Only Orders whose Status is in QUALIFYING_STATUSES are counted. Change that
 * set to redefine what "spend" means for the business (for example, add
 * 'Draft' to include orders that have not been activated yet).
 *
 * Each affected account is fully re-aggregated rather than adjusted by a delta,
 * so the result is correct for insert / update / delete / undelete / reparent
 * and for bulk DML without any running-total bookkeeping.
 */
public with sharing class OrderCustomerMetricsService {
    /** Set to true from a data-load or migration script to skip recalculation. */
    public static Boolean bypass = false;

    /** Order statuses that count toward the customer spend metrics. */
    private static final Set<String> QUALIFYING_STATUSES = new Set<String>{ 'Activated' };

    /** Order fields whose change on update should force a recalculation. */
    private static final Set<String> MATERIAL_FIELDS = new Set<String>{
        'AccountId', 'TotalAmount', 'Status', 'EffectiveDate'
    };

    /** Tier assigned when lifetime spend is below every threshold below. */
    private static final String DEFAULT_TIER = 'Bronze';

    /**
     * Loyalty tiers in descending order of minimum lifetime spend (AED), each
     * with the member benefits it unlocks. The first entry whose minSpend the
     * account's lifetime spend meets or exceeds wins.
     */
    private static final List<TierDefinition> TIER_DEFINITIONS = new List<TierDefinition>{
        new TierDefinition('Platinum', 100000, new List<String>{
            'Complimentary delivery',
            'First access to new collections',
            'Exclusive Platinum member offers',
            'Priority client service',
            'Private shopping experiences'
        }),
        new TierDefinition('Gold', 50000, new List<String>{
            'Complimentary delivery',
            'Priority access to new collections',
            'Exclusive member offers',
            'Priority client service'
        }),
        new TierDefinition('Silver', 10000, new List<String>{
            'Complimentary delivery',
            'Early access to selected launches',
            'Exclusive member offers'
        })
    };

    private class TierDefinition {
        String label;
        Decimal minSpend;
        String benefits;

        TierDefinition(String label, Decimal minSpend, List<String> benefits) {
            this.label = label;
            this.minSpend = minSpend;
            this.benefits = String.join(benefits, '; ');
        }
    }

    /** Returns the loyalty tier label for a given lifetime spend. */
    private static String tierFor(Decimal lifetimeSpend) {
        for (TierDefinition tier : TIER_DEFINITIONS) {
            if (lifetimeSpend >= tier.minSpend) {
                return tier.label;
            }
        }
        return DEFAULT_TIER;
    }

    /** Returns the benefits text for a tier label, or null below Silver. */
    private static String benefitsFor(String tierLabel) {
        for (TierDefinition tier : TIER_DEFINITIONS) {
            if (tier.label == tierLabel) {
                return tier.benefits;
            }
        }
        return null;
    }

    /**
     * Trigger entry point. Pass Trigger.new / Trigger.old; either may be null
     * depending on the event (insert/undelete have no old, delete has no new).
     */
    public static void handleTrigger(List<Order> newOrders, List<Order> oldOrders) {
        if (bypass) {
            return;
        }

        Map<Id, Order> newMap = newOrders == null ? new Map<Id, Order>() : new Map<Id, Order>(newOrders);
        Map<Id, Order> oldMap = oldOrders == null ? new Map<Id, Order>() : new Map<Id, Order>(oldOrders);

        Set<Id> accountIds = new Set<Id>();

        if (oldMap.isEmpty()) {
            // insert or undelete
            for (Order o : newMap.values()) {
                addIfPresent(accountIds, o.AccountId);
            }
        } else if (newMap.isEmpty()) {
            // delete
            for (Order o : oldMap.values()) {
                addIfPresent(accountIds, o.AccountId);
            }
        } else {
            // update: recalc only when a material field changed; include both
            // the old and new AccountId so a reparented order updates both sides.
            for (Id orderId : newMap.keySet()) {
                Order newOrder = newMap.get(orderId);
                Order oldOrder = oldMap.get(orderId);
                if (isMaterialChange(newOrder, oldOrder)) {
                    addIfPresent(accountIds, newOrder.AccountId);
                    addIfPresent(accountIds, oldOrder.AccountId);
                }
            }
        }

        recalculate(accountIds);
    }

    private static void addIfPresent(Set<Id> accountIds, Id accountId) {
        if (accountId != null) {
            accountIds.add(accountId);
        }
    }

    private static Boolean isMaterialChange(Order newOrder, Order oldOrder) {
        for (String field : MATERIAL_FIELDS) {
            if (newOrder.get(field) != oldOrder.get(field)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Re-aggregates every qualifying Order for the given accounts and writes the
     * metric fields back. Safe to call with a null or empty set. Public so it
     * can also be driven from a batch backfill or a script.
     */
    public static void recalculate(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }

        // Start each affected account from a zeroed baseline so an account that
        // just lost its last qualifying order gets cleared rather than left stale.
        Map<Id, Account> toUpdate = new Map<Id, Account>();
        for (Id accountId : accountIds) {
            toUpdate.put(accountId, new Account(
                Id = accountId,
                Customer_Lifetime_Spend__c = 0,
                Number_of_Orders__c = 0,
                Average_Order_Value__c = 0,
                First_Order_Date__c = null,
                Last_Order_Date__c = null,
                Customer_Tier__c = DEFAULT_TIER,
                Loyalty_Tier_Benefits__c = benefitsFor(DEFAULT_TIER)
            ));
        }

        for (AggregateResult ar : [
            SELECT AccountId aid,
                   SUM(TotalAmount) totalSpend,
                   COUNT(Id) orderCount,
                   MIN(EffectiveDate) firstOrderDate,
                   MAX(EffectiveDate) lastOrderDate
            FROM Order
            WHERE AccountId IN :accountIds
              AND Status IN :QUALIFYING_STATUSES
            GROUP BY AccountId
        ]) {
            Id accountId = (Id) ar.get('aid');
            Integer orderCount = (Integer) ar.get('orderCount');
            Decimal totalSpend = (Decimal) ar.get('totalSpend');
            if (totalSpend == null) {
                totalSpend = 0;
            }

            Account acct = toUpdate.get(accountId);
            acct.Customer_Lifetime_Spend__c = totalSpend;
            acct.Number_of_Orders__c = orderCount;
            acct.Average_Order_Value__c = orderCount == 0
                ? 0
                : (totalSpend / orderCount).setScale(2, System.RoundingMode.HALF_UP);
            acct.First_Order_Date__c = (Date) ar.get('firstOrderDate');
            acct.Last_Order_Date__c = (Date) ar.get('lastOrderDate');

            String tier = tierFor(totalSpend);
            acct.Customer_Tier__c = tier;
            acct.Loyalty_Tier_Benefits__c = benefitsFor(tier);
        }

        update toUpdate.values();
    }
}