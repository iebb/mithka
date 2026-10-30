## Change

Describe the problem, resulting behavior, and affected platforms. Link related issues if applicable.

Use one PR per feature, fix, or improvement in this repository. Search existing
open and recently closed PRs first, and update the existing PR for revisions,
tests, documentation, and CI. Link any related PRs below and explain why each is
independently useful; consolidate same-topic submissions into one canonical PR.

Related PRs and canonical PR (or `None; existing PRs checked`):

## Telegram API Terms classification

Follow the [contribution and agentic review rules](https://github.com/iebb/mithka/blob/master/AGENTS.md#contributions-and-agentic-pr-review). Select exactly one classification and explain it below.

This is an agentic source-code review classification. Every store version must remain compliant with applicable Telegram API Terms; the guarded-source exception does not apply to store distribution or review.

- [ ] Compliant/unchanged: this change complies with applicable Telegram API Terms, preserves Telegram's basic functionality, and does not introduce behavior covered by section 1.4.
- [ ] Section 1.4 exception: the entire feature is guarded by `allowTelegramTosViolations` (`I_DONT_FUCKING_CARE_ABOUT_TOS`), disabled in official builds, and available only in an explicitly enabled self-build.
- [ ] Disallowed or unresolved: this PR must not be approved or merged until its classification and implementation are resolved.

Reason and affected Telegram behavior:

## Basic checks (every PR)

Check each item after verification. If a check is inapplicable, explain why in the evidence below before checking it.

- [ ] I reviewed the diff for correctness, unintended behavior, secrets, and unrelated changes.
- [ ] Formatting passed, or I recorded why it is inapplicable: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver`.
- [ ] Analysis passed, or I recorded why it is inapplicable: `flutter analyze`.
- [ ] Relevant tests passed, or I recorded why they are inapplicable; name the commands and test cases below. Quality CI runs `flutter test --concurrency=4`.
- [ ] I checked affected build/platform paths and applicable localization/generated files; list the evidence below.
- [ ] I completed the Terms classification above and verified that official builds cannot enable section 1.4 exceptions.

Commands, results, platform/build/UI evidence, and reasons for inapplicable checks:

## Section 1.4 exception checks

Complete every item for an exception. For a compliant/unchanged PR, write `Not applicable` here.

- [ ] All UI, routes, commands, callbacks, background work, TDLib/native effects, and registrations use the compile-time guard; a runtime preference alone cannot enable the feature.
- [ ] With the flag omitted, the feature is absent and ordinary Telegram behavior remains intact, including with old saved settings.
- [ ] With `--dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=false`, the feature is absent and ordinary Telegram behavior remains intact.
- [ ] With `--dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true`, the feature works through the guarded entry points in a self-build; I included relevant test and build/UI evidence.
- [ ] Official release, nightly, TestFlight, and store builds keep the flag `false` and have no option that enables it. All store versions remain compliant with applicable Telegram API Terms.

Guard locations and evidence for each flag variant:

## Agentic reviewer confirmation

Agentic code reviewer only: record this confirmation in the PR review or check these boxes before approval.

- [ ] I independently confirmed the Terms classification and inspected all required guards and evidence.
- [ ] Applicable checks and Quality CI pass; no unresolved classification or unguarded section 1.4 behavior remains.
