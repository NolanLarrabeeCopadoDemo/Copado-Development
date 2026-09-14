import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';

import WAYPOINTS_JSON_FIELD   from '@salesforce/schema/Route__c.Waypoints_JSON__c';
import WEATHER_SEVERITY_FIELD from '@salesforce/schema/Route__c.Weather_Severity__c';
import MAP_EMBED_URL_FIELD     from '@salesforce/schema/Route__c.Map_Embed_URL__c';
import WEATHER_ALERTS_JSON_FIELD from '@salesforce/schema/Route__c.Weather_Alerts_JSON__c';

/** Static resource name – must match the uploaded zip resource: LeafletJS */
const LEAFLET_RESOURCE_NAME = 'LeafletJS';

const FIELDS = [
    WAYPOINTS_JSON_FIELD,
    WEATHER_SEVERITY_FIELD,
    MAP_EMBED_URL_FIELD,
    WEATHER_ALERTS_JSON_FIELD
];

const SEVERITY_CONFIG = {
    Low:      { label: 'Low Severity',      cssClass: 'slds-badge slds-theme_success severity-badge' },
    Moderate: { label: 'Moderate Severity', cssClass: 'slds-badge slds-theme_warning severity-badge' },
    High:     { label: 'High Severity',     cssClass: 'slds-badge slds-theme_error severity-badge' },
    Severe:   { label: 'Severe Weather',    cssClass: 'slds-badge slds-theme_error severity-badge severity-badge--severe' }
};

export default class LogisticsMapCopado extends LightningElement {
    @api recordId;

    @track _waypointsJson   = null;
    @track _weatherSeverity = null;
    @track _mapEmbedUrl     = null;
    @track _weatherAlerts   = null;

    isLoading       = true;
    _leafletLoaded  = false;
    _leafletFailed  = false;
    _map            = null;
    _errorMessage   = null;

    // ─── Wire ────────────────────────────────────────────────────────────────

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRoute({ data, error }) {
        if (data) {
            this._waypointsJson   = getFieldValue(data, WAYPOINTS_JSON_FIELD);
            this._weatherSeverity = getFieldValue(data, WEATHER_SEVERITY_FIELD);
            this._mapEmbedUrl     = getFieldValue(data, MAP_EMBED_URL_FIELD);
            this._weatherAlerts   = getFieldValue(data, WEATHER_ALERTS_JSON_FIELD);
            this.isLoading = false;
            if (this._waypointsJson) {
                this._initLeaflet();
            }
        } else if (error) {
            this._handleError('Failed to load route data.', error);
        }
    }

    // ─── Lifecycle ───────────────────────────────────────────────────────────

    renderedCallback() {
        if (this._leafletLoaded && !this._map) {
            this._renderLeafletMap();
        }
    }

    // ─── Getters ─────────────────────────────────────────────────────────────

    get hasError()        { return !!this._errorMessage; }
    get errorMessage()    { return this._errorMessage; }
    get hasSeverity()     { return !!this._weatherSeverity; }
    get showLeafletMap()  { return !this.isLoading && !this.hasError && !!this._waypointsJson && !this._leafletFailed; }
    get showFallbackMap() { return !this.isLoading && !this.hasError && (!this._waypointsJson || this._leafletFailed) && !!this._mapEmbedUrl; }
    get showNoData()      { return !this.isLoading && !this.hasError && !this._waypointsJson && !this._mapEmbedUrl; }
    get mapEmbedUrl()     { return this._mapEmbedUrl; }

    get weatherSeverityLabel() {
        return SEVERITY_CONFIG[this._weatherSeverity]?.label ?? this._weatherSeverity;
    }

    get severityBadgeClass() {
        return SEVERITY_CONFIG[this._weatherSeverity]?.cssClass ?? 'slds-badge severity-badge';
    }

    // ─── Private methods ─────────────────────────────────────────────────────

    _initLeaflet() {
        if (this._leafletLoaded || this._leafletFailed) { return; }
        const base = `/resource/${LEAFLET_RESOURCE_NAME}`;
        Promise.all([
            loadScript(this, `${base}/leaflet.min.js`),
            loadStyle(this, `${base}/leaflet.min.css`)
        ])
        .then(() => {
            this._leafletLoaded = true;
            this._renderLeafletMap();
        })
        .catch((err) => {
            this._leafletFailed = true;
            console.error('[logisticsMapCopado] Leaflet load failed – falling back to static map.', err);
        });
    }

    _renderLeafletMap() {
        const container = this.template.querySelector('[id="map-container"]');
        if (!container || this._map) { return; }

        let waypoints;
        try {
            waypoints = JSON.parse(this._waypointsJson);
        } catch (parseErr) {
            this._handleError('Waypoints data is invalid JSON.', parseErr);
            return;
        }

        if (!Array.isArray(waypoints) || waypoints.length < 2) {
            this._handleError('At least two waypoints are required to render a route.', null);
            return;
        }

        try {
            // eslint-disable-next-line no-undef
            const L = window.L;
            const latlngs = waypoints.map(wp => [wp.lat, wp.lng]);

            this._map = L.map(container).setView(latlngs[0], 10);

            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            }).addTo(this._map);

            L.polyline(latlngs, { color: '#005fb2', weight: 4 }).addTo(this._map);

            L.marker(latlngs[0])
                .addTo(this._map)
                .bindPopup('Origin')
                .openPopup();

            L.marker(latlngs[latlngs.length - 1])
                .addTo(this._map)
                .bindPopup('Destination');

            this._renderWeatherMarkers(L);

            this._map.fitBounds(L.polyline(latlngs).getBounds(), { padding: [30, 30] });

        } catch (mapErr) {
            this._handleError('Map rendering failed.', mapErr);
        }
    }

    _renderWeatherMarkers(L) {
        if (!this._weatherAlerts) { return; }
        let alerts;
        try {
            alerts = JSON.parse(this._weatherAlerts);
        } catch (_) {
            return;
        }
        if (!Array.isArray(alerts)) { return; }

        alerts.forEach(alert => {
            if (!alert.lat || !alert.lng) { return; }
            const color = this._severityColor(alert.severity);
            const icon = L.divIcon({
                className: '',
                html: `<div style="background:${color};width:14px;height:14px;border-radius:50%;border:2px solid #fff;"></div>`,
                iconSize: [14, 14]
            });
            L.marker([alert.lat, alert.lng], { icon })
                .addTo(this._map)
                .bindPopup(alert.message ?? `Weather alert: ${alert.severity}`);
        });
    }

    _severityColor(severity) {
        const colors = { Low: '#2e7d32', Moderate: '#f57c00', High: '#c62828', Severe: '#6a1b9a' };
        return colors[severity] ?? '#546e7a';
    }

    _handleError(message, err) {
        this.isLoading     = false;
        this._errorMessage = message;
        console.error(`[logisticsMapCopado] ${message}`, err ?? '');
    }
}