/*
 * remote-tailnet-guard - HOST half source of record (t5 deliverable, landed for t16 F4).
 *
 * LAST UPDATED : 2026-09-24 (t16 repair-round-2)
 * AUTHOR       : team remote-tailnet-guard-2 (member "smith", tasks t5 + t16)
 *
 * WHY THIS FILE EXISTS (review finding F4)
 *   The t5 host half only ever existed inside the dynamic Cordis package, so nobody could review
 *   its disposer or the claim that stopping the package also terminates a running child. This file
 *   is that source, on disk, greppable and hashable.
 *
 * SNAPSHOT STATE (important, measured)
 *   The dynamic package this file corresponds to is guard-1/pkg-4. It is NOT running now:
 *   cordis_inspect_self() returns {"mode":"plugins","plugins":[]} after the DSH process restarted,
 *   because dynamic packages live in process memory and are never written to disk. Re-activate per
 *   docs/install/install.md section 1, then verify with cordis_inspect_self().
 *
 * WHAT IT REGISTERS (all on ctx.effect, so cordis_stop removes everything)
 *   - Service  : remoteTailnetGuard  (ctx.provide)
 *   - RPC      : remote-tailnet-guard/posture          (harness.handle, package-private)
 *   - Tool     : remote_tailnet_posture                (harness.defineTool + harness.registerTool)
 *   The effect disposer also calls activeHandle.terminate() on a still-running collector child.
 *
 * CLI vs PLUGIN SPAWN COUNTS (asked for by the t16 repair list)
 *   Measured difference between running the collector by hand and letting this host half spawn it:
 *   the two do NOT produce identical verdicts on the same machine, and the reason is a Windows
 *   sandbox/integrity asymmetry rather than a collector bug:
 *     - CLI (agent session):  `tailscale ip -4` exits 1 with
 *       "open \\.\pipe\ProtectedPrefix\Administrators\Tailscale\tailscaled: Access is denied."
 *       => TAILSCALE_CLI_LAYER = unknown/ts_pipe_denied, SERVE_PRESENT = unknown/serve_unknown.
 *     - plugin child (spawned by the DSH host process, which runs outside this agent session's
 *       restricted token): the same child CAN open the tailscaled named pipe, so `ip -4` can
 *       succeed and the CLI/serve checks can become determinate.
 *   => Never compare "counts I got from the CLI" with "counts the panel shows" as if they came from
 *      the same probe set: pass/fail totals legitimately differ. Both are honest; the report says
 *      which probe answered (evidence.source + the per-check raw blocks).
 *
 * READ-ONLY / SAFETY
 *   Nothing here writes, listens, reconfigures, elevates or restarts anything. The only external
 *   effect is a bounded child process running src/collect.ps1 with -CheckOnly. No credential is
 *   read, printed or forwarded: `raw` never crosses the RPC boundary (see toBoundedChecks).
 *
 * FIXTURE ARGUMENT (t16 F10)
 *   The optional `fixture` argument is restricted to a repository-relative path under
 *   tests/fixtures/ ending in .json; absolute paths, UNC paths and any ".." segment are rejected.
 *   Anything rejected comes back as {ok:false, code:'fixture-rejected'} instead of being passed on.
 *
 * COMMANDS USED (read-only; no client Inspect, no long waits):
 *   cordis_inspect_list ; cordis_inspect_query(host, Service.listService, {service:"fs"})
 *   cordis_inspect_query(host, Service.listService, {service:"subprocess"})
 *   cordis_define(host) ; cordis_run(guard-1, pkg-4, update) ; cordis_inspect_self()
 *   remote_tailnet_posture(role="both", fixture="remote-tailnet-plugin/tests/fixtures/zh.json")
 *   powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly
 *   Get-FileHash -LiteralPath remote-tailnet-plugin/src/host-half.js -Algorithm SHA256
 */
const COLLECTOR_REL = 'remote-tailnet-plugin/src/collect.ps1';
const FIXTURE_PREFIX = 'tests/fixtures/';
const FIXTURE_PREFIX_LONG = 'remote-tailnet-plugin/tests/fixtures/';

function guardFixturePath(value) {
  if (typeof value !== 'string' || value.length === 0) return { ok: true, path: '' };
  const raw = value.replace(/\\/g, '/');
  if (/^[A-Za-z]:\//.test(raw)) {
    return { ok: false, code: 'fixture-rejected', message: 'absolute paths are not accepted; use a repository-relative tests/fixtures/*.json path' };
  }
  if (raw.slice(0, 2) === '//') {
    return { ok: false, code: 'fixture-rejected', message: 'UNC paths are not accepted' };
  }
  const parts = raw.split('/');
  for (let index = 0; index < parts.length; index += 1) {
    if (parts[index] === '..') {
      return { ok: false, code: 'fixture-rejected', message: '".." segments are not accepted' };
    }
  }
  const allowed = raw.indexOf(FIXTURE_PREFIX) === 0 || raw.indexOf(FIXTURE_PREFIX_LONG) === 0;
  if (!allowed) {
    return { ok: false, code: 'fixture-rejected', message: 'only paths under tests/fixtures/ are accepted' };
  }
  if (!/\.json$/i.test(raw)) {
    return { ok: false, code: 'fixture-rejected', message: 'only .json fixtures are accepted' };
  }
  return { ok: true, path: raw };
}

return {
  name: 'remote-tailnet-guard-host',
  apply(ctx) {
    const fs = ctx.get('fs');
    const subprocess = ctx.get('subprocess');

    let lastSummary = null;
    let activeHandle = null;

    function textOf(error) {
      if (error && typeof error.message === 'string') return error.message;
      return String(error);
    }

    function parentOf(pathText) {
      const normalized = String(pathText).replace(/[\\/]+$/, '');
      const cut = Math.max(normalized.lastIndexOf('\\'), normalized.lastIndexOf('/'));
      if (cut <= 0) return '';
      return normalized.slice(0, cut);
    }

    function countVerdicts(checks) {
      const counts = { pass: 0, degraded: 0, blocked: 0, unknown: 0 };
      for (const check of checks) {
        if (Object.prototype.hasOwnProperty.call(counts, check.verdict)) counts[check.verdict] += 1;
      }
      return counts;
    }

    // Only the fields a consumer needs cross the boundary - never the raw report, never a live
    // object from the host runtime. Each entry carries its own evidence block so a consumer can
    // show WHY a verdict is what it is (and that a low-confidence text-parse verdict is degraded
    // by policy rather than presented as proven).
    function toBoundedChecks(report) {
      const out = [];
      const checks = Array.isArray(report.checks) ? report.checks : [];
      for (const check of checks) {
        const evidence = check.evidence && typeof check.evidence === 'object' ? check.evidence : {};
        const verdict = String(check.verdict);
        out.push({
          id: String(check.id),
          role: String(check.role),
          title: String(check.title),
          status: verdict,
          verdict: verdict,
          verdictLabel: String(check.verdictLabel),
          reasonKey: String(check.reasonKey),
          reason: String(check.reason),
          confidence: typeof evidence.confidence === 'string' ? evidence.confidence : 'unknown',
          confidenceDowngrade: evidence.confidenceDowngrade === true,
          evidence: {
            command: typeof evidence.command === 'string' ? evidence.command : '',
            exitCode: typeof evidence.exitCode === 'number' ? evidence.exitCode : null,
            source: typeof evidence.source === 'string' ? evidence.source : '',
            confidence: typeof evidence.confidence === 'string' ? evidence.confidence : 'unknown',
            window: typeof evidence.window === 'string' ? evidence.window : '',
            confidenceDowngrade: evidence.confidenceDowngrade === true
          },
          manualReview: check.manualReview === true,
          manualQuestion: typeof check.manualQuestion === 'string' ? check.manualQuestion : '',
          remediationAction: check.remediation && typeof check.remediation.action === 'string' ? check.remediation.action : '',
          remediationRollback: check.remediation && typeof check.remediation.rollback === 'string' ? check.remediation.rollback : '',
          autoApplied: false
        });
      }
      return out;
    }

    function toSummary(report) {
      const checks = Array.isArray(report.checks) ? report.checks : [];
      const counts = countVerdicts(checks);
      const nonPass = [];
      const lowConfidence = [];
      for (const check of checks) {
        const evidence = check.evidence && typeof check.evidence === 'object' ? check.evidence : {};
        if (check.verdict === 'pass') continue;
        nonPass.push({
          id: String(check.id),
          verdict: String(check.verdict),
          verdictLabel: String(check.verdictLabel),
          reasonKey: String(check.reasonKey),
          reason: String(check.reason),
          confidence: typeof evidence.confidence === 'string' ? evidence.confidence : 'unknown',
          manualReview: check.manualReview === true
        });
        if (evidence.confidence === 'low') lowConfidence.push(String(check.id));
      }
      return {
        verdict: String(report.summary && report.summary.verdict ? report.summary.verdict : 'unknown'),
        verdictLabel: String(report.summary && report.summary.verdictLabel ? report.summary.verdictLabel : ''),
        exitCode: Number(report.summary && typeof report.summary.exitCode === 'number' ? report.summary.exitCode : 2),
        total: checks.length,
        pass: counts.pass,
        degraded: counts.degraded,
        blocked: counts.blocked,
        unknown: counts.unknown,
        lowConfidenceCount: lowConfidence.length,
        lowConfidenceIds: lowConfidence,
        failClosed: 'any unknown forbids exit 0',
        generatedAtLocal: String(report.collector && report.collector.generatedAtLocal ? report.collector.generatedAtLocal : ''),
        checkIds: checks.map(function (check) { return String(check.id); }),
        nonPass: nonPass
      };
    }

    // Locate the collector without any machine-specific path. The fs provider's default base is
    // NOT the workspace root, so walk its ancestors and test the repository-relative path under
    // each one; the hit also becomes the subprocess cwd (which is what makes a relative
    // -FixturePath work).
    async function resolveCollector() {
      if (!fs) return { ok: false, code: 'no-fs', message: 'the fs service is unavailable in this host half' };
      const tried = [];
      let basePath = '';
      try {
        basePath = String((await fs.resolve('.')).displayPath || '');
      } catch (error) {
        basePath = '';
      }
      let candidateRoot = basePath;
      for (let step = 0; step <= 5; step += 1) {
        if (!candidateRoot) break;
        const candidate = candidateRoot.replace(/[\\/]+$/, '') + '/' + COLLECTOR_REL;
        tried.push(candidate);
        try {
          const target = await fs.resolve(candidate);
          const info = await fs.stat(target);
          if (info) {
            return {
              ok: true,
              scriptPath: fs.processPath(target),
              displayPath: String(target.displayPath),
              cwd: fs.processPath(await fs.resolve(candidateRoot))
            };
          }
        } catch (error) {
          tried.push(textOf(error));
        }
        candidateRoot = parentOf(candidateRoot);
      }
      return { ok: false, code: 'collector-missing', message: 'not found: ' + COLLECTOR_REL, tried: tried };
    }

    async function runCollector(options) {
      const opts = options && typeof options === 'object' ? options : {};
      const fixtureCheck = guardFixturePath(opts.fixture);
      if (fixtureCheck.ok !== true) {
        return { ok: false, code: fixtureCheck.code, message: fixtureCheck.message };
      }
      const found = await resolveCollector();
      if (!found.ok) {
        const extra = found.tried ? ' tried: ' + found.tried.join(' | ') : '';
        return { ok: false, code: found.code, message: String(found.message) + extra };
      }
      if (!subprocess) {
        return { ok: false, code: 'no-subprocess', message: 'the subprocess service is unavailable; run the collector manually: powershell -NoProfile -ExecutionPolicy Bypass -File ' + found.displayPath + ' -CheckOnly' };
      }
      let exe;
      try {
        exe = await subprocess.resolveExecutable('powershell.exe');
      } catch (error) {
        return { ok: false, code: 'no-powershell', message: textOf(error) };
      }
      const argv = [exe, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', found.scriptPath, '-CheckOnly', '-AsJson'];
      if (opts.role) argv.push('-Role', String(opts.role));
      if (opts.peer) argv.push('-Peer', String(opts.peer));
      if (opts.peerName) argv.push('-PeerName', String(opts.peerName));
      if (opts.lang) argv.push('-Lang', String(opts.lang));
      if (fixtureCheck.path) { argv.push('-FixturePath', fixtureCheck.path); argv.push('-NoNative'); }
      let handle;
      try {
        handle = subprocess.spawn({
          argv: argv,
          cwd: found.cwd,
          stdio: { stdin: 'ignore', stdout: { maxBytes: 8388608 }, stderr: { maxBytes: 262144 } },
          graceMs: 120000,
          signal: opts.signal
        });
      } catch (error) {
        return { ok: false, code: 'spawn-failed', message: textOf(error) };
      }
      activeHandle = handle;
      let outcome;
      try {
        outcome = await handle.done;
      } catch (error) {
        activeHandle = null;
        return { ok: false, code: 'run-failed', message: textOf(error) };
      }
      activeHandle = null;
      let stdout = '';
      let lossy = false;
      try {
        const collected = handle.collected && handle.collected.stdout ? handle.collected.stdout.readFrom(0) : null;
        if (collected) { stdout = String(collected.text); lossy = collected.lossy === true; }
      } catch (error) {
        return { ok: false, code: 'read-failed', message: textOf(error) };
      }
      let report = null;
      try {
        report = JSON.parse(stdout);
      } catch (error) {
        return { ok: false, code: 'json-parse-failed', message: textOf(error), exitCode: outcome ? outcome.exitCode : null, stdoutBytes: stdout.length };
      }
      const summary = toSummary(report);
      lastSummary = summary;
      return {
        ok: true,
        exitCode: outcome && typeof outcome.exitCode === 'number' ? outcome.exitCode : 0,
        lossy: lossy,
        stdoutBytes: stdout.length,
        script: found.displayPath,
        fixture: fixtureCheck.path,
        summary: summary,
        checks: toBoundedChecks(report)
      };
    }

    function compactText(result) {
      if (!result.ok) return 'remote-tailnet-guard: collection failed [' + result.code + '] ' + result.message;
      const summary = result.summary;
      const lines = [
        'verdict=' + summary.verdict + ' exit=' + summary.exitCode + ' (pass=' + summary.pass + ' degraded=' + summary.degraded + ' blocked=' + summary.blocked + ' unknown=' + summary.unknown + ')',
        'low-confidence (localized-text path) items: ' + (summary.lowConfidenceIds.length === 0 ? 'none' : summary.lowConfidenceIds.join(', ')),
        'read-only: the collector changes nothing; unknown is never treated as passing'
      ];
      for (const item of summary.nonPass) {
        lines.push('[' + item.verdict + '] ' + item.id + ' :: ' + item.reasonKey + ' (confidence=' + item.confidence + ')' + (item.manualReview ? ' (manual step required)' : ''));
      }
      return lines.join('\n');
    }

    const service = {
      name: 'remoteTailnetGuard',
      readOnly: true,
      collector: COLLECTOR_REL,
      fixturePolicy: 'relative tests/fixtures/*.json only; absolute, UNC and ".." are rejected',
      collect: function (options) { return runCollector(options); },
      lastSummary: function () { return lastSummary; }
    };

    const tool = harness.defineTool({
      name: 'remote_tailnet_posture',
      description: 'Run the read-only cross-network remote-access posture collector on this machine (Tailscale link prerequisites plus security posture) and return the pass/degraded/blocked/unknown verdicts with their evidence confidence. Nothing is written and nothing is changed.',
      parameters: {
        role: { type: 'string', description: 'server | client | both - which perspective to collect (default both)' },
        peer: { type: 'string', description: 'peer address for the client-side link probes (omit to leave those checks unknown)' },
        peerName: { type: 'string', description: 'peer MagicDNS name used for the resolution check' },
        fixture: { type: 'string', description: 'repository-relative tests/fixtures/*.json path only; the collector then runs fully offline against it' }
      },
      output: {
        schema: {
          type: 'object',
          additionalProperties: false,
          properties: {
            ok: { type: 'boolean', required: true, description: 'whether the collector ran and produced a parseable report' },
            verdict: { type: 'string', required: true },
            exitCode: { type: 'number', required: true },
            pass: { type: 'number', required: true },
            degraded: { type: 'number', required: true },
            blocked: { type: 'number', required: true },
            unknown: { type: 'number', required: true },
            lowConfidenceCount: { type: 'number', required: true },
            report: { type: 'string', required: true, description: 'human-readable one-line-per-finding summary' },
            nonPassIds: { type: 'array', required: true, items: { type: 'string' } }
          }
        },
        render: function (args, value) {
          return [{ type: 'text', text: String(value && value.report ? value.report : '') }];
        }
      },
      execute: async function (args, exec) {
        const result = await runCollector({
          role: args && args.role ? args.role : 'both',
          peer: args ? args.peer : '',
          peerName: args ? args.peerName : '',
          fixture: args ? args.fixture : '',
          signal: exec && exec.signal ? exec.signal : undefined
        });
        if (!result.ok) {
          return { ok: false, verdict: 'unknown', exitCode: 2, pass: 0, degraded: 0, blocked: 0, unknown: 0, lowConfidenceCount: 0, report: compactText(result), nonPassIds: [] };
        }
        const summary = result.summary;
        return {
          ok: true,
          verdict: summary.verdict,
          exitCode: summary.exitCode,
          pass: summary.pass,
          degraded: summary.degraded,
          blocked: summary.blocked,
          unknown: summary.unknown,
          lowConfidenceCount: summary.lowConfidenceCount,
          report: compactText(result),
          nonPassIds: summary.nonPass.map(function (item) { return item.id; })
        };
      }
    });

    ctx.effect(function () {
      const disposeService = ctx.provide('remoteTailnetGuard', service);
      const disposeRpc = harness.handle('remote-tailnet-guard/posture', async function (args) {
        const result = await runCollector(args || {});
        if (!result.ok) return { ok: false, code: result.code, message: result.message };
        return { ok: true, exitCode: result.exitCode, summary: result.summary, checks: result.checks, script: result.script, fixture: result.fixture };
      });
      const disposeTool = harness.registerTool(ctx, tool);
      console.log('remote-tailnet-guard: read-only posture service ready (' + COLLECTOR_REL + ')');
      return function () {
        try { disposeTool(); } catch (error) { }
        try { disposeRpc(); } catch (error) { }
        try { disposeService(); } catch (error) { }
        if (activeHandle && typeof activeHandle.terminate === 'function') {
          try { activeHandle.terminate(); } catch (error) { }
          activeHandle = null;
        }
      };
    }, 'remote-tailnet-guard: posture service, private method, verification tool');
  }
};
