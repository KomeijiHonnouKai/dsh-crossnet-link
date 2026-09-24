/*
 * remote-tailnet-guard - CLIENT half of the persistent DSH plugin (t46) - BROWSER BUNDLE.
 * LAST UPDATED : 2026-09-24 (v0.2 - t46: the plugins-page card seat `settings.plugin.item` is
 * registered beside the t43 `settings.section` seat; the row that mounts this package still ships
 * disabled: see plugin/cordis.patch.yml and docs/install/plugin-package.md).
 *
 * WHY THIS FILE IS A BUNDLE AND NOT PLAIN ESM: every client half in this DSH release is served to
 * the page as a classic script that must REGISTER itself with window.__ModuleLoader__.load({id,
 * factory}) - the module system throws "bundle ... loaded without registering ... via
 * __ModuleLoader__.load" when a fetched bundle does not (dsh-client-modules/lib/client.js:248), and
 * its synchronous require only resolves platform seed words or already-materialized rows
 * (dsh-client-modules/lib/client.js:300-310). Both real installed plugins on this machine ship
 * exactly this shape (dsh-ego-browser/lib/client.js, @nanmicoder/dsh-agent-teams/lib/client.js,
 * the latter 197202 bytes plus a 224758-byte .map).
 *
 * The only external this bundle requires is the platform seed "react". The seed table is built by
 * the Web shell (dsh-web-frontend/dist/assets/index-*.js, function feeding
 * __ModuleLoader__.create({staticModules: ...})) and contains react, react/jsx-runtime,
 * react-dom, react-dom/client, @deepseek-ai/cordis, @deepseek-ai/dsh-client-store,
 * @deepseek-ai/dsh-client-ui-slots, @deepseek-ai/dsh-client-ui-primitives and
 * @deepseek-ai/dsh-client-ui-dockkit. Everything else stays inside this file.
 *
 * The region between the two SHARED BODY markers is byte-identical to the ESM source of the same
 * half (lib/client/index.js); panel/plugin-preflight.ps1 fails if the two ever drift apart.
 */
window.__ModuleLoader__.load({ id: "remote-tailnet-guard", factory: (require) => {
var module = { exports: {} }; var exports = module.exports;
var React = require("react");
// ==== SHARED BODY BEGIN (byte-identical in lib/client.js and lib/client/index.js) ====
const SECTION_ID = 'remote-tailnet-guard';
const SECTION_LABEL = 'Remote access link (read-only posture)';
// Plugins-page card key (t46): the configurable tab inside 'settings.plugins.tab' renders one card
// per SERVED settings namespace, so this key must equal the namespace the host half registers.
const SETTINGS_NS = 'remote-tailnet-guard';
const CARD_ORDER = 100;
const ROUTE = '/remote-tailnet-guard/api/posture';
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

function queryPosture(role) {
  return fetch(ROUTE, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ role: role })
  }).then(function (response) {
    return response.json();
  }).then(function (payload) {
    if (payload !== null && typeof payload === 'object' && payload.ok === true) return payload;
    throw new Error(readString(payload && payload.message, 'the host route returned no usable result'));
  });
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
    queryPosture(role).then(function (result) {
      if (!alive) return;
      setState({ phase: 'ready', payload: result, error: '' });
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
      'This is reported as unknown, never as passing. If the message mentions the route or the collector path, the host half of this plugin is not serving it: the row is either still disabled or its route failed to register (docs/install/plugin-package.md).'));
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

function apply(ctx) {
  // Seat 1 (t43): the standalone settings page entry.
  ctx.slots.inject('settings.section', function () {
    return ctx.slots.register(
      { name: 'settings.section', id: SECTION_ID, order: 100, label: SECTION_LABEL },
      function () { return React.createElement(GuardPanel, null); }
    );
  });
  // Seat 2 (t46): the card inside Settings -> Plugins. Same panel, same read-only content; the
  // slot is keyed by the settings namespace the host half registers, and the section supplies no
  // owner props (the card draws its own label), so the identical component serves both seats.
  ctx.slots.inject('settings.plugin.item', function () {
    return ctx.slots.register(
      { name: 'settings.plugin.item', key: SETTINGS_NS, order: CARD_ORDER },
      function () { return React.createElement(GuardPanel, null); }
    );
  });
}
// ==== SHARED BODY END ====
exports.name = "remote-tailnet-guard";
exports.inject = ["slots"];
exports.apply = apply;
return module.exports; } });