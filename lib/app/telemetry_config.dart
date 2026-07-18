const sentryDsn = String.fromEnvironment('SENTRY_DSN');
const sentryEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'production',
);

const sentryEnabled = sentryDsn != '';
