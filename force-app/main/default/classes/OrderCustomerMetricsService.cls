/**
 * Recalculates roll-up customer metrics on Account from its child Orders.
 *
 * Maintains on Account:
 *   - Customer_Lifetime_Spend__c = SUM(Order.TotalAmount)
 *   - Number_of_Orders__c        = COUNT(Order)
 *   - Average_Order_Value__c     = spend / count
 *   - First_Order_Date__c        = MIN(Order.EffectiveDate)
 *   - Last_Order_Date__c         = MAX(Order.EffectiveDate)
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
                Last_Order_Date__c = null
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
        }

        update toUpdate.values();
    }
}
