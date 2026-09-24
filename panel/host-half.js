/*
 * remote-tailnet-guard - HOST half of the posture panel package (t6).
 * LAST UPDATED : 2026-09-24 (t16 repair-round-2: F10 fixture-path whitelist added to BOTH the
 * service path and the direct fallback; absolute paths, UNC paths and ".." segments are refused).
 * This file IS the exact text passed as `code.host` to
 * cordis_define (plain JavaScript function body, no import/require/TypeScript/JSX).
 * COMMANDS USED (read-only; no client Inspect, no long waits):
 *   cordis_inspect_list ; cordis_inspect_query(host, Service.listService, {service:"fs"})
 *   cordis_inspect_query(host, Service.listService, {service:"subprocess"})
 *   grep -n "settings\.section" <app>\node_modules\@deepseek-ai\**\lib\*.js
 *   grep -n "React|host\.call|listBuiltins|inject: \[|slots" <app>\...\dsh-cordis-client-runner\lib\client.js
 *   powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/panel/prereq.ps1 -CheckOnly
 *   powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly
 * See docs/install/install.md for the slot/builtin evidence table and the activation checklist.
 */
const METHOD = 'remote-tailnet-guard/panel/posture';
const SERVICE_KEY = 'remoteTailnetGuard';
const COLLECTOR_REL = 'remote-tailnet-plugin/src/collect.ps1';
const FIXTURE_PREFIX = 'tests/fixtures/';
const FIXTURE_PREFIX_LONG = 'remote-tailnet-plugin/tests/fixtures/';

// t16 F10: the bridge's optional `fixture` argument is a path-shaped input, so it is whitelisted
// instead of trusted: repository-relative, under tests/fixtures/, .json only, and no ".." segment.
// Anything else is refused with a machine-readable code and never reaches the child process.
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
  if (raw.indexOf(FIXTURE_PREFIX) !== 0 && raw.indexOf(FIXTURE_PREFIX_LONG) !== 0) {
    return { ok: false, code: 'fixture-rejected', message: 'only paths under tests/fixtures/ are accepted' };
  }
  if (!/\.json$/i.test(raw)) {
    return { ok: false, code: 'fixture-rejected', message: 'only .json fixtures are accepted' };
  }
  return { ok: true, path: raw };
}

return {
  name: 'remote-tailnet-guard-panel-host',
  apply(ctx) {
    function pickString(value, fallback) {
      if (typeof value !== 'string') return fallback;
      if (value.length === 0) return fallback;
      return value;
    }

    // The collector reports evidence confidence on the full report (evidence.confidence) while
    // the t5 Service hands out bounded checks carrying it at the top level. Accept both shapes so
    // the panel shows the same marker whichever path answered.
    function readConfidence(check) {
      if (check && typeof check.confidence === 'string' && check.confidence.length > 0) return check.confidence;
      const evidence = check && check.evidence ? check.evidence : null;
      if (evidence && typeof evidence.confidence === 'string' && evidence.confidence.length > 0) return evidence.confidence;
      return 'unknown';
    }

    function readDowngrade(check) {
      if (check && check.confidenceDowngrade === true) return true;
      const evidence = check && check.evidence ? check.evidence : null;
      return evidence !== null && evidence.confidenceDowngrade === true;
    }

    function boundedCheck(check) {
      const remediation = check && check.remediation ? check.remediation : null;
      return {
        id: pickString(check && check.id, ''),
        role: pickString(check && check.role, ''),
        title: pickString(check && check.title, ''),
        verdict: pickString(check && check.verdict, 'unknown'),
        verdictLabel: pickString(check && check.verdictLabel, 'UNKNOWN'),
        reasonKey: pickString(check && check.reasonKey, ''),
        reason: pickString(check && check.reason, ''),
        evidenceConfidence: readConfidence(check),
        confidenceDowngrade: readDowngrade(check),
        manualReview: (check && check.manualReview === true),
        manualQuestion: pickString(check && check.manualQuestion, ''),
        remediationAction: pickString(remediation && remediation.action, ''),
        remediationRollback: pickString(remediation && remediation.rollback, ''),
        autoApplied: false
      };
    }

    function boundedChecks(list) {
      const out = [];
      const source = Array.isArray(list) ? list : [];
      for (let index = 0; index < source.length; index += 1) out.push(boundedCheck(source[index]));
      return out;
    }

    function boundedSummary(summary, checks) {
      const counts = { pass: 0, degraded: 0, blocked: 0, unknown: 0 };
      for (let index = 0; index < checks.length; index += 1) {
        const verdict = checks[index].verdict;
        if (Object.prototype.hasOwnProperty.call(counts, verdict)) counts[verdict] += 1;
      }
      return {
        verdict: pickString(summary && summary.verdict, 'unknown'),
        verdictLabel: pickString(summary && summary.verdictLabel, 'UNKNOWN'),
        exitCode: summary && typeof summary.exitCode === 'number' ? summary.exitCode : 2,
        total: checks.length,
        pass: counts.pass,
        degraded: counts.degraded,
        blocked: counts.blocked,
        unknown: counts.unknown,
        failClosed: pickString(summary && summary.failClosed, 'any unknown forbids exit 0'),
        generatedAtLocal: pickString(summary && summary.generatedAtLocal, '')
      };
    }

    // --- fallback path: run the collector directly when the t5 host Service is absent -------
    async function locateCollector() {
      const fs = ctx.get('fs');
      if (fs === undefined) return null;
      let base = '';
      try { base = String((await fs.resolve('.')).displayPath || ''); } catch (error) { base = ''; }
      let dir = base.replace(/[\\/]+$/, '');
      for (let step = 0; step <= 5 && dir.length > 0; step += 1) {
        const candidate = dir + '/' + COLLECTOR_REL;
        try {
          const target = await fs.resolve(candidate);
          const info = await fs.stat(target);
          if (info) {
            return {
              scriptPath: fs.processPath(target),
              displayPath: String(target.displayPath),
              cwd: fs.processPath(await fs.resolve(dir))
            };
          }
        } catch (error) { /* try the parent directory */ }
        const cut = Math.max(dir.lastIndexOf('\\'), dir.lastIndexOf('/'));
        dir = cut > 0 ? dir.slice(0, cut) : '';
      }
      return null;
    }

    async function runCollectorDirectly(options) {
      const subprocess = ctx.get('subprocess');
      if (subprocess === undefined) {
        return { ok: false, code: 'no-subprocess', message: 'the subprocess service is unavailable in this host half' };
      }
      const found = await locateCollector();
      if (found === null) {
        return { ok: false, code: 'collector-missing', message: 'not found: ' + COLLECTOR_REL + ' (searched the fs base and its ancestors)' };
      }
      const exe = await subprocess.resolveExecutable('powershell.exe');
      const argv = [exe, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', found.scriptPath, '-CheckOnly', '-AsJson'];
      if (options.role) argv.push('-Role', options.role);
      if (options.peer) argv.push('-Peer', options.peer);
      if (options.peerName) argv.push('-PeerName', options.peerName);
      const fixtureCheck = guardFixturePath(options.fixture);
      if (fixtureCheck.ok !== true) {
        return { ok: false, code: fixtureCheck.code, message: fixtureCheck.message };
      }
      if (fixtureCheck.path) { argv.push('-FixturePath', fixtureCheck.path); argv.push('-NoNative'); }
      const handle = subprocess.spawn({
        argv: argv,
        cwd: found.cwd,
        stdio: { stdin: 'ignore', stdout: { maxBytes: 8388608 }, stderr: { maxBytes: 262144 } },
        graceMs: 120000
      });
      const outcome = await handle.done;
      let stdout = '';
      try {
        const collected = handle.collected && handle.collected.stdout ? handle.collected.stdout.readFrom(0) : null;
        if (collected !== null) stdout = String(collected.text);
      } catch (error) {
        return { ok: false, code: 'read-failed', message: String(error && error.message ? error.message : error) };
      }
      let report = null;
      try {
        report = JSON.parse(stdout);
      } catch (error) {
        return {
          ok: false,
          code: 'json-parse-failed',
          message: String(error && error.message ? error.message : error),
          exitCode: outcome && typeof outcome.exitCode === 'number' ? outcome.exitCode : null
        };
      }
      const checks = boundedChecks(report.checks);
      return {
        ok: true,
        source: 'direct',
        script: found.displayPath,
        exitCode: outcome && typeof outcome.exitCode === 'number' ? outcome.exitCode : 0,
        summary: boundedSummary(report.summary, checks),
        checks: checks
      };
    }

    async function fetchPosture(args) {
      const raw = args && typeof args === 'object' ? args : {};
      const options = {
        role: pickString(raw.role, 'both'),
        peer: pickString(raw.peer, ''),
        peerName: pickString(raw.peerName, ''),
        fixture: pickString(raw.fixture, '')
      };
      const fixtureCheck = guardFixturePath(pickString(raw.fixture, ''));
      if (fixtureCheck.ok !== true) {
        return { ok: false, code: fixtureCheck.code, message: fixtureCheck.message };
      }
      const service = ctx.get(SERVICE_KEY);
      if (service !== undefined && typeof service.collect === 'function') {
        let result = null;
        try {
          result = await service.collect(options);
        } catch (error) {
          return { ok: false, code: 'service-threw', message: String(error && error.message ? error.message : error) };
        }
        if (result && result.ok === true) {
          const checks = boundedChecks(result.checks);
          return {
            ok: true,
            source: 'service:' + SERVICE_KEY,
            script: pickString(result.script, ''),
            exitCode: typeof result.exitCode === 'number' ? result.exitCode : 0,
            summary: boundedSummary(result.summary, checks),
            checks: checks
          };
        }
        // The Service exists but could not collect: fall through to the direct path once.
        const direct = await runCollectorDirectly(options);
        if (direct.ok === true) return direct;
        return {
          ok: false,
          code: pickString(result && result.code, 'service-failed'),
          message: pickString(result && result.message, 'the collector service reported a failure') +
            ' | direct fallback: [' + direct.code + '] ' + direct.message
        };
      }
      const direct = await runCollectorDirectly(options);
      if (direct.ok === true) return direct;
      return {
        ok: false,
        code: direct.code,
        message: direct.message + ' | the t5 host package provides the Service "' + SERVICE_KEY +
          '"; activating it is the preferred path (see docs/install/install.md)'
      };
    }

    ctx.effect(function () {
      const dispose = harness.handle(METHOD, function (args) {
        return fetchPosture(args);
      });
      console.log('remote-tailnet-guard panel bridge ready: ' + METHOD);
      return function () {
        try { dispose(); } catch (error) { /* already disposed */ }
      };
    }, 'remote-tailnet-guard: panel bridge (package-private JSON method)');
  }
};
