@isTest
private class PolylineDecoderUtilTest_copado {

    // -----------------------------------------------------------------------
    // 1. NULL / BLANK INPUT GUARDS
    // -----------------------------------------------------------------------

    @isTest
    static void testNullInputReturnsEmptyList() {
        Test.startTest();
        List<Map<String, Decimal>> result = PolylineDecoderUtil_copado.decode(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Null input should return an empty list, not null.');
        System.assertEquals(0, result.size(), 'Null input should yield zero decoded points.');
    }

    @isTest
    static void testBlankInputReturnsEmptyList() {
        Test.startTest();
        List<Map<String, Decimal>> result = PolylineDecoderUtil_copado.decode('   ');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size(), 'Blank/whitespace input should yield zero decoded points.');
    }

    @isTest
    static void testEmptyStringReturnsEmptyList() {
        Test.startTest();
        List<Map<String, Decimal>> result = PolylineDecoderUtil_copado.decode('');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Empty string should yield zero decoded points.');
    }

    // -----------------------------------------------------------------------
    // 2. KNOWN POLYLINE DECODING - SINGLE POINT
    // -----------------------------------------------------------------------

    @isTest
    static void testDecodeSingleKnownPoint() {
        // Encoded polyline for a single point at approximately (38.5, -120.2).
        // Encoded value: "_p~iF~ps|U" decodes to (38.5, -120.2).
        String encoded = '_p~iF~ps|U';

        Test.startTest();
        List<Map<String, Decimal>> result = PolylineDecoderUtil_copado.decode(encoded);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected exactly 1 decoded coordinate.');
        Map<String, Decimal> point = result[0];
        System.assert(point.containsKey('lat'), 'Decoded point must contain lat key.');
        System.assert(point.containsKey('lng'), 'Decoded point must contain lng key.');

        // Allow a small tolerance for floating-point rounding in the 1e-5 scale.
        Decimal lat = point.get('lat');
        Decimal lng = point.get('lng');
        System.assert(lat >= 38.4 && lat <= 38.6, 'Latitude should be approximately 38.5, got: ' + lat);
        System.assert(lng >= -120.3 && lng <= -120.1, 'Longitude should be approximately -120.2, got: ' + lng);
    }

    // -----------------------------------------------------------------------
    // 3. KNOWN POLYLINE DECODING - MULTI-POINT (GOOGLE EXAMPLE)
    // -----------------------------------------------------------------------

    @isTest
    static void testDecodeGoogleExampleMultiPoint() {
        // Classic Google documentation example: three points.
        // _p~iF~ps|U_ulLnnqC_mqNvxq`@
        // Decodes to: (38.5,-120.2), (40.7,-120.95), (43.252,-126.453)
        String encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

        Test.startTest();
        List<Map<String, Decimal>> result = PolylineDecoderUtil_copado.decode(encoded);
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Expected 3 decoded coordinates from the Google example.');

        // Point 0: (38.5, -120.2)
        System.assert(result[0].get('lat') >= 38.4 && result[0].get('lat') <= 38.6);
        System.assert(result[0].get('lng') >= -120.3 && result[0].get('lng') <= -120.1);

        // Point 1: (40.7, -120.95)
        System.assert(result[1].get('lat') >= 40.6 && result[1].get('lat') <= 40.8);
        System.assert(result[1].get('lng') >= -121.05 && result[1].get('lng') <= -120.85);

        // Point 2: (43.252, -126.453)
        System.assert(result[2].get('lat') >= 43.15 && result[2].get('lat') <= 43.35);
        System.assert(result[2].get('lng') >= -126.55 && result[2].get('lng') <= -126.35);
    }

    // -----------------------------------------------------------------------
    // 4. NEGATIVE COORDINATE HANDLING (ZIGZAG ENCODING)
    // -----------------------------------------------------------------------

    @isTest
    static void testDecodeNegativeCoordinateHandledByZigzag() {
        // The decoder uses zigzag encoding which must correctly handle negative
        // delta values. Longitude values west of the prime meridian are negative.
        // A single known US point near Denver: approx (39.74, -104.98).
        // Encoded with standard Google polyline algo: "e{aeFd|{hT" (approx).
        String encoded = '_p~iF~ps|U'; // verified point at (38.5,-120.2)

        Test.startTest();
        List<Map<String, Decimal>> result = PolylineDecoderUtil_copado.decode(encoded);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assert(result[0].get('lng') < 0, 'Longitude for US coordinate must be negative (west of prime meridian).');
    }

    // -----------------------------------------------------------------------
    // 5. MALFORMED POLYLINE THROWS PolylineDecoderException
    // -----------------------------------------------------------------------

    @isTest
    static void testMalformedPolylineThrowsDecoderException() {
        // A trailing tilde character "~" has a continuation bit set but no
        // subsequent byte, making it a structurally invalid polyline.
        String malformed = '~';
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            PolylineDecoderUtil_copado.decode(malformed);
        } catch (PolylineDecoderUtil_copado.PolylineDecoderException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'A malformed polyline should throw PolylineDecoderException.');
    }

    // -----------------------------------------------------------------------
    // 6. EACH DECODED POINT HAS EXACTLY 'lat' AND 'lng' KEYS
    // -----------------------------------------------------------------------

    @isTest
    static void testEachDecodedPointHasLatAndLngKeys() {
        String encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

        Test.startTest();
        List<Map<String, Decimal>> result = PolylineDecoderUtil_copado.decode(encoded);
        Test.stopTest();

        for (Map<String, Decimal> point : result) {
            System.assert(point.containsKey('lat'), 'Each decoded point must contain the lat key.');
            System.assert(point.containsKey('lng'), 'Each decoded point must contain the lng key.');
            System.assertNotEquals(null, point.get('lat'), 'lat value must not be null.');
            System.assertNotEquals(null, point.get('lng'), 'lng value must not be null.');
        }
    }

    // -----------------------------------------------------------------------
    // 7. LARGE POLYLINE DOES NOT HIT GOVERNOR LIMITS
    // -----------------------------------------------------------------------

    @isTest
    static void testLargePolylineDoesNotHitGovernorLimits() {
        // Repeat a known valid 3-point polyline multiple times to simulate
        // a long-route polyline with many coordinates. The decoder processes
        // delta-encoded values, so repeating produces cumulative coordinate shifts
        // but exercises the loop for governor-limit validation.
        String threePoint = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
        String longEncoded = '';
        for (Integer i = 0; i < 50; i++) {
            longEncoded += threePoint;
        }

        Test.startTest();
        List<Map<String, Decimal>> result = PolylineDecoderUtil_copado.decode(longEncoded);
        Test.stopTest();

        // 50 repetitions x 3 points = 150 decoded coordinates expected.
        System.assertEquals(150, result.size(), 'Repeated 3-point polyline x50 should yield 150 decoded points.');
    }

    // -----------------------------------------------------------------------
    // 8. PRECISION: COORDINATES SCALED BY 1E-5
    // -----------------------------------------------------------------------

    @isTest
    static void testCoordinatePrecisionIsScaledByOnePowerOfFive() {
        // All decoded lat/lng values must be in degree range, not raw integers.
        String encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

        Test.startTest();
        List<Map<String, Decimal>> result = PolylineDecoderUtil_copado.decode(encoded);
        Test.stopTest();

        for (Map<String, Decimal> point : result) {
            Decimal lat = point.get('lat');
            Decimal lng = point.get('lng');
            System.assert(lat >= -90 && lat <= 90, 'Latitude out of valid degree range: ' + lat);
            System.assert(lng >= -180 && lng <= 180, 'Longitude out of valid degree range: ' + lng);
        }
    }
}