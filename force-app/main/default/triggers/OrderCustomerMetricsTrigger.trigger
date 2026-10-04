/**
 * Keeps the Account customer roll-up metrics (Customer Lifetime Spend, Number of
 * Orders, Average Order Value, First / Last Order Date) in sync with its Orders.
 *
 * All logic lives in OrderCustomerMetricsService. Runs after the DML so the
 * committed Order rows are what gets aggregated.
 */
trigger OrderCustomerMetricsTrigger on Order (
    after insert,
    after update,
    after delete,
    after undelete
) {
    OrderCustomerMetricsService.handleTrigger(
        Trigger.isDelete ? null : Trigger.new,
        (Trigger.isInsert || Trigger.isUndelete) ? null : Trigger.old
    );
}