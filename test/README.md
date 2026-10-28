# Test scope

The default Flutter suite is deliberately small. It retains regressions for
account ownership, authentication and app locks, private data and consent,
destructive actions, payment entitlements, asynchronous cancellation, media
recovery, native callbacks, and representative composer/navigation flows.

Layout permutations, copy and style snapshots, benchmarks, implementation-string
assertions, and helper checks that duplicate those flows were pruned. Prefer a
regression that drives the production entry point over another check of widget
types, private state, or framework behavior. Add cases for a distinct failure
mode rather than repeating it across cosmetic variants.

Quality runs the entire retained suite with `flutter test --concurrency=4`, plus
formatting, analysis, localization generation checks and the trusted PR review
controller tests. The script suites under `test/scripts` protect store versions,
shipping SDK selection, artifact provenance and submission behavior.

The explicit default, false, invalid and true compile-time Terms guard runs in
`.github/workflows/quality.yml` remain required. Their focused files are also
part of the default discovery run. Do not remove those variants to shorten CI.

Apple PR verification separately runs the retained production glass captures,
credential-free device/simulator builds and native RunnerTests. Device-only
media smoke tests remain under `integration_test`; ordinary unit tests do not
establish device behavior.

Incoming PR validation runs in GitHub Actions. A passing reduced suite remains
one merge requirement alongside exact-head owner approval, current-master
merged-result evidence, completed checks and resolved review findings.
