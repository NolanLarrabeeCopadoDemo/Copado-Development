/**
 * Static utility that decodes Google-encoded polyline strings (as returned by
 * OpenRouteService's `geometry` field) into an ordered list of lat/lng
 * coordinate pairs, using the standard polyline algorithm: 5-bit chunks with a
 * continuation bit, zigzag delta encoding, scaled by 1e-5 (US-0000486).
 */
public with sharing class PolylineDecoderUtil_copado {

    private static final Decimal COORDINATE_PRECISION = 100000;
    private static final Integer ASCII_OFFSET = 63;
    private static final Integer CONTINUATION_BIT = 32;
    private static final Integer VALUE_MASK = 31;

    /** Thrown when an encoded polyline string is malformed and cannot be fully decoded. */
    public class PolylineDecoderException extends Exception {}

    /**
     * Decodes an encoded polyline string into a list of coordinate maps, each
     * containing 'lat' and 'lng' Decimal keys, in route order.
     * Returns an empty list for a null/blank input.
     */
    public static List<Map<String, Decimal>> decode(String encoded) {
        List<Map<String, Decimal>> coordinates = new List<Map<String, Decimal>>();
        if (String.isBlank(encoded)) {
            return coordinates;
        }

        List<Integer> chars = encoded.getChars();
        List<Integer> position = new List<Integer>{ 0 };
        Integer lat = 0;
        Integer lng = 0;

        while (position[0] < chars.size()) {
            lat += decodeNextValue(chars, position);
            lng += decodeNextValue(chars, position);

            Map<String, Decimal> point = new Map<String, Decimal>();
            point.put('lat', Decimal.valueOf(lat) / COORDINATE_PRECISION);
            point.put('lng', Decimal.valueOf(lng) / COORDINATE_PRECISION);
            coordinates.add(point);
        }

        return coordinates;
    }

    /**
     * Decodes a single zigzag-delta-encoded value starting at position[0],
     * advancing position[0] past the consumed characters. A single-element
     * list is used as a mutable index holder since Apex has no out params.
     */
    private static Integer decodeNextValue(List<Integer> chars, List<Integer> position) {
        Integer result = 0;
        Integer shift = 0;
        Integer chunk;

        do {
            if (position[0] >= chars.size()) {
                throw new PolylineDecoderException('Unexpected end of polyline string while decoding.');
            }
            chunk = chars[position[0]] - ASCII_OFFSET;
            position[0]++;
            result |= (chunk & VALUE_MASK) << shift;
            shift += 5;
        } while (chunk >= CONTINUATION_BIT);

        return ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
    }
}