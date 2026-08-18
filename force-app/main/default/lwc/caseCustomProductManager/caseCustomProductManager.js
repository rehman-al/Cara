import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { refreshApex } from '@salesforce/apex';

import getRequests from '@salesforce/apex/CaseCustomProductController.getRequests';
import createRequest from '@salesforce/apex/CaseCustomProductController.createRequest';
import updateRequest from '@salesforce/apex/CaseCustomProductController.updateRequest';
import deleteRequest from '@salesforce/apex/CaseCustomProductController.deleteRequest';
import getRequestFiles from '@salesforce/apex/CaseCustomProductController.getRequestFiles';

const REQUEST_ACTIONS = [
    { label: 'Files', name: 'manageFiles' },
    { label: 'Delete', name: 'delete' }
];

const REQUEST_COLUMNS = [
    { label: 'Request', fieldName: 'Name', type: 'text' },
    { label: 'Product Name', fieldName: 'Product_Name__c', type: 'text' },
    { label: 'Existing Product', fieldName: 'productName', type: 'text' },
    { label: 'Category', fieldName: 'Category__c', type: 'text' },
    { label: 'Quantity', fieldName: 'Quantity__c', type: 'number' },
    {
        label: 'Estimated Cost',
        fieldName: 'Estimated_Cost__c',
        type: 'currency'
    },
    {
        label: 'Selling Price',
        fieldName: 'Selling_Price__c',
        type: 'currency'
    },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: REQUEST_ACTIONS
        }
    }
];

const FILE_COLUMNS = [
    { label: 'File Name', fieldName: 'fileName', type: 'text' },
    { label: 'Type', fieldName: 'fileType', type: 'text' },
    {
        type: 'button',
        typeAttributes: {
            label: 'View / Preview',
            name: 'preview',
            title: 'View or preview file',
            variant: 'base'
        }
    }
];

const NEW_REQUEST = {
    Product_Name__c: '',
    Description__c: '',
    Category__c: '',
    Quantity__c: 1,
    Dimensions__c: '',
    Requested_Specification__c: '',
    Estimated_Cost__c: null,
    Selling_Price__c: null,
    Status__c: 'Draft',
    Product__c: null
};

export default class CaseCustomProductManager extends NavigationMixin(
    LightningElement
) {
    @api recordId;

    requestColumns = REQUEST_COLUMNS;
    fileColumns = FILE_COLUMNS;

    requests = [];
    draft = { ...NEW_REQUEST };

    requestFiles = [];

    selectedRequestId = null;
    selectedProductName = '';
    selectedPreviewFile = null;

    isModalOpen = false;
    isAttachmentModalOpen = false;

    isSaving = false;
    requestsLoading = true;
    requestFilesLoading = false;

    wiredRequestsResult;

    categoryOptions = [
        'Product',
        'Service',
        'Custom',
        'Other'
    ].map((value) => ({
        label: value,
        value
    }));

    statusOptions = [
        'Draft',
        'Under Review',
        'Approved',
        'Rejected'
    ].map((value) => ({
        label: value,
        value
    }));

    @wire(getRequests, { caseId: '$recordId' })
    wiredRequests(result) {
        this.wiredRequestsResult = result;
        this.requestsLoading = false;

        if (result.data) {
            this.requests = result.data.map((request) => ({
                ...request,
                productName: request.Product__r?.Name || ''
            }));
        } else if (result.error) {
            this.requests = [];
            this.showError(
                'Unable to load requests',
                result.error
            );
        }
    }

    get hasRequests() {
        return this.requests.length > 0;
    }

    get hasRequestFiles() {
        return this.requestFiles.length > 0;
    }

    get isLoading() {
        return this.requestsLoading;
    }

    get modalTitle() {
        return this.draft.Id
            ? 'Edit Custom Product Request'
            : 'Add Custom Product Request';
    }

    get isPreviewPdf() {
        return Boolean(
            this.selectedPreviewFile &&
                this.selectedPreviewFile.fileType &&
                this.selectedPreviewFile.fileType.toUpperCase() === 'PDF'
        );
    }

    handleAdd() {
        this.resetDraft();
        this.isModalOpen = true;
    }

    handleRequestAction(event) {
        const { action, row } = event.detail;

        if (action.name === 'manageFiles') {
            this.selectedRequestId = row.Id;
            this.selectedProductName =
                row.Product_Name__c || 'Product';

            this.isAttachmentModalOpen = true;

            this.loadRequestFiles(row.Id);
        } else if (action.name === 'delete') {
            this.confirmDelete(row);
        }
    }

    handleFieldChange(event) {
        const rawValue =
            event.detail?.value ?? event.target.value;

        const value =
            event.target.type === 'number'
                ? this.numberOrNull(rawValue)
                : rawValue;

        this.draft = {
            ...this.draft,
            [event.target.name]: value
        };
    }

    handleProductChange(event) {
        this.draft = {
            ...this.draft,
            Product__c: event.detail.recordId || null
        };
    }

    closeModal() {
        if (this.isSaving) {
            return;
        }

        this.isModalOpen = false;
        this.resetDraft();
    }

    closeAttachmentModal() {
        this.isAttachmentModalOpen = false;
        this.resetAttachmentState();
    }

    async loadRequestFiles(requestId) {
        if (!requestId) {
            this.requestFiles = [];
            return;
        }

        this.requestFilesLoading = true;

        try {
            const files = await getRequestFiles({
                requestId
            });

            this.requestFiles = files || [];
        } catch (error) {
            this.requestFiles = [];

            this.showError(
                'Unable to load product files',
                error
            );
        } finally {
            this.requestFilesLoading = false;
        }
    }

    handleRequestFilePreview(event) {
        const file = event.detail.row;

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: file.contentDocumentId
            }
        });
    }

    async handleUploadFinished(event) {
        const uploadedFiles =
            event.detail.files || [];

        if (uploadedFiles.length === 0) {
            return;
        }

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Files uploaded',
                message:
                    `${uploadedFiles.length} file(s) attached ` +
                    'to the custom product request.',
                variant: 'success'
            })
        );

        await this.loadRequestFiles(
            this.selectedRequestId
        );
    }

    openAttachmentPreview(event) {
        const fileId =
            event.currentTarget.dataset.file;

        this.selectedPreviewFile =
            this.requestFiles.find(
                (item) =>
                    item.contentDocumentId === fileId
            ) || null;
    }

    closeAttachmentPreview() {
        this.selectedPreviewFile = null;
    }

    async handleSave() {
        const fields = [
            ...this.template.querySelectorAll(
                '[data-form-field]'
            )
        ];

        const isValid = fields.reduce(
            (valid, field) => {
                field.reportValidity();

                return (
                    valid &&
                    field.checkValidity()
                );
            },
            true
        );

        if (!isValid) {
            return;
        }

        const isEdit = Boolean(this.draft.Id);

        const requestRecord = {
            sobjectType:
                'Custom_Product_Request__c',
            ...this.draft
        };

        this.isSaving = true;

        try {
            if (isEdit) {
                await updateRequest({
                    requestRecord
                });
            } else {
                await createRequest({
                    caseId: this.recordId,
                    requestRecord
                });
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: isEdit
                        ? 'Custom product request updated.'
                        : 'Custom product request created.',
                    variant: 'success'
                })
            );

            /*
             * Refresh the table first.
             */
            await refreshApex(
                this.wiredRequestsResult
            );

            /*
             * IMPORTANT:
             * Close the Add Product popup directly.
             * Do not call closeModal() here because
             * isSaving is still true at this point.
             */
            this.isModalOpen = false;

            /*
             * Reset the Add Product form.
             */
            this.resetDraft();

        } catch (error) {
            this.showError(
                'Unable to save request',
                error
            );
        } finally {
            this.isSaving = false;
        }
    }

    async confirmDelete(row) {
        const confirmed =
            await LightningConfirm.open({
                label:
                    'Delete Custom Product Request',
                message:
                    `Delete ${row.Product_Name__c}?`,
                variant: 'headerless'
            });

        if (!confirmed) {
            return;
        }

        try {
            await deleteRequest({
                requestId: row.Id
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message:
                        'Custom product request deleted.',
                    variant: 'success'
                })
            );

            await refreshApex(
                this.wiredRequestsResult
            );
        } catch (error) {
            this.showError(
                'Unable to delete request',
                error
            );
        }
    }

    resetDraft() {
        this.draft = {
            ...NEW_REQUEST
        };

        this.requestFiles = [];
        this.selectedRequestId = null;
        this.selectedProductName = '';
        this.selectedPreviewFile = null;
    }

    resetAttachmentState() {
        this.requestFiles = [];
        this.selectedRequestId = null;
        this.selectedProductName = '';
        this.selectedPreviewFile = null;
    }

    numberOrNull(value) {
        return value === '' ||
            value === null ||
            value === undefined
            ? null
            : Number(value);
    }

    showError(title, error) {
        const message =
            error?.body?.message ||
            error?.message ||
            'An unexpected error occurred.';

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant: 'error'
            })
        );
    }
}