// Tracking-issue state machine for the daily scheduled govulncheck run.
//
// Extracted from .github/workflows/govulncheck-scheduled.yml so the logic
// lives in a real, lintable, testable file and the workflow step stays a thin
// shim (mirrors scripts/scout-drift-sla.cjs in luthersystems/buildenv):
//
//   uses: actions/github-script@v7
//   with:
//     script: |
//       const run = require('./scripts/govulncheck-drift.cjs');
//       await run({ github, context, core });
//
// Inputs (env):
//   FOUND        'true' when the scan reported a reachable vulnerability
//   REPORT_PATH  path to the captured govulncheck output (default /tmp/govulncheck.txt)
//
// Behaviour:
//   - finding + no open issue   -> open one, labelled `govulncheck-drift`
//   - finding + issue already open -> add a comment (don't spam new issues)
//   - clean + issue open        -> comment and CLOSE it (auto-resolve on recovery)
//   - clean + no issue          -> no-op, stays quiet
//
// It reports only; it does not attempt a fix. govulncheck findings are
// reachability findings and the remedy is frequently a major-version migration
// rather than a version bump, so there is nothing safe to auto-apply.

const LABEL = 'govulncheck-drift';
const TITLE = 'govulncheck: reachable vulnerability on main';
const MAX_REPORT_BYTES = 50000;

module.exports = async ({ github, context, core }) => {
  const fs = require('fs');
  const found = process.env.FOUND === 'true';
  const reportPath = process.env.REPORT_PATH || '/tmp/govulncheck.txt';
  const { owner, repo } = context.repo;
  const runUrl = `${context.serverUrl}/${owner}/${repo}/actions/runs/${context.runId}`;

  const open = await github.rest.issues.listForRepo({
    owner,
    repo,
    state: 'open',
    labels: LABEL,
  });
  const existing = open.data[0];

  if (!found) {
    if (!existing) {
      core.info('govulncheck clean, no open drift issue — nothing to do.');
      return;
    }
    await github.rest.issues.createComment({
      owner,
      repo,
      issue_number: existing.number,
      body: `Scheduled govulncheck is clean as of ${runUrl} — closing.`,
    });
    await github.rest.issues.update({
      owner,
      repo,
      issue_number: existing.number,
      state: 'closed',
      state_reason: 'completed',
    });
    core.info(`Closed #${existing.number} on recovery.`);
    return;
  }

  let report = '';
  try {
    report = fs.readFileSync(reportPath, 'utf8').slice(-MAX_REPORT_BYTES);
  } catch (err) {
    core.warning(`Could not read ${reportPath}: ${err.message}`);
  }

  const body = [
    'Scheduled `govulncheck` found a reachable vulnerability on `main`.',
    '',
    'This is a **reachability** finding: govulncheck only reports when this',
    'module actually calls the vulnerable code, so it is not import-only noise.',
    '',
    `Run: ${runUrl}`,
    '',
    '<details><summary>Report</summary>',
    '',
    '```',
    report,
    '```',
    '',
    '</details>',
  ].join('\n');

  if (existing) {
    await github.rest.issues.createComment({
      owner,
      repo,
      issue_number: existing.number,
      body,
    });
    core.info(`Refreshed #${existing.number}.`);
    return;
  }

  const created = await github.rest.issues.create({
    owner,
    repo,
    title: TITLE,
    body,
    labels: [LABEL],
  });
  core.info(`Opened #${created.data.number}.`);
};
