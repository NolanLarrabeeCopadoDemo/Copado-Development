import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELD_WEATHER_ALERTS_JSON = 'Route__c.Weather_Alerts_JSON__c';
const FIELD_WEATHER_SEVERITY    = 'Route__c.Weather_Severity__c';
const FIELD_WEATHER_CHECKED_DT  = 'Route__c.Weather_Checked_DateTime__c';

const ROUTE_FIELDS = [
    FIELD_WEATHER_ALERTS_JSON,
    FIELD_WEATHER_SEVERITY,
    FIELD_WEATHER_CHECKED_DT
];

const SEVERE_BANNER_TRIGGER = 'Severe';

const WMO_CODE_DESCRIPTIONS = {
    0:  'Clear sky',
    1:  'Mainly clear',
    2:  'Partly cloudy',
    3:  'Overcast',
    45: 'Fog',
    48: 'Depositing rime fog',
    51: 'Light drizzle',
    53: 'Moderate drizzle',
    55: 'Dense drizzle',
    56: 'Light freezing drizzle',
    57: 'Dense freezing drizzle',
    61: 'Slight rain',
    63: 'Moderate rain',
    65: 'Heavy rain',
    66: 'Light freezing rain',
    67: 'Heavy freezing rain',
    71: 'Slight snow fall',
    73: 'Moderate snow fall',
    75: 'Heavy snow fall',
    77: 'Snow grains',
    80: 'Slight rain showers',
    81: 'Moderate rain showers',
    82: 'Violent rain showers',
    85: 'Slight snow showers',
    86: 'Heavy snow showers',
    95: 'Thunderstorm',
    96: 'Thunderstorm with slight hail',
    99: 'Thunderstorm with heavy hail'
};

const SEVERITY_BADGE_CLASS_MAP = {
    Low:      'slds-theme_success',
    Moderate: 'slds-theme_warning',
    High:     'slds-theme_warning',
    Severe:   'slds-theme_error',
    Extreme:  'slds-theme_error',
    Unknown:  'slds-theme_shade'
};

const DEFAULT_BADGE_CLASS = 'slds-theme_shade';

/**
 * @description LWC component that renders per-waypoint weather data for a Route__c record.
 *              Displays temperature, precipitation, wind speed, WMO description, and a
 *              severity badge per waypoint. Shows a Severe Alert banner when severity
 *              equals "Severe". Follows the -copado naming convention per dev standards.
 *
 * @author      Nolan Larrabee
 * @story       US-0000491
 */
export default class WeatherDashboardCopado extends LightningElement {
    @api recordId;

    _weatherAlertsJson;
    _weatherSeverity;
    _weatherCheckedDateTime;
    errorMessage;

    @wire(getRecord, { recordId: '$recordId', fields: ROUTE_FIELDS })
    wiredRoute({ data, error }) {
        if (data) {
            this.errorMessage            = undefined;
            this._weatherAlertsJson      = data.fields.Weather_Alerts_JSON__c?.value ?? undefined;
            this._weatherSeverity        = data.fields.Weather_Severity__c?.value ?? undefined;
            this._weatherCheckedDateTime = data.fields.Weather_Checked_DateTime__c?.value ?? undefined;
        } else if (error) {
            this.errorMessage            = error?.body?.message ?? 'Unable to load weather data.';
            this._weatherAlertsJson      = undefined;
            this._weatherSeverity        = undefined;
            this._weatherCheckedDateTime = undefined;
        }
    }

    get showSevereAlertBanner() {
        return this._weatherSeverity === SEVERE_BANNER_TRIGGER;
    }

    get lastUpdatedDisplay() {
        if (!this._weatherCheckedDateTime) {
            return 'Not yet checked';
        }
        return new Date(this._weatherCheckedDateTime).toLocaleString();
    }

    get hasWaypoints() {
        return this.waypointCards.length > 0;
    }

    get waypointCards() {
        return this._parsedWeatherAlerts.map((entry, index) =>
            this._buildCardData(entry, index)
        );
    }

    get _parsedWeatherAlerts() {
        if (!this._weatherAlertsJson) {
            return [];
        }
        try {
            const parsed = JSON.parse(this._weatherAlertsJson);
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            return [];
        }
    }

    _buildCardData(entry, index) {
        const severityValue = entry.severity || this._weatherSeverity || 'Unknown';
        return {
            key:                    entry.waypointName ? `${entry.waypointName}-${index}` : `waypoint-${index}`,
            waypointName:           entry.waypointName           || `Waypoint ${index + 1}`,
            temperature:            entry.temperature            != null ? entry.temperature : 'N/A',
            precipitation:          entry.precipitation          != null ? entry.precipitation : 'N/A',
            windSpeed:              entry.windSpeed              != null ? entry.windSpeed : 'N/A',
            weatherCodeDescription: this._describeWmoCode(entry.weatherCode),
            severity:               severityValue,
            severityBadgeClass:     this._severityBadgeClass(severityValue)
        };
    }

    _describeWmoCode(code) {
        if (code === undefined || code === null) {
            return 'Unknown conditions';
        }
        return WMO_CODE_DESCRIPTIONS[code] || 'Unknown conditions';
    }

    _severityBadgeClass(severityValue) {
        const themeClass = SEVERITY_BADGE_CLASS_MAP[severityValue] || DEFAULT_BADGE_CLASS;
        return `slds-badge ${themeClass}`;
    }
}