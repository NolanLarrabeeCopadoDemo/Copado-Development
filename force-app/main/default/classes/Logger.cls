public with sharing class Logger {

    public static void error(String context, Exception ex) {
        String exceptionDetail = ex == null ? 'null' : ex.getMessage() + ' | ' + ex.getStackTraceString();
        System.debug(LoggingLevel.ERROR, buildLogLine(context, exceptionDetail));
    }

    public static void error(String context, String message) {
        System.debug(LoggingLevel.ERROR, buildLogLine(context, message));
    }

    private static String buildLogLine(String context, String detail) {
        String safeContext = String.isBlank(context) ? 'Unknown' : context;
        String safeDetail = String.isBlank(detail) ? '' : detail;
        return safeContext + ': ' + safeDetail;
    }
}