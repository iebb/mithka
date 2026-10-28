# App Store review from GitHub

The [iOS TestFlight](https://github.com/iebb/mithka/actions/workflows/ios-testflight.yml)
and [macOS TestFlight](https://github.com/iebb/mithka/actions/workflows/macos-testflight.yml)
workflows build, sign and upload binaries. App Review is a separate manual step:

1. Open [App Store Review Submission](https://github.com/iebb/mithka/actions/workflows/app-store-submit.yml), select `master`, and click **Run workflow**.
2. Select `IOS` or `MAC_OS`, the listing version, exact binary version/build number and full source commit SHA.
3. For `github_actions`, provide the completed upload workflow run ID and the ASC build UUID. For `xcode_cloud`, provide the Xcode Cloud run UUID and leave the ASC build UUID empty. The existing release verifier checks the selected build's app, platform, version, source provenance, processing state and App Store eligibility.
4. Provide the path to a committed release-notes JSON under `distribution/app-store/`, containing exactly `en-US` and `zh-Hans` text. For example: `distribution/app-store/release-notes-1.7.11.json`. Use release notes appropriate to the selected version.
5. Run `validate` first. It plans the review submission without changing ASC. Select `submit` to create/update the listing, attach that exact build, copy the existing review details and metadata, and submit to App Review. The workflow verifies the resulting version and review-submission state. New versions use the existing release script's `AFTER_APPROVAL` behavior.

The workflow runs the full Quality gate on the exact uploaded `source_commit`
before accessing ASC credentials, plus tests for the current submission code.
Only a canonical master App Review dispatch may select a source override, and
that source must be an ancestor of master. PR and push checks keep their event
SHA and merge-identity checks. Release-source checks have a distinct job name
so they cannot substitute for current-head PR evidence.
Empty release notes in additional inherited listing locales receive the en-US
text. Existing translations in those locales are preserved.
It never selects a build merely because it is the latest upload.
Completed historical submissions whose items for the selected version were
removed are ignored. Multiple remaining submissions still block publication.

Required repository secrets are `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID` and `APP_STORE_CONNECT_PRIVATE_KEY` (raw `.p8`
contents). Existing build/signing workflows continue to use their Apple signing,
Telegram and Firebase secrets. Keys are written only to a temporary file on the
runner and deleted when the step exits.

Run [Store Workflow Checks](https://github.com/iebb/mithka/actions/workflows/store-checks.yml)
on `master` to test both store credentials. It performs an ASC app lookup and a
Play track lookup using a temporary edit that is deleted without committing.
Pull-request and push runs execute only offline tests and workflow validation.

## Friday releases

[Friday Store Release](https://github.com/iebb/mithka/actions/workflows/weekly-store-release.yml)
runs every Friday at **09:00 Asia/Tokyo (00:00 UTC)**. It can also be dispatched
from `master`: `plan` is the default and never publishes a version or submits
an app; `release` performs the signed builds and store submissions.

The coordinator reads live ASC/TestFlight and Play state, preserves the full
normal `X.Y.Z` version, and increments the patch when the current number has
already been used. It never changes a normal patch to `.0`. It advances only
within master's current major/minor train. A new release snapshot updates only
`pubspec.yaml`, the shared Android version code and versioned bilingual release
notes. Curated notes at that version's path are retained; otherwise the fallback
notes describe app maintenance without inventing feature claims.

An atomic fast-forward publication creates immutable `store-vX.Y.Z`,
`store-YYYY-MM-DD` and canonical `vX.Y.Z` tags. The annotated date tag records the source SHA, exact
version, Android code and Apple build number. The date uses Tokyo time. Use the
same `release_key` to resume an interrupted release: the coordinator reuses the
recorded snapshot and existing child workflow runs. It stops on a failed or
ambiguous publication instead of dispatching another upload with a reused code.
Resolve that attempt explicitly before resuming; do not rewrite release tags.
After the actual Play/ASC postconditions pass, a `store-complete-YYYY-MM-DD`
tag records completion after master advances to the next minor's development
version (`1.N.Z` submitted → `1.(N+1).0` on master). The bump increments build
metadata and allocates a fresh shared Android code, preserving app changes
and the submitted snapshot. It is idempotent and refuses to replace another
newly selected patch version. The coordinator also publishes the matching stable
GitHub `vX.Y.Z` release: two Android APKs, Windows x64/arm64 archives and installers,
macOS universal, and Linux x64/arm64 archives and AppImages. Every package is built
from the immutable store snapshot, with a source/version/checksum manifest.
The release stays a draft until all package digests are verified. The new minor
on master is never substituted for the submitted patch or the GitHub version.
A later Friday resumes a unique unfinished snapshot
before allocating another patch. Multiple unfinished snapshots require
reconciliation.
Publication/completion markers created by Actions point to the current
`master` controller commit. Their immutable JSON annotations contain the
actual `source_sha` of the built snapshot. This avoids requesting permission
to rewrite workflow files just to tag an older snapshot. Legacy Play markers
that point directly to the source remain valid. A Play marker-only failure can
be repaired only after the exact upload and Quality jobs succeeded and a
separate API lookup verified the expected completed production code; the AAB
is never uploaded again for that repair.

Both Apple builds must pass Quality, signing, processing and App Store
eligibility. Both App Review plans are validated before Play production is
published, then iOS/macOS are submitted sequentially and their actual store
states are checked. A unique older `PREPARE_FOR_SUBMISSION` draft is advanced
in place, preserving screenshots, listing metadata and review details, with
release after approval. An active review or an ambiguous draft is left for the
maintainer. Store review can still delay public availability after submission.

The scheduler shares the nightly version allocator's lock; Play state lookups
share the existing Play publication lock. Upload-only Apple builds skip beta
distribution and keep every official-build Terms guard disabled. The
coordinator dispatches the multi-platform package workflow with an exact source;
that store mode skips Telegram notifications and never moves an existing tag.
It does not install a schedule on the maintainer's computer. New release
snapshots require current master Quality before reserving their version tags;
resuming an already-tested snapshot continues to validate that exact source.

If only the GitHub release API step fails after Quality and all seven package
builders pass, the coordinator can dispatch
[Recover Store GitHub Publication](https://github.com/iebb/mithka/actions/workflows/github-store-publish.yml).
It verifies the exact original workflow/source, all jobs and eleven immutable
artifacts, then uploads those artifacts without rebuilding or resubmitting to
stores. Any test/build failure blocks this path. Recovery has its own immutable
intent, and partial drafts resume only when existing asset digests agree.
The API uses `master` as `target_commitish` to avoid requesting workflow-write
permission for an older source. The existing verified `vX.Y.Z` tag stays on
the submitted source; the tag and release manifest determine the actual source.
Drafts are looked up through authenticated listing and verified by release ID;
the tag lookup endpoint exposes published releases only. A corrected publisher
may resume a known failed attempt under a new immutable retry intent. Existing
manifest bytes retain their initial upload identity when all source, original
build, version and package digests match; no package or manifest is overwritten.
