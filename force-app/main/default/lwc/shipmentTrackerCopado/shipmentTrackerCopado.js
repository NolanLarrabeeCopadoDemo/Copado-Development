import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = [
    'Shipment__c.Status__c',
    'Shipment__c.Request_Date__c',
    'Shipment__c.Expected_Delivery_Date__c',
    'Shipment__c.Actual_Delivery_Date__c'
];

const STAGE_DEFS = [
    { value: 'Draft', label: 'Draft', dateField: 'Request_Date__c', dateLabel: 'Requested' },
    { value: 'Scheduled', label: 'Scheduled', dateField: 'Expected_Delivery_Date__c', dateLabel: 'Expected' },
    { value: 'In Transit', label: 'In Transit', dateField: null, dateLabel: '' },
    { value: 'Delivered', label: 'Delivered', dateField: 'Actual_Delivery_Date__c', dateLabel: 'Delivered' }
];

export default class ShipmentTrackerCopado extends LightningElement {
    @api recordId;

    shipment;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredShipment({ data, error }) {
        if (data) {
            this.shipment = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.shipment = undefined;
        }
    }

    get status() {
        return this.shipment?.fields?.Status__c?.value;
    }

    get requestDate() {
        return this.shipment?.fields?.Request_Date__c?.value;
    }

    get expectedDeliveryDate() {
        return this.shipment?.fields?.Expected_Delivery_Date__c?.value;
    }

    get actualDeliveryDate() {
        return this.shipment?.fields?.Actual_Delivery_Date__c?.value;
    }

    get isCancelled() {
        return this.status === 'Cancelled';
    }

    get isDelayed() {
        return (
            !!this.actualDeliveryDate &&
            !!this.expectedDeliveryDate &&
            new Date(this.actualDeliveryDate) > new Date(this.expectedDeliveryDate)
        );
    }

    get currentStageIndex() {
        return STAGE_DEFS.findIndex((stage) => stage.value === this.status);
    }

    get stages() {
        const currentIndex = this.currentStageIndex;
        const cancelled = this.isCancelled;
        return STAGE_DEFS.map((stage, index) => {
            const isActive = !cancelled && index === currentIndex;
            const isCompleted = !cancelled && currentIndex > -1 && index < currentIndex;
            let itemClass = 'slds-progress__item';
            if (cancelled) {
                itemClass += ' slds-is-cancelled';
            } else if (isCompleted) {
                itemClass += ' slds-is-completed';
            } else if (isActive) {
                itemClass += ' slds-is-active';
            }
            return {
                key: stage.value,
                label: stage.label,
                dateLabel: stage.dateLabel,
                dateValue: this.dateValueFor(stage.dateField),
                itemClass
            };
        });
    }

    dateValueFor(fieldName) {
        if (!fieldName) {
            return undefined;
        }
        return this.shipment?.fields?.[fieldName]?.value;
    }
}