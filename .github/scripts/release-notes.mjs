// Nightly package release notes. No inference happens here: the notes are the
// validated summary that the canonical master sync recorded for this exact
// source commit. Without one, the release says so and links the full changelog.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { display, validateNotes } from './nightly-summary.mjs';

const REPO = 'iebb/mithka';
const SHA = /^[a-f0-9]{40}$/;
const TAG = /^v\d+\.\d+\.\d+(?:-nightly\.\d+\.[a-f0-9]+)?$/;
const ROOT = `https://github.com/${REPO}`;
const ARTIFACT = 'nightly-release-summary';
const gh = args => execFileSync('gh', args, {
  encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60_000, maxBuffer: 4_000_000,
});

export function verifiedSummary(provenance, notes, target) {
  if (!SHA.test(target ?? '') || provenance?.target !== target || provenance.status !== 'generated') return null;
  if (provenance.tag !== null && !TAG.test(provenance.tag ?? '')) return null;
  try { return { tag: provenance.tag, notes: validateNotes(notes) }; } catch { return null; }
}

export function renderReleaseNotes(summary, { releaseTag, target, compareLabel, compareUrl }) {
  const lines = ['## Changes', '### English'];
  if (summary) {
    lines.push(...summary.notes.english.map(line => `- ${display(line)}`), '',
      '### 中文', ...summary.notes.chinese.map(line => `- ${display(line)}`));
  } else {
    lines.push("- No release summary was recorded for this build; see the full changelog for its changes.", '',
      '### 中文', '- 本次构建没有记录发布摘要；具体变更请参阅完整变更记录。');
  }
  // Link the same range the summary describes.
  if (summary?.tag) {
    compareLabel = `${summary.tag}...${releaseTag}`;
    compareUrl = `${ROOT}/compare/${summary.tag}...${releaseTag}`;
  } else if (summary) {
    compareLabel = `${releaseTag} commit`;
    compareUrl = `${ROOT}/commit/${target}`;
  }
  lines.push('', '', `**Full changelog:** [${compareLabel}](${compareUrl})`);
  return lines.join('\n') + '\n';
}

// Newest canonical master sync run whose summary covers `target`. Waits briefly
// while sync runs are still finishing, since the summary job runs after dispatch.
export async function findSummary(target, {
  run = gh, sleep = ms => new Promise(resolve => setTimeout(resolve, ms)), attempts = 10, interval = 30_000,
} = {}) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const runs = JSON.parse(run(['api', `repos/${REPO}/actions/workflows/sync-nightly.yml/runs?branch=master&per_page=10`])).workflow_runs ?? [];
    let pending = false;
    for (const sync of runs) {
      if (sync.head_branch !== 'master' || sync.repository?.full_name !== REPO ||
          !['schedule', 'workflow_dispatch'].includes(sync.event)) continue;
      if (sync.status !== 'completed') { pending = true; continue; }
      const dir = mkdtempSync(join(tmpdir(), 'mithka-release-summary-'));
      try {
        run(['run', 'download', String(sync.id), '-R', REPO, '-n', ARTIFACT, '-D', dir]);
        const provenance = JSON.parse(readFileSync(join(dir, 'provenance.json'), 'utf8'));
        if (provenance.target !== target) continue;
        const notesPath = join(dir, 'notes.json');
        const notes = existsSync(notesPath) ? JSON.parse(readFileSync(notesPath, 'utf8')) : null;
        const summary = verifiedSummary(provenance, notes, target);
        if (summary) return summary;
      } catch { /* Runs without a summary artifact, or with an expired one, are skipped. */ }
      finally { rmSync(dir, { recursive: true, force: true }); }
    }
    if (!pending) return null;
    if (attempt + 1 < attempts) await sleep(interval);
  }
  return null;
}

async function main() {
  const { RELEASE_TAG: releaseTag, SOURCE_COMMIT: target, COMPARE_LABEL: compareLabel, COMPARE_URL: compareUrl } = process.env;
  let summary = null;
  try {
    if (process.env.GITHUB_REPOSITORY === REPO) summary = await findSummary(target);
  } catch { /* The release still publishes, with the honest unavailable note. */ }
  writeFileSync('release-notes.md', renderReleaseNotes(summary, { releaseTag, target, compareLabel, compareUrl }));
  console.log(summary ? 'Using the nightly release summary recorded for this source commit.'
    : 'No nightly release summary was recorded for this source commit.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
