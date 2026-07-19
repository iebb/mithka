const sentryDsn = String.fromEnvironment('SENTRY_DSN');
const sentryEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'production',
);
const sentryTracesSampleRate = 0.02;

const sentryEnabled = sentryDsn != '';
