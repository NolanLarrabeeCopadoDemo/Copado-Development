@isTest
private class SimpleGreetingTest {
    @isTest
    static void testGetGreetingWithName() {
        // Test with a valid name
        String result = SimpleGreeting.getGreeting('John');
        System.assertEquals('Hello, John!', result, 'Should return greeting with name');
    }
    
    @isTest
    static void testGetGreetingWithBlankName() {
        // Test with blank name
        String result = SimpleGreeting.getGreeting('');
        System.assertEquals('Hello, Guest!', result, 'Should return guest greeting for blank name');
    }
    
    @isTest
    static void testGetGreetingWithNullName() {
        // Test with null name
        String result = SimpleGreeting.getGreeting(null);
        System.assertEquals('Hello, Guest!', result, 'Should return guest greeting for null name');
    }
}