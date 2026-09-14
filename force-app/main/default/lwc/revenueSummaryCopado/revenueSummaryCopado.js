import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = [
    'Completed_Shipment__c.Gross_Revenue__c',
    'Completed_Shipment__c.Total_Cost__c',
    'Completed_Shipment__c.Net_Revenue__c',
    'Completed_Shipment__c.Profit_Margin_Pct__c',
    'Completed_Shipment__c.Fuel_Cost__c',
    'Completed_Shipment__c.Maintenance_Allocation__c',
    'Completed_Shipment__c.On_Time_Delivery__c',
    'Completed_Shipment__c.Delay_Days__c',
    'Completed_Shipment__c.Shipment__r.Actual_Delivery_Date__c',
    'Completed_Shipment__c.Shipment__r.Expected_Delivery_Date__c'
];

export default class RevenueSummaryCopado extends LightningElement {
    @api recordId;

    record;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.record = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.record = undefined;
        }
    }

    get hasError() {
        return this.error !== undefined && this.error !== null;
    }

    get errorMessage() {
        return this.error && this.error.body && this.error.body.message
            ? this.error.body.message
            : 'Unable to load shipment financial data.';
    }

    getFieldValue(fieldApiName) {
        return this.record &&
            this.record.fields &&
            this.record.fields[fieldApiName]
            ? this.record.fields[fieldApiName].value
            : undefined;
    }

    get grossRevenue() {
        return this.getFieldValue('Gross_Revenue__c');
    }

    get totalCost() {
        return this.getFieldValue('Total_Cost__c');
    }

    get netRevenue() {
        return this.getFieldValue('Net_Revenue__c');
    }

    get profitMarginPct() {
        return this.getFieldValue('Profit_Margin_Pct__c');
    }

    get fuelCost() {
        return this.getFieldValue('Fuel_Cost__c');
    }

    get maintenanceAllocation() {
        return this.getFieldValue('Maintenance_Allocation__c');
    }

    get onTimeDelivery() {
        return this.getFieldValue('On_Time_Delivery__c');
    }

    get delayDays() {
        const value = this.getFieldValue('Delay_Days__c');
        return value === undefined || value === null ? 0 : value;
    }

    get netRevenueTileClass() {
        return this.isPositive(this.netRevenue)
            ? 'slds-box slds-theme_success kpi-tile'
            : 'slds-box slds-theme_error kpi-tile';
    }

    get profitMarginTileClass() {
        return this.isPositive(this.profitMarginPct)
            ? 'slds-box slds-theme_success kpi-tile'
            : 'slds-box slds-theme_error kpi-tile';
    }

    get deliveryBadgeClass() {
        return this.onTimeDelivery
            ? 'slds-badge slds-theme_success'
            : 'slds-badge slds-theme_warning';
    }

    get deliveryStatusLabel() {
        return this.onTimeDelivery ? 'On Time' : 'Delayed';
    }

    get showDelayDays() {
        return !this.onTimeDelivery && this.delayDays > 0;
    }

    get delayDaysLabel() {
        return this.delayDays === 1
            ? '1 day late'
            : `${this.delayDays} days late`;
    }

    isPositive(value) {
        return typeof value === 'number' && value >= 0;
    }
}