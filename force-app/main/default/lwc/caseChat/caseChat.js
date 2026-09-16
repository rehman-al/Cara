import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChatData from '@salesforce/apex/CaseChatController.getChatData';
import sendMessage from '@salesforce/apex/CaseChatController.sendMessage';

export default class CaseChat extends LightningElement {
    @api recordId;

    accountName = 'Case Customer';
    messages = [];
    draftMessage = '';
    loadError;
    isLoading = true;
    isSending = false;
    refreshCooldownSeconds = 0;

    wiredChatResult;
    shouldScrollToLatest = false;
    refreshCooldownTimer;

    @wire(getChatData, { caseId: '$recordId' })
    wiredChat(result) {
        this.wiredChatResult = result;
        const { data, error } = result;

        if (data) {
            this.accountName = data.accountName || 'Case Customer';
            this.messages = (data.messages || []).map((message) => {
                const isInbound = message.direction === 'Inbound';
                return {
                    ...message,
                    rowClass: isInbound
                        ? 'message-row message-row_inbound'
                        : 'message-row message-row_outbound',
                    bubbleClass: isInbound
                        ? 'message-bubble message-bubble_inbound'
                        : 'message-bubble message-bubble_outbound'
                };
            });
            this.loadError = undefined;
            this.isLoading = false;
            this.shouldScrollToLatest = true;
        } else if (error) {
            this.messages = [];
            this.loadError = this.getErrorMessage(error);
            this.isLoading = false;
        }
    }

    renderedCallback() {
        if (!this.shouldScrollToLatest) {
            return;
        }

        const anchor = this.template.querySelector('.scroll-anchor');
        if (anchor) {
            anchor.scrollIntoView({ behavior: 'smooth', block: 'end' });
            this.shouldScrollToLatest = false;
        }
    }

    get hasMessages() {
        return this.messages.length > 0;
    }

    get isInitialLoading() {
        return this.isLoading && !this.hasMessages;
    }

    get isSendDisabled() {
        return this.isSending || !this.draftMessage.trim();
    }

    get isRefreshDisabled() {
        return this.isLoading || this.refreshCooldownSeconds > 0;
    }

    get refreshButtonTitle() {
        return this.refreshCooldownSeconds > 0
            ? `Refresh available in ${this.refreshCooldownSeconds} seconds`
            : 'Refresh messages';
    }

    handleMessageInput(event) {
        this.draftMessage = event.target.value;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSend();
        }
    }

    async handleSend() {
        const messageBody = this.draftMessage.trim();
        if (!messageBody || this.isSending) {
            return;
        }

        this.isSending = true;
        try {
            await sendMessage({ caseId: this.recordId, messageBody });
            this.draftMessage = '';
            this.shouldScrollToLatest = true;
            await refreshApex(this.wiredChatResult);
            this.focusComposer();
        } catch (error) {
            this.showError('Unable to send message', error);
        } finally {
            this.isSending = false;
        }
    }

    async handleRefresh() {
        if (this.isRefreshDisabled) {
            return;
        }

        this.startRefreshCooldown();
        this.isLoading = true;
        this.shouldScrollToLatest = true;
        try {
            await refreshApex(this.wiredChatResult);
        } catch (error) {
            this.showError('Unable to refresh messages', error);
        } finally {
            this.isLoading = false;
        }
    }

    startRefreshCooldown() {
        this.refreshCooldownSeconds = 60;
        clearInterval(this.refreshCooldownTimer);

        this.refreshCooldownTimer = setInterval(() => {
            if (this.refreshCooldownSeconds <= 1) {
                clearInterval(this.refreshCooldownTimer);
                this.refreshCooldownTimer = undefined;
                this.refreshCooldownSeconds = 0;
                return;
            }

            this.refreshCooldownSeconds -= 1;
        }, 1000);
    }

    disconnectedCallback() {
        clearInterval(this.refreshCooldownTimer);
    }

    focusComposer() {
        requestAnimationFrame(() => {
            this.template.querySelector('.message-input')?.focus();
        });
    }

    showError(title, error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: this.getErrorMessage(error),
                variant: 'error'
            })
        );
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}