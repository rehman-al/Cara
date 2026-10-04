import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import cancelOrder from '@salesforce/apex/CARAOrderCancellationController.cancelOrder';

export default class OrderCancelAction extends LightningElement {
    @api recordId;
    isProcessing = false;
    showConfirm = false;

    handleShowConfirm() {
        this.showConfirm = true;
    }

    handleCloseConfirm() {
        this.showConfirm = false;
    }

    handleCancel() {
        this.isProcessing = true;
        this.showConfirm = false;

        cancelOrder({ orderId: this.recordId })
            .then((result) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: result.success
                            ? result.refundFailed
                                ? 'Order Cancelled — Refund Failed'
                                : 'Order Cancelled'
                            : 'Order Not Cancelled',
                        message: result.message,
                        variant: result.success ? (result.refundFailed ? 'warning' : 'success') : 'warning'
                    })
                );
                if (result.success) {
                    this.dispatchEvent(new RefreshEvent());
                }
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Order Not Cancelled',
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