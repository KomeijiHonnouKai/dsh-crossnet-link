/*
 * dsh-crossnet-link - CLIENT half of the posture panel package (t6).
 * LAST UPDATED : 2026-09-24 (v0.1 - t26: CREDENTIAL_NOTICES gained a FOURTH entry that states the
 * non-intrusive promise in the panel itself - nothing is changed and suggested fixes are yours to
 * run - and the notices heading now says so. The three credential-discipline strings, the slot
 * registration and the host half are unchanged.) This file IS the exact text passed as `code.client`
 * to cordis_define (plain JavaScript: no JSX, no TypeScript, no import/require).
 * Builtins used - and only these: `React` (createElement / useState / useEffect) and
 * `host.call(method, args)`. useCallback/useMemo/useRef are deliberately NOT used because the
 * runner declares only createElement/useState/useEffect.
 * Slot: `settings.section`, kind `list`, options { id (required), order, label }.
 * Full evidence table (file + line) is in docs/install/install.md section 3; no client Inspect
 * was used anywhere in this task.
 * COMMANDS USED (read-only; no client Inspect, no long waits):
 *   grep -n "settings\.section" <app>\node_modules\@deepseek-ai\**\lib\*.js
 *   grep -n "React|host\.call|listBuiltins|inject: \[|slots" <app>\...\dsh-cordis-client-runner\lib\client.js
 *   cordis_define(host+client) ; cordis_inspect_self(pluginId, packageId)
 *   powershell -NoProfile -Command '(Get-ChildItem remote-tailnet-plugin -Recurse -Include *.js,*.mjs,*.cjs | Select-String -SimpleMatch "dsh-client-"+"runtime" | Measure-Object).Count'
 *   powershell -NoProfile -Command '$f="remote-tailnet-plugin/panel/client-half.js"; $b=[IO.File]::ReadAllBytes((Resolve-Path $f)); "nonAscii=" + @($b | Where-Object { $_ -gt 127 }).Count + " bom=" + ($b[0..2] -join ",")'
 *   powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1
 */
const SECTION_ID = 'dsh-crossnet-link';
const SECTION_LABEL = 'Remote access link (read-only posture)';
const METHOD = 'dsh-crossnet-link/panel/posture';
const VERDICTS = ['blocked', 'unknown', 'degraded', 'pass'];
const VERDICT_STYLE = {
  blocked: { label: 'BLOCKED', color: '#c0392b' },
  unknown: { label: 'UNKNOWN', color: '#8a6d00' },
  degraded: { label: 'DEGRADED', color: '#8a6d00' },
  pass: { label: 'PASS', color: '#1e7a34' }
};
const CREDENTIAL_NOTICES = [
  'This panel reads no credential material: no token, no cookie, no key file, no DSH secret store.',
  'It displays verdicts only - raw probe output stays on the host and never crosses the bridge.',
  'It installs nothing, opens no listener, changes no system setting and never restarts DSH.',
  'Nothing is changed here: no system setting, no firewall rule, no profile, no cordis.patch.yml and no other plugin configuration. Suggested fixes are printed for you to run - the panel itself only reports.'
];

function readString(value, fallback) {
  if (typeof value === 'string' && value.length > 0) return value;
  return fallback;
}

function severityOf(verdict) {
  if (verdict === 'blocked') return 0;
  if (verdict === 'unknown') return 1;
  if (verdict === 'degraded') return 2;
  return 3;
}

function styleOf(verdict) {
  if (Object.prototype.hasOwnProperty.call(VERDICT_STYLE, verdict)) return VERDICT_STYLE[verdict];
  return { label: 'UNKNOWN', color: '#555555' };
}

function countLine(summary) {
  if (summary === null || typeof summary !== 'object') return '';
  return 'pass=' + summary.pass + '  degraded=' + summary.degraded + '  blocked=' + summary.blocked +
    '  unknown=' + summary.unknown + '   (total ' + summary.total + ')';
}

function exitReading(summary) {
  if (summary === null || typeof summary !== 'object') return '';
  if (summary.exitCode === 0) return 'exit 0 = every judgement passed.';
  if (summary.exitCode === 1) return 'exit 1 = degraded and/or unknown. The link may work, but nothing unproven counts as passing.';
  return 'exit 2 = a fail-closed verdict, NOT a command failure: at least one blocked finding, or the collector itself could not run.';
}

function itemRow(check, key) {
  const vstyle = styleOf(check.verdict);
  const badges = [];
  if (check.evidenceConfidence === 'low') {
    badges.push(React.createElement('span', {
      key: 'conf',
      style: { marginLeft: '6px', padding: '1px 4px', border: '1px solid #b58900', borderRadius: '3px', fontSize: '11px', color: '#8a6d00' }
    }, 'low confidence: localized-text path, reported as degraded'));
  }
  if (check.manualReview === true) {
    badges.push(React.createElement('span', {
      key: 'manual',
      style: { marginLeft: '6px', padding: '1px 4px', border: '1px solid #777777', borderRadius: '3px', fontSize: '11px', color: '#555555' }
    }, 'manual step required'));
  }
  const children = [
    React.createElement('div', { key: 'head', style: { marginBottom: '2px' } },
      React.createElement('span', { style: { color: vstyle.color, fontWeight: 'bold', marginRight: '6px' } }, check.verdictLabel || vstyle.label),
      React.createElement('span', { style: { fontFamily: 'monospace', fontSize: '12px' } }, check.id),
      badges
    ),
    React.createElement('div', { key: 'reason', style: { fontSize: '13px' } }, check.reason),
    check.manualQuestion ? React.createElement('div', { key: 'mq', style: { fontSize: '12px', color: '#555555', marginTop: '2px' } }, check.manualQuestion) : null,
    check.remediationAction ? React.createElement('div', { key: 'ra', style: { fontSize: '12px', marginTop: '2px' } }, 'fix (yours to run, nothing was applied): ' + check.remediationAction) : null,
    check.remediationRollback ? React.createElement('div', { key: 'rr', style: { fontSize: '12px', color: '#555555' } }, 'rollback: ' + check.remediationRollback) : null
  ];
  return React.createElement('li', {
    key: key,
    style: { marginBottom: '8px', paddingBottom: '6px', borderBottom: '1px solid rgba(127,127,127,0.25)' }
  }, children);
}

function GuardPanel() {
  const statePair = React.useState({ phase: 'loading', payload: null, error: '' });
  const state = statePair[0];
  const setState = statePair[1];
  const noncePair = React.useState(0);
  const nonce = noncePair[0];
  const setNonce = noncePair[1];
  const rolePair = React.useState('client');
  const role = rolePair[0];
  const setRole = rolePair[1];

  React.useEffect(function () {
    let alive = true;
    setState({ phase: 'loading', payload: null, error: '' });
    host.call(METHOD, { role: role }).then(function (result) {
      if (!alive) return;
      if (result && result.ok === true) setState({ phase: 'ready', payload: result, error: '' });
      else {
        setState({
          phase: 'failed',
          payload: result || null,
          error: readString(result && result.message, 'the host method returned no usable result')
        });
      }
    }).catch(function (error) {
      if (!alive) return;
      setState({ phase: 'failed', payload: null, error: String(error && error.message ? error.message : error) });
    });
    return function () { alive = false; };
  }, [nonce, role]);

  const blocks = [];

  blocks.push(React.createElement('h3', { key: 'title', style: { margin: '0 0 4px 0' } }, SECTION_LABEL));
  blocks.push(React.createElement('div', { key: 'sub', style: { fontSize: '12px', color: '#666666', marginBottom: '10px' } },
    'Read-only. Verdicts come from remote-tailnet-plugin/src/collect.ps1 - nothing is installed, no listener is opened, no setting is changed.'));

  const controls = [];
  controls.push(React.createElement('label', { key: 'rolelabel', style: { fontSize: '12px', marginRight: '6px' } }, 'perspective:'));
  controls.push(React.createElement('select', {
    key: 'role',
    value: role,
    onChange: function (event) { setRole(event.target.value); },
    style: { fontSize: '12px', marginRight: '8px' }
  },
    React.createElement('option', { key: 'client', value: 'client' }, 'client (this machine just uses the link)'),
    React.createElement('option', { key: 'server', value: 'server' }, 'server (this machine serves the link)'),
    React.createElement('option', { key: 'both', value: 'both' }, 'both')
  ));
  controls.push(React.createElement('button', {
    key: 'refresh',
    type: 'button',
    onClick: function () { setNonce(nonce + 1); },
    style: { fontSize: '12px' }
  }, state.phase === 'loading' ? 'checking...' : 'refresh'));
  blocks.push(React.createElement('div', { key: 'controls', style: { marginBottom: '10px' } }, controls));
  blocks.push(React.createElement('div', { key: 'rolehint', style: { fontSize: '12px', color: '#666666', marginBottom: '10px' } },
    'A client-only machine should use the client perspective: the server-only checks are then not emitted at all, so the summary cannot report a server-side gap you do not have.'));

  if (state.phase === 'loading') {
    blocks.push(React.createElement('p', { key: 'loading' }, 'Querying the collector on the host...'));
  } else if (state.phase === 'failed') {
    blocks.push(React.createElement('p', { key: 'failed', style: { color: '#c0392b' } },
      'No posture available yet: ' + state.error));
    blocks.push(React.createElement('p', { key: 'hint', style: { fontSize: '12px', color: '#666666' } },
      'This is reported as unknown, never as passing. If the message mentions the collector Service or the script path, activate the host half of this plugin (docs/install/install.md) and refresh.'));
  } else {
    const payload = state.payload;
    const summary = payload.summary;
    const checks = Array.isArray(payload.checks) ? payload.checks : [];
    blocks.push(React.createElement('div', { key: 'overall', style: { marginBottom: '6px' } },
      React.createElement('span', {
        style: { fontWeight: 'bold', color: styleOf(summary.verdict).color, marginRight: '8px' }
      }, summary.verdictLabel || styleOf(summary.verdict).label),
      React.createElement('span', { style: { fontSize: '13px' } }, countLine(summary))
    ));
    blocks.push(React.createElement('div', { key: 'exit', style: { fontSize: '12px', marginBottom: '4px' } }, exitReading(summary)));
    blocks.push(React.createElement('div', { key: 'failclosed', style: { fontSize: '12px', color: '#666666', marginBottom: '4px' } },
      'fail-closed: ' + readString(summary.failClosed, 'any unknown forbids exit 0') + ' - an unknown is never rendered as a pass.'));
    blocks.push(React.createElement('div', { key: 'provenance', style: { fontSize: '11px', color: '#777777', marginBottom: '10px', fontFamily: 'monospace' } },
      'source=' + readString(payload.source, 'unknown') +
      '  script=' + readString(payload.script, '(not reported)') +
      '  generated=' + readString(summary.generatedAtLocal, '(unknown)')));

    const ordered = checks.slice(0).sort(function (left, right) {
      const delta = severityOf(left.verdict) - severityOf(right.verdict);
      if (delta !== 0) return delta;
      return String(left.id) < String(right.id) ? -1 : 1;
    });
    blocks.push(React.createElement('div', { key: 'itemsHead', style: { fontSize: '12px', color: '#666666', marginBottom: '4px' } },
      'All judgements, worst first (' + ordered.length + '):'));
    const rows = [];
    for (let index = 0; index < ordered.length; index += 1) rows.push(itemRow(ordered[index], ordered[index].id));
    blocks.push(React.createElement('ul', { key: 'items', style: { listStyle: 'none', paddingLeft: '0', margin: '0 0 12px 0' } }, rows));

    const manual = [];
    for (let index = 0; index < ordered.length; index += 1) {
      if (ordered[index].manualReview === true) manual.push(ordered[index]);
    }
    if (manual.length > 0) {
      blocks.push(React.createElement('div', { key: 'manualhead', style: { fontSize: '12px', fontWeight: 'bold', marginBottom: '4px' } },
        'Steps only a human can take (never automated here):'));
      const manualRows = [];
      for (let index = 0; index < manual.length; index += 1) {
        manualRows.push(React.createElement('li', { key: 'm' + manual[index].id, style: { fontSize: '12px', marginBottom: '3px' } },
          manual[index].id + ': ' + manual[index].manualQuestion));
      }
      blocks.push(React.createElement('ul', { key: 'manual', style: { marginTop: '0', marginBottom: '12px' } }, manualRows));
    }
  }

  blocks.push(React.createElement('div', { key: 'credhead', style: { fontSize: '12px', fontWeight: 'bold', marginBottom: '4px' } },
    'Credential discipline and the no-change promise'));
  const notices = [];
  for (let index = 0; index < CREDENTIAL_NOTICES.length; index += 1) {
    notices.push(React.createElement('li', { key: 'c' + index, style: { fontSize: '12px', marginBottom: '2px' } }, CREDENTIAL_NOTICES[index]));
  }
  blocks.push(React.createElement('ul', { key: 'cred', style: { marginTop: '0', marginBottom: '0' } }, notices));

  return React.createElement('div', { style: { padding: '4px 0 8px 0' } }, blocks);
}

return {
  name: 'dsh-crossnet-link-panel',
  inject: ['slots'],
  apply(ctx) {
    ctx.slots.inject('settings.section', function () {
      return ctx.slots.register(
        { name: 'settings.section', id: SECTION_ID, order: 100, label: SECTION_LABEL },
        function () { return React.createElement(GuardPanel, null); }
      );
    });
  }
};
