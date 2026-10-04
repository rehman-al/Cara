import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import { getRecord } from 'lightning/uiRecordApi';
import retrySync from '@salesforce/apex/CARAOrderStagingRetryController.retrySync';

const FIELDS = ['SFCC_Order_Staging__c.Sync_Status__c'];
const BLOCKED_STATUSES = ['Syncing', 'Synced'];

export default class OrderStagingRetryAction extends LightningElement {
    @api recordId;
    isProcessing = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    stagingRecord;

    get syncStatus() {
        return this.stagingRecord?.data?.fields?.Sync_Status__c?.value;
    }

    get isRetryDisabled() {
        return this.isProcessing || BLOCKED_STATUSES.includes(this.syncStatus);
    }

    get statusMessage() {
        if (this.syncStatus === 'Synced') {
            return 'This order has already been synchronized. No action is needed.';
        }
        if (this.syncStatus === 'Syncing') {
            return 'A sync is currently in progress for this order.';
        }
        return 'Re-runs the Order Sync for this staged payload using the original SFCC data. SFCC does not need to resend the order.';
    }

    handleRetry() {
        this.isProcessing = true;

        retrySync({ stagingId: this.recordId })
            .then((result) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: result.success ? 'Order Sync Succeeded' : 'Order Sync Failed',
                        message: result.message,
                        variant: result.success ? 'success' : 'error'
                    })
                );
                this.dispatchEvent(new RefreshEvent());
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Order Sync Failed',
                        message: error?.body?.message || 'An unexpected error occurred.',
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }
}