/**
 * @description Pure scoring logic for Shipment delivery risk (US-0000519). Weights and thresholds come from
 * Shipment_Risk_Setting__mdt. Contains no SOQL or DML.
 */
public with sharing class ShipmentRiskScoringService_copado {
    private static final String STATUS_DELIVERED = 'Delivered';
    private static final String STATUS_CANCELLED = 'Cancelled';
    private static final Integer MAX_FACTORS_LENGTH = 2000;

    /**
     * @description Scoring weights and level thresholds.
     */
    public class Settings {
        public Integer daysWeight = 30;
        public Integer weatherWeight = 25;
        public Integer capacityWeight = 20;
        public Integer cargoWeight = 15;
        public Integer scheduledWeight = 10;
        public Integer mediumMin = 30;
        public Integer highMin = 60;
        public Integer criticalMin = 80;
    }

    /**
     * @description Loads settings from the Default custom metadata record, falling back to built-in defaults.
     * @return Settings instance
     */
    public static Settings loadSettings() {
        Settings s = new Settings();
        Shipment_Risk_Setting__mdt rec = Shipment_Risk_Setting__mdt.getInstance('Default');
        if (rec != null) {
            s.daysWeight = intOr(rec.Days_To_Delivery_Weight__c, s.daysWeight);
            s.weatherWeight = intOr(rec.Weather_Severity_Weight__c, s.weatherWeight);
            s.capacityWeight = intOr(rec.Capacity_Utilization_Weight__c, s.capacityWeight);
            s.cargoWeight = intOr(rec.Cargo_Type_Weight__c, s.cargoWeight);
            s.scheduledWeight = intOr(rec.Scheduled_No_Equipment_Weight__c, s.scheduledWeight);
            s.mediumMin = intOr(rec.Medium_Min_Score__c, s.mediumMin);
            s.highMin = intOr(rec.High_Min_Score__c, s.highMin);
            s.criticalMin = intOr(rec.Critical_Min_Score__c, s.criticalMin);
        }
        return s;
    }

    /**
     * @description Scores shipments in memory using settings from custom metadata.
     * @param shipments Shipments to score
     * @param routes Routes keyed by Id
     * @param equipment Equipment keyed by Id
     */
    public static void scoreShipments(List<Shipment__c> shipments, Map<Id, Route__c> routes, Map<Id, Equipment__c> equipment) {
        scoreShipments(shipments, routes, equipment, loadSettings());
    }

    /**
     * @description Scores shipments in memory using the supplied settings. Delivered and Cancelled are cleared.
     * @param shipments Shipments to score
     * @param routes Routes keyed by Id (may be null)
     * @param equipment Equipment keyed by Id (may be null)
     * @param cfg Settings to use
     */
    public static void scoreShipments(List<Shipment__c> shipments, Map<Id, Route__c> routes, Map<Id, Equipment__c> equipment, Settings cfg) {
        if (shipments == null) {
            return;
        }
        Datetime now = System.now();
        for (Shipment__c sh : shipments) {
            if (sh.Status__c == STATUS_DELIVERED || sh.Status__c == STATUS_CANCELLED) {
                sh.Risk_Score__c = null;
                sh.Risk_Level__c = null;
                sh.Risk_Factors__c = null;
                sh.Risk_Last_Calculated__c = null;
                continue;
            }
            Route__c route = (routes != null && sh.Route__c != null) ? routes.get(sh.Route__c) : null;
            Equipment__c eq = (equipment != null && sh.Equipment__c != null) ? equipment.get(sh.Equipment__c) : null;
            List<String> factors = new List<String>();
            Integer total = daysPoints(sh, cfg, factors) + weatherPoints(route, cfg, factors)
                + capacityPoints(sh, eq, cfg, factors) + cargoPoints(sh, cfg, factors) + scheduledPoints(sh, cfg, factors);
            total = Math.min(100, Math.max(0, total));
            sh.Risk_Score__c = total;
            sh.Risk_Level__c = determineLevel(total, cfg);
            String text = factors.isEmpty() ? 'No risk factors identified.' : String.join(factors, '\n');
            sh.Risk_Factors__c = text.length() > MAX_FACTORS_LENGTH ? text.substring(0, MAX_FACTORS_LENGTH) : text;
            sh.Risk_Last_Calculated__c = now;
        }
    }

    /**
     * @description Maps a score to a risk level.
     * @param score Score 0-100
     * @param cfg Settings with thresholds
     * @return Low, Medium, High or Critical
     */
    public static String determineLevel(Integer score, Settings cfg) {
        String level = 'Low';
        if (score >= cfg.criticalMin) {
            level = 'Critical';
        } else if (score >= cfg.highMin) {
            level = 'High';
        } else if (score >= cfg.mediumMin) {
            level = 'Medium';
        }
        return level;
    }

    private static Integer daysPoints(Shipment__c sh, Settings cfg, List<String> factors) {
        Integer pts = 0;
        if (sh.Expected_Delivery_Date__c != null) {
            Integer days = Date.today().daysBetween(sh.Expected_Delivery_Date__c);
            Integer pct = 0;
            if (days <= 1) {
                pct = 100;
            } else if (days <= 3) {
                pct = 75;
            } else if (days <= 7) {
                pct = 50;
            } else if (days <= 14) {
                pct = 25;
            }
            pts = points(cfg.daysWeight, pct);
            if (pts > 0) {
                factors.add((days < 0 ? 'Past due by ' + Math.abs(days) + ' day(s)' : days + ' day(s) to delivery') + ' (+' + pts + ')');
            }
        }
        return pts;
    }

    private static Integer weatherPoints(Route__c route, Settings cfg, List<String> factors) {
        Integer pts = 0;
        if (route != null && route.Weather_Severity__c != null) {
            Integer pct = 0;
            switch on route.Weather_Severity__c {
                when 'Extreme' { pct = 100; }
                when 'Severe' { pct = 80; }
                when 'High' { pct = 60; }
                when 'Moderate' { pct = 40; }
                when 'Unknown' { pct = 20; }
                when else { pct = 0; }
            }
            pts = points(cfg.weatherWeight, pct);
            if (pts > 0) {
                factors.add('Route weather ' + route.Weather_Severity__c + ' (+' + pts + ')');
            }
        }
        return pts;
    }

    private static Integer capacityPoints(Shipment__c sh, Equipment__c eq, Settings cfg, List<String> factors) {
        Integer pts = 0;
        if (eq != null && eq.Payload_Capacity_lbs__c != null && eq.Payload_Capacity_lbs__c > 0 && sh.Cargo_Weight_lbs__c != null) {
            Decimal util = sh.Cargo_Weight_lbs__c * 100 / eq.Payload_Capacity_lbs__c;
            Integer pct = 0;
            if (util >= 100) {
                pct = 100;
            } else if (util >= 90) {
                pct = 75;
            } else if (util >= 75) {
                pct = 50;
            } else if (util >= 50) {
                pct = 25;
            }
            pts = points(cfg.capacityWeight, pct);
            if (pts > 0) {
                factors.add('Capacity utilization ' + util.setScale(0) + '% (+' + pts + ')');
            }
        }
        return pts;
    }

    private static Integer cargoPoints(Shipment__c sh, Settings cfg, List<String> factors) {
        Integer pct = 0;
        if (sh.Cargo_Type__c == 'Hazmat') {
            pct = 100;
        } else if (sh.Cargo_Type__c == 'Refrigerated') {
            pct = 67;
        }
        Integer pts = points(cfg.cargoWeight, pct);
        if (pts > 0) {
            factors.add('Cargo type ' + sh.Cargo_Type__c + ' (+' + pts + ')');
        }
        return pts;
    }

    private static Integer scheduledPoints(Shipment__c sh, Settings cfg, List<String> factors) {
        Integer pts = 0;
        if (sh.Status__c == 'Scheduled' && sh.Equipment__c == null) {
            pts = cfg.scheduledWeight;
            if (pts > 0) {
                factors.add('Scheduled without equipment (+' + pts + ')');
            }
        }
        return pts;
    }

    private static Integer points(Integer weight, Integer pct) {
        return Math.round(weight * pct / 100.0);
    }

    private static Integer intOr(Decimal value, Integer fallback) {
        return value == null ? fallback : value.intValue();
    }
}