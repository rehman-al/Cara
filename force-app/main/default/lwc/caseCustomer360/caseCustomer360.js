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


    get customerTags() {
        return this.account?.Customer_Tags__c ||
            'Not a Valid Customer';
    }


    get kycVerified() {
        return !!this.account?.KYC_Completed__c;
    }


    get kycStatusLabel() {
        return this.kycVerified
            ? 'Verified'
            : 'Not Verified';
    }


    get kycBadgeClass() {
        return this.kycVerified
            ? 'status-pill status-pill-success'
            : 'status-pill status-pill-neutral';
    }


    get accountTier() {
        return this.account?.Customer_Tier__c ||
            'Not Set';
    }


    get accountTierClass() {
        const tierClasses = {
            Bronze: 'status-pill status-pill-bronze',
            Silver: 'status-pill status-pill-silver',
            Gold: 'status-pill status-pill-gold',
            Platinum: 'status-pill status-pill-platinum'
        };

        return tierClasses[this.account?.Customer_Tier__c] ||
            'status-pill status-pill-neutral';
    }


    get loyaltyTierBenefits() {
        return this.account?.Loyalty_Tier_Benefits__c ||
            'No benefits recorded yet.';
    }


    get customerSince() {
        return this.account?.First_Order_Date__c ||
            this.account?.CreatedDate ||
            null;
    }


    get preferredCurrency() {
        return this.account?.Preferred_Currency__c ||
            'AED';
    }


    get personEmail() {
        return this.account?.PersonEmail ||
            'Not Available';
    }


    get personMobile() {
        return this.account?.PersonMobilePhone ||
            'Not Available';
    }


    get accountStreet() {
        return this.account?.PersonMailingStreet;
    }


    get accountCity() {
        return this.account?.PersonMailingCity;
    }


    get accountState() {
        return this.account?.PersonMailingState;
    }


    get accountPostalCode() {
        return this.account?.PersonMailingPostalCode;
    }


    get accountCountry() {
        return this.account?.PersonMailingCountry;
    }


    get hasAccountAddress() {
        return !!(
            this.accountStreet ||
            this.accountCity ||
            this.accountState ||
            this.accountCountry
        );
    }


    get isRepeatCustomer() {
        return this.totalOrders > 1;
    }


    get badges() {
        const chips = [];

        if (this.account?.VIP_Status__c) {
            chips.push({
                key: 'vip',
                label: 'VIP',
                cssClass: 'badge badge-vip'
            });
        }

        if (
            this.customerTags &&
            this.customerTags !== 'Not a Valid Customer'
        ) {
            chips.push({
                key: 'tag',
                label: this.customerTags,
                cssClass: 'badge badge-tag'
            });
        }

        if (this.isRepeatCustomer) {
            chips.push({
                key: 'repeat',
                label: 'Repeat Customer',
                cssClass: 'badge badge-repeat'
            });
        }

        if (this.kycVerified) {
            chips.push({
                key: 'kyc',
                label: 'KYC Verified',
                cssClass: 'badge badge-kyc'
            });
        }

        return chips;
    }


    get hasBadges() {
        return this.badges.length > 0;
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


    get lifetimeValue() {
        return this.data?.lifetimeValue || 0;
    }


    get averageOrderValue() {
        return this.data?.averageOrderValue || 0;
    }


    get totalCases() {
        return this.data?.totalCases || 0;
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