# Google Play release metadata

The `release` branch builds and submits a signed Android App Bundle to the
Google Play production track. Localized release notes in `whatsnew/` are public
store metadata and are safe to version.

To publish manually, open [Google Play Release](https://github.com/iebb/mithka/actions/workflows/google-play.yml),
select `master`, and click **Run workflow**. This builds and submits the selected
master commit to **production** after Quality passes, using the version in
`pubspec.yaml` and its immutable Android version code. A successful upload is
recorded with a `play-version-code-*` tag. Reruns and duplicate publication
attempts for the same commit remain blocked; use a new release commit or promote
the existing Play artifact instead. Automatic `release` production and `nightly`
beta publication keep their existing behavior.

Private values are provided only through GitHub Actions secrets. In particular,
do not add service-account JSON, signing keystores, passwords, Telegram client
credentials, Firebase configuration, reviewer accounts, or one-time codes here.

The Play service account is stored as the `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
secret in the `google-play-production` GitHub environment. That environment is
restricted to the `master`, `release` and `nightly` branches. Android signing,
Telegram and Firebase credentials remain repository secrets.

Use [Store Workflow Checks](https://github.com/iebb/mithka/actions/workflows/store-checks.yml)
on `master` to verify app access without submitting a release. The check creates
an uncommitted edit, reads the available tracks, then deletes that edit.
