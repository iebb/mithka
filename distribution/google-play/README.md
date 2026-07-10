# Google Play release metadata

The `release` branch builds and submits a signed Android App Bundle to the
Google Play production track. Localized release notes in `whatsnew/` are public
store metadata and are safe to version.

Private values are provided only through GitHub Actions secrets. In particular,
do not add service-account JSON, signing keystores, passwords, Telegram client
credentials, Firebase configuration, reviewer accounts, or one-time codes here.

The Play service account is stored as the `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
secret in the `google-play-production` GitHub environment. That environment is
restricted to deployments from the `release` branch.
