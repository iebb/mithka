# Hosted PR review

Incoming PRs are reviewed by GitHub Actions, not a scheduled job on the
maintainer's computer. There is no PR-review cron. The separate nightly build
and release schedules are not changed by this workflow.

## Recommendations and authority

`PR Review` reads the current PR head, live master ref, complete file inventory,
patches, bounded head/master source, human review/comment feedback, unresolved
threads and current CI. It uses the current master `AGENTS.md`, not instructions
provided by a PR. Prior change requests are revisited on updated evidence.

The first LLM reviews the code. Both `ready` and source-grounded `request_changes`
answers get an independent challenge pass. A finding must quote current-head
code at an exact line; the controller mechanically verifies it against head
source or the added/context side of the current patch. Prior-review claims and
removed code are not current evidence. Unverifiable findings are downgraded to
human review, not asserted as blockers. A quotation proves location, not the
model's reasoning; a maintainer still needs to review the code.

Before a merge candidate is selected, both passes must return complete,
consistent JSON, agree on the allowed Terms classification, and report no
remaining findings. Models give advice in one updated bot comment; they never
create GitHub approvals, execute commands, modify PR code or close PRs.

The compile-time exception policy is unchanged. Every official/store build
remains compliant. Guarded-source PRs still require omitted/false/true evidence
and the full existing Quality gates. This automation change is
compliant/unchanged: it does not change Telegram behavior.

## Auto-merge gates

All of these must hold:

1. The PR is open, not draft, conflict-free and targets `iebb/mithka:master`.
2. The **actual iebb account (user ID 2127498)** has an `APPROVED` review on
   **this exact head**. A newer head, dismissal or later change request revokes
   eligibility. Comments, labels, display names and model answers are not
   approvals. An iebb-authored PR needs manual handling because GitHub does not
   allow self-approval.
3. The contribution template has one allowed Terms classification and all
   applicable basic/exception checks completed. All review threads are resolved,
   no reviewer still requests changes, and exact-head Quality and other current
   checks/statuses pass. Green CI alone never authorizes a merge.
4. Both model passes recommend `ready` with complete context. Oversized/binary
   or unavailable source, missing patches, malformed/truncated answers, missing
   credentials, outages and quotas fail closed. Generated localization
   catalogues are checked against their reviewed canonical XML by Quality.
5. Workflow/controller/policy/credential changes (including renames) are always
   manual-merge-only. The bot cannot expand its own authority.
6. The **separate ordinary `pull_request` Quality workflow** runs the complete existing Quality suite,
   formatting, analysis, localization/generated checks and all guarded define
   states on the actual synthetic merge commit. Before any PR code executes,
   the workflow verifies its parents equal the event's head and base. The
   workflow engine records merge/base/head in an immutable job name. The review
   controller checks that Actions job through the API, together with overall
   Quality success, and requires its base to equal **live master**, not stale
   `pull_request.base.sha` metadata. No PR artifacts, caches or step outputs are
   trusted as attestations. Quality uses `secrets_example.dart`, never real
   credentials. PR code never executes under a privileged trigger, even in a
   reduced-permission job. The normal fork/PR cache namespace remains isolated.
7. Immediately before publication, a fresh trusted job rechecks approval, head,
   master, reviews and that CI attestation, fetches the **exact tested merge SHA**, and verifies
   both parents again. It performs a normal fast-forward push to master. A racing
   master advance rejects the push; there is no force-push or speculative merge.
8. Remote master and GitHub's actual `MERGED` state are checked independently.
   Only post-merge **Quality** is dispatched because `GITHUB_TOKEN` pushes do not
   trigger ordinary push workflows. That dispatch is not proof the later run
   passed. Release/store/deployment workflows are never dispatched here.

These are this bot's merge gates, not a change to repository-wide branch rules
or the maintainer's ability to merge manually. A human can inspect the findings,
fix a PR and approve its updated head; an old request for changes is not a
permanent rejection. Larger/uncertain changes remain open for human revision.

## Events, deduplication and re-runs

PR open/synchronize/reopen/ready/description events, human PR comments, review
submission/dismissal/edits, review comments, completed Quality and master pushes
wake the controller. `PR Review Signal` carries review events from forks without
secrets, code checkout or artifacts; the privileged controller always re-reads
live GitHub data rather than trusting signal outputs.

The controller serializes runs and inspects up to five most recently updated
open PRs per general event; PR/comment events target their specific PR. A fingerprint includes current head/master, policy,
description, human feedback, approval/thread state and CI results. Identical
evidence produces no repeated model request or comment. A cached comment can
**never authorize a merge**. Bot chatter does not retrigger inference.

Use Actions → **PR Review** → **Run workflow**, optionally selecting a PR number,
to force a fresh assessment after provider recovery or for an older PR outside
the per-event batch. No local review daemon or schedule is needed.

PRs whose last Quality run predates the merge-identity job need a new PR Quality
run containing the updated base workflow before auto-merge. A missing identity
is not treated as a pass; old green CI cannot substitute for the current merge.

## Credentials, cost and trust boundary

The repository Actions secret is `OPENROUTER_API_KEY`. It is injected only into
the trusted inference step. Set/rotate it in GitHub Settings → Secrets and
variables → Actions, or with an interactive `gh secret set OPENROUTER_API_KEY
--repo iebb/mithka`. Never put keys in source, PRs, prompts, comments or logs.

The review prefers NVIDIA Nemotron free variants, and the challenge prefers
Google Gemma free variants (to avoid simply repeating one model family).
Availability fallbacks are exclusively `:free` models and `openrouter/free`,
with maximum prompt, completion, request and image prices all zero. There are
no paid fallbacks, paid plugins, web search, model tools or automatic top-ups.
Each fresh PR uses one API call, or two for a ready/grounded-change decision;
provider fallbacks may count additional quota attempts. The output budget is
8,192 tokens with low reasoning effort so reasoning does not consume the entire
answer before producing JSON. Cut-off answers still fail closed.
In-progress Quality waits without consuming inference
quota. Non-collecting providers are required (`data_collection: deny`); if no
eligible free provider is available, the PR stays open.

The public diff and bounded review context are sent to OpenRouter and the
selected free provider; the model/API credentials are not. Credential-like
filenames are excluded, common key formats and registered keys are redacted.
Untrusted PR text remains data, never workflow expressions or shell input.
Privileged jobs check out master only, do not consume PR artifacts/caches and
cannot run PR scripts. Actual test execution happens solely in credential-free,
read-only GitHub-hosted jobs. Other automations, Telegram accounts and release
systems are outside this controller's scope.

References: [OpenRouter free routing](https://openrouter.ai/docs/guides/routing/routers/free-router),
[provider price/data controls](https://openrouter.ai/docs/guides/routing/provider-selection),
[GitHub privileged-trigger security](https://docs.github.com/en/actions/reference/security/secure-use).

## Controller validation

No third-party Node packages are needed. Run:

```sh
node --test .github/scripts/pr-review.test.mjs
actionlint .github/workflows/pr-review.yml .github/workflows/pr-review-signal.yml .github/workflows/quality.yml
git diff --check
```

The regression suite covers exact-head identity/approval, dismissal, spoofing,
checklist/Terms gates, CI provenance, source completeness, prompt-injection data
boundaries, mechanically grounded current-head citations (not removed or
historical code), free-only routing, provider/JSON failures, duplicate suppression,
two-pass decisions, in-flight ownership changes, exact merge parents, normal
push races, authoritative state readback and Quality-only post-merge dispatch.
