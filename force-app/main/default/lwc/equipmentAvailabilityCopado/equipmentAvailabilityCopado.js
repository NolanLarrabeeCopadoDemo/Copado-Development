import { LightningElement, wire } from 'lwc';
import getEquipmentAvailability from '@salesforce/apex/EquipmentAvailabilityController_copado.getEquipmentAvailability';

const STATUS_TO_CSS_CLASS = {
    Available: 'slds-theme_success',
    In_Transit: 'slds-theme_warning',
    In_Maintenance: 'slds-theme_error',
    Out_of_Service: 'slds-theme_error',
    Retired: 'slds-theme_shade'
};

const DEFAULT_STATUS_CSS_CLASS = 'slds-theme_shade';

export default class EquipmentAvailabilityCopado extends LightningElement {
    equipmentList = [];
    error;

    truckSizeClassFilter = '';
    operationalStatusFilter = '';
    minPayloadCapacityFilter;

    @wire(getEquipmentAvailability)
    wiredEquipment({ data, error }) {
        if (data) {
            this.equipmentList = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.equipmentList = [];
        }
    }

    get truckSizeClassOptions() {
        return this.buildOptionsFromField('Truck_Size_Class__c');
    }

    get operationalStatusOptions() {
        return this.buildOptionsFromField('Operational_Status__c');
    }

    buildOptionsFromField(fieldName) {
        const uniqueValues = new Set();
        this.equipmentList.forEach((record) => {
            if (record[fieldName]) {
                uniqueValues.add(record[fieldName]);
            }
        });
        const options = [{ label: 'All', value: '' }];
        uniqueValues.forEach((value) => {
            options.push({ label: value, value });
        });
        return options;
    }

    handleTruckSizeClassChange(event) {
        this.truckSizeClassFilter = event.detail.value;
    }

    handleOperationalStatusChange(event) {
        this.operationalStatusFilter = event.detail.value;
    }

    handleMinPayloadCapacityChange(event) {
        const value = event.detail.value;
        this.minPayloadCapacityFilter = value === '' ? undefined : Number(value);
    }

    get filteredEquipment() {
        return this.equipmentList
            .filter((record) => {
                const matchesTruckSizeClass =
                    !this.truckSizeClassFilter || record.Truck_Size_Class__c === this.truckSizeClassFilter;
                const matchesOperationalStatus =
                    !this.operationalStatusFilter || record.Operational_Status__c === this.operationalStatusFilter;
                const matchesPayloadCapacity =
                    this.minPayloadCapacityFilter === undefined ||
                    this.minPayloadCapacityFilter === null ||
                    (record.Payload_Capacity_lbs__c !== null &&
                        record.Payload_Capacity_lbs__c >= this.minPayloadCapacityFilter);
                return matchesTruckSizeClass && matchesOperationalStatus && matchesPayloadCapacity;
            })
            .map((record) => {
                return {
                    ...record,
                    statusCssClass: `slds-card equipment-card ${
                        STATUS_TO_CSS_CLASS[record.Operational_Status__c] || DEFAULT_STATUS_CSS_CLASS
                    }`,
                    isInTransit: record.Operational_Status__c === 'In_Transit' && !!record.Active_Shipment__c,
                    activeShipmentName: record.Active_Shipment__r ? record.Active_Shipment__r.Name : null
                };
            });
    }

    get hasEquipment() {
        return this.filteredEquipment.length > 0;
    }

    get hasError() {
        return !!this.error;
    }
}