import {
    LightningElement,
    api,
    wire
} from 'lwc';

import {
    NavigationMixin
} from 'lightning/navigation';

import {
    refreshApex
} from '@salesforce/apex';

import getCustomerContext
    from '@salesforce/apex/CaseCustomer360Controller.getCustomerContext';


const CASE_COLUMNS = [
    {
        label: 'Case Number',
        fieldName: 'CaseNumber',
        type: 'button',
        typeAttributes: {
            label: {
                fieldName: 'CaseNumber'
            },
            name: 'openCase',
            variant: 'base'
        }
    },
    {
        label: 'Subject',
        fieldName: 'Subject'
    },
    {
        label: 'Status',
        fieldName: 'Status'
    },
    {
        label: 'Priority',
        fieldName: 'Priority'
    },
    {
        label: 'Created Date',
        fieldName: 'CreatedDate',
        type: 'date'
    }
];


const ORDER_COLUMNS = [
    {
        label: 'Order Number',
        fieldName: 'OrderNumber',
        type: 'button',
        typeAttributes: {
            label: {
                fieldName: 'OrderNumber'
            },
            name: 'openOrder',
            variant: 'base'
        }
    },
    {
        label: 'Amount',
        fieldName: 'TotalAmount',
        type: 'number',
        typeAttributes: {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }
    },
    {
        label: 'Currency',
        fieldName: 'CurrencyIsoCode__c'
    },
    {
        label: 'Status',
        fieldName: 'Status'
    },
    {
        label: 'Shipping',
        fieldName: 'Shipping_Status__c'
    },
    {
        label: 'Payment',
        fieldName: 'Payment_Status__c'
    },
    {
        label: 'Confirmation',
        fieldName: 'Confirmation_Status__c'
    }
];


const CONVERSATION_COLUMNS = [
    {
        label: 'Case',
        fieldName: 'RelatedCaseNumber',
        type: 'button',
        typeAttributes: {
            label: {
                fieldName: 'RelatedCaseNumber'
            },
            name: 'openConversationCase',
            variant: 'base'
        }
    },
    {
        label: 'Direction',
        fieldName: 'Direction'
    },
    {
        label: 'Subject',
        fieldName: 'Subject'
    },
    {
        label: 'From',
        fieldName: 'FromAddress'
    },
    {
        label: 'Date',
        fieldName: 'MessageDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    }
];


export default class CaseCustomer360
    extends NavigationMixin(LightningElement) {

    @api recordId;

    data;
    error;

    isLoading = true;

    wiredContextResult;

    caseColumns = CASE_COLUMNS;
    orderColumns = ORDER_COLUMNS;
    conversationColumns = CONVERSATION_COLUMNS;


    @wire(getCustomerContext, {
        caseId: '$recordId'
    })
    wiredCustomerContext(result) {

        this.wiredContextResult = result;

        const {
            data,
            error
        } = result;

        if (data) {

            this.data = data;
            this.error = undefined;
            this.isLoading = false;

        } else if (error) {

            this.data = undefined;

            this.error =
                error.body?.message ||
                'Unable to load Customer 360 information.';

            this.isLoading = false;
        }
    }


    get hasAccount() {
        return !!this.data?.account;
    }


    get account() {
        return this.data?.account;
    }


    get contact() {
        return this.data?.contact;
    }


    get hasContact() {
        return !!this.contact;
    }


    get accountName() {
        return this.account?.Name ||
            'Not Available';
    }






    get accountPhone() {
        return this.account?.Phone ||
            'Not Available';
    }


    get accountType() {
        return this.account?.Type ||
            'Not Available';
    }


get customerStatus() {
    return this.account
        ? 'Account Linked'
        : 'No Account Linked';
}


    get contactPhone() {
        return this.contact?.Phone ||
            'Not Available';
    }


    get contactMobile() {
        return this.contact?.MobilePhone ||
            'Not Available';
    }


    get orders() {
        return this.data?.orders || [];
    }


    get previousCases() {
        return this.data?.previousCases || [];
    }


    get conversations() {
        return this.data?.conversations || [];
    }


    get hasOrders() {
        return this.orders.length > 0;
    }


    get hasPreviousCases() {
        return this.previousCases.length > 0;
    }


    get hasConversations() {
        return this.conversations.length > 0;
    }


    get totalOrders() {
        return this.data?.totalOrders || 0;
    }


    get completedOrders() {
        return this.data?.completedOrders || 0;
    }


    get lifetimeValue() {
        return this.data?.lifetimeValue || 0;
    }


    get totalCases() {
        return this.data?.totalCases || 0;
    }


    get latestShippingStatus() {

        if (!this.orders.length) {
            return 'No Orders';
        }

        return this.orders[0].Shipping_Status__c ||
            'Not Available';
    }


    get conversationCount() {
        return this.conversations.length;
    }


    get conversationRows() {

        const caseNumberMap = new Map();


        if (this.data?.currentCase) {

            caseNumberMap.set(
                this.data.currentCase.Id,
                this.data.currentCase.CaseNumber
            );
        }


        this.previousCases.forEach(
            caseRecord => {

                caseNumberMap.set(
                    caseRecord.Id,
                    caseRecord.CaseNumber
                );
            }
        );


        return this.conversations.map(
            message => ({
                ...message,

                Direction:
                    message.Incoming
                        ? 'Incoming'
                        : 'Outgoing',

                RelatedCaseNumber:
                    caseNumberMap.get(
                        message.ParentId
                    ) || 'Open Case'
            })
        );
    }


    handleCaseAction(event) {

        this.navigateToRecord(
            event.detail.row.Id,
            'Case'
        );
    }


    handleOrderAction(event) {

        this.navigateToRecord(
            event.detail.row.Id,
            'Order'
        );
    }


    handleConversationAction(event) {

        this.navigateToRecord(
            event.detail.row.ParentId,
            'Case'
        );
    }


    openAccount() {

        if (this.account?.Id) {

            this.navigateToRecord(
                this.account.Id,
                'Account'
            );
        }
    }


    openContact() {

        if (this.contact?.Id) {

            this.navigateToRecord(
                this.contact.Id,
                'Contact'
            );
        }
    }


    navigateToRecord(
        recordId,
        objectApiName
    ) {

        this[
            NavigationMixin.Navigate
        ]({
            type: 'standard__recordPage',

            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }


    async handleRefresh() {

        this.isLoading = true;

        await refreshApex(
            this.wiredContextResult
        );

        this.isLoading = false;
    }
}