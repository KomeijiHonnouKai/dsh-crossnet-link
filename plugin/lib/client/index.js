/*
 * remote-tailnet-guard - CLIENT half of the persistent DSH plugin - ESM SOURCE.
 * LAST UPDATED : 2026-09-25 (v0.3 - see ../client.js: the standalone settings-section seat is
 * removed; the plugin now registers only the standard plugins-page card, folded and in Chinese).
 *
 * WHAT THIS FILE IS: the readable, importable source of the plugins-page card. The runtime entry
 * named by package.json exports['./client'] is ../client.js (the browser bundle); the region between
 * the two SHARED BODY markers below is kept byte-identical to the bundle, and
 * panel/plugin-preflight.ps1 fails if the two ever drift apart.
 */
import React from 'react';
// ==== SHARED BODY BEGIN (byte-identical in lib/client.js and lib/client/index.js) ====
const SETTINGS_NS = 'remote-tailnet-guard';
const CARD_ORDER = 100;
const ROUTE = '/remote-tailnet-guard/api/posture';
const CSS_ID = 'dsh-rtg-card-css';
const CARD_TITLE = '\u8de8\u7f51\u94fe\u8def\u59ff\u6001';
const CARD_DESC = '\u53ea\u8bfb\u4f53\u68c0:\u5224\u5b9a\u4e24\u53f0 DSH \u4e4b\u95f4\u7684\u94fe\u8def\u59ff\u6001,\u4e0d\u88c5\u4efb\u4f55\u4e1c\u897f\u3001\u4e0d\u6539\u4efb\u4f55\u914d\u7f6e\u3002';
const CARD_CSS = '.dsh-rtg-card{border:1px solid var(--dsw-alias-border-l2);background:var(--dsw-alias-bg-layer-3);border-radius:12px;list-style:none;transition:border-color .16s,background .16s}.dsh-rtg-card:hover{border-color:var(--dsw-alias-label-dimmed)}.dsh-rtg-card--open{background:var(--dsw-alias-bg-layer-2);border-color:var(--dsw-alias-label-dimmed)}.dsh-rtg-card__header{appearance:none;width:100%;font:inherit;color:inherit;text-align:left;cursor:pointer;background:0 0;border:0;border-radius:12px;align-items:center;gap:12px;padding:14px 16px;display:flex}.dsh-rtg-card__header:focus-visible{outline:2px solid var(--dsw-alias-brand-primary);outline-offset:-2px}.dsh-rtg-card__head-text{flex-direction:column;flex:1;gap:4px;min-width:0;display:flex}.dsh-rtg-card__name{color:var(--dsw-alias-label-primary);font-size:15px;font-weight:600;line-height:1.4}.dsh-rtg-card__desc{color:var(--dsw-alias-label-tertiary);font-size:13px;line-height:1.5}.dsh-rtg-card__chevron{color:var(--dsw-alias-label-tertiary);flex:none;transition:transform .16s;display:inline-flex;align-items:center}.dsh-rtg-card__chevron--open{transform:rotate(180deg)}.dsh-rtg-card__body{border-top:1px solid var(--dsw-alias-border-l2);margin:0 16px;padding:12px 0 4px}';
const VERDICT_STYLE = {
  blocked: { label: '\u963b\u65ad', color: '#c0392b' },
  unknown: { label: '\u672a\u77e5', color: '#8a6d00' },
  degraded: { label: '\u964d\u7ea7', color: '#8a6d00' },
  pass: { label: '\u901a\u8fc7', color: '#1e7a34' }
};
const CREDENTIAL_NOTICES = [
  '\u672c\u9762\u677f\u4e0d\u8bfb\u4efb\u4f55\u51ed\u636e\u6750\u6599:\u6ca1\u6709 token\u3001\u6ca1\u6709 cookie\u3001\u6ca1\u6709\u5bc6\u94a5\u6587\u4ef6\u3001\u6ca1\u6709\u51ed\u636e\u5e93\u3002',
  '\u53ea\u663e\u793a\u5224\u5b9a:\u539f\u59cb\u63a2\u6d4b\u8f93\u51fa\u7559\u5728\u4e3b\u673a,\u4e0d\u8fc7\u6865\u3002',
  '\u4e0d\u88c5\u4efb\u4f55\u4e1c\u897f\u3001\u4e0d\u5f00\u76d1\u542c\u3001\u4e0d\u6539\u4efb\u4f55\u7cfb\u7edf\u8bbe\u7f6e\u3001\u4ece\u4e0d\u91cd\u542f DSH\u3002',
  '\u8fd9\u91cc\u4e0d\u6539\u4efb\u4f55\u4e1c\u897f:\u4e0d\u6539\u7cfb\u7edf\u8bbe\u7f6e\u3001\u9632\u706b\u5899\u89c4\u5219\u3001profile\u3001cordis.patch.yml,\u4e5f\u4e0d\u6539\u5176\u5b83\u63d2\u4ef6\u914d\u7f6e;\u5efa\u8bae\u7684\u4fee\u590d\u6253\u5370\u7ed9\u4f60\u6267\u884c,\u9762\u677f\u53ea\u62a5\u544a\u3002'
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
  return { label: '\u672a\u77e5', color: '#555555' };
}

function countLine(summary) {
  if (summary === null || typeof summary !== 'object') return '';
  return '\u901a\u8fc7=' + summary.pass + '  \u964d\u7ea7=' + summary.degraded + '  \u963b\u65ad=' + summary.blocked +
    '  \u672a\u77e5=' + summary.unknown + '  \uff08\u5171 ' + summary.total + '\uff09';
}

function exitReading(summary) {
  if (summary === null || typeof summary !== 'object') return '';
  if (summary.exitCode === 0) return '\u9000\u51fa 0 = \u6bcf\u4e00\u9879\u90fd\u901a\u8fc7\u3002';
  if (summary.exitCode === 1) return '\u9000\u51fa 1 = \u6709\u964d\u7ea7\u6216\u672a\u77e5\u3002\u94fe\u8def\u53ef\u80fd\u53ef\u7528,\u4f46\u672a\u7ecf\u8bc1\u660e\u7684\u4e0d\u7b97\u901a\u8fc7\u3002';
  return '\u9000\u51fa 2 = fail-closed \u5224\u5b9a,\u4e0d\u662f\u547d\u4ee4\u5931\u8d25:\u81f3\u5c11\u4e00\u9879\u963b\u65ad,\u6216\u91c7\u96c6\u5668\u672c\u8eab\u8dd1\u4e0d\u8d77\u6765\u3002';
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
    throw new Error(readString(payload && payload.message, '\u4e3b\u673a\u8def\u7531\u6ca1\u6709\u8fd4\u56de\u53ef\u7528\u7ed3\u679c'));
  });
}

function itemRow(check, key) {
  const vstyle = styleOf(check.verdict);
  const badges = [];
  if (check.evidenceConfidence === 'low') {
    badges.push(React.createElement('span', {
      key: 'conf',
      style: { marginLeft: '6px', padding: '1px 4px', border: '1px solid #b58900', borderRadius: '3px', fontSize: '11px', color: '#8a6d00' }
    }, '\u4f4e\u7f6e\u4fe1\u5ea6:\u672c\u5730\u5316\u6587\u672c\u8def\u5f84,\u8bb0\u4e3a\u964d\u7ea7'));
  }
  if (check.manualReview === true) {
    badges.push(React.createElement('span', {
      key: 'manual',
      style: { marginLeft: '6px', padding: '1px 4px', border: '1px solid #777777', borderRadius: '3px', fontSize: '11px', color: '#555555' }
    }, '\u9700\u4eba\u5de5\u5904\u7406'));
  }
  const children = [
    React.createElement('div', { key: 'head', style: { marginBottom: '2px' } },
      React.createElement('span', { style: { color: vstyle.color, fontWeight: 'bold', marginRight: '6px' } }, check.verdictLabel || vstyle.label),
      React.createElement('span', { style: { fontFamily: 'monospace', fontSize: '12px' } }, check.id),
      badges
    ),
    React.createElement('div', { key: 'reason', style: { fontSize: '13px' } }, check.reason),
    check.manualQuestion ? React.createElement('div', { key: 'mq', style: { fontSize: '12px', color: '#555555', marginTop: '2px' } }, check.manualQuestion) : null,
    check.remediationAction ? React.createElement('div', { key: 'ra', style: { fontSize: '12px', marginTop: '2px' } }, '\u4fee\u590d(\u7531\u4f60\u6267\u884c,\u672a\u5e94\u7528): ' + check.remediationAction) : null,
    check.remediationRollback ? React.createElement('div', { key: 'rr', style: { fontSize: '12px', color: '#555555' } }, '\u56de\u6eda: ' + check.remediationRollback) : null
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

  const controls = [];
  controls.push(React.createElement('label', { key: 'rolelabel', style: { fontSize: '12px', marginRight: '6px' } }, '\u89c6\u89d2:'));
  controls.push(React.createElement('select', {
    key: 'role',
    value: role,
    onChange: function (event) { setRole(event.target.value); },
    style: { fontSize: '12px', marginRight: '8px' }
  },
    React.createElement('option', { key: 'client', value: 'client' }, '\u5ba2\u6237\u7aef(\u8fd9\u53f0\u673a\u5668\u53ea\u7528\u8fd9\u6761\u94fe\u8def)'),
    React.createElement('option', { key: 'server', value: 'server' }, '\u670d\u52a1\u7aef(\u8fd9\u53f0\u673a\u5668\u63d0\u4f9b\u8fd9\u6761\u94fe\u8def)'),
    React.createElement('option', { key: 'both', value: 'both' }, '\u4e24\u8005')
  ));
  controls.push(React.createElement('button', {
    key: 'refresh',
    type: 'button',
    onClick: function () { setNonce(nonce + 1); },
    style: { fontSize: '12px' }
  }, state.phase === 'loading' ? '\u68c0\u67e5\u4e2d\u2026' : '\u5237\u65b0'));
  blocks.push(React.createElement('div', { key: 'controls', style: { marginBottom: '10px' } }, controls));
  blocks.push(React.createElement('div', { key: 'rolehint', style: { fontSize: '12px', color: '#666666', marginBottom: '10px' } },
    '\u7eaf\u5ba2\u6237\u7aef\u673a\u5668\u8bf7\u9009\u5ba2\u6237\u7aef\u89c6\u89d2:\u670d\u52a1\u7aef\u68c0\u67e5\u9879\u4e0d\u4f1a\u51fa\u73b0,\u6458\u8981\u4e5f\u5c31\u4e0d\u4f1a\u62a5\u4f60\u6ca1\u6709\u7684\u670d\u52a1\u7aef\u7f3a\u53e3\u3002'));

  if (state.phase === 'loading') {
    blocks.push(React.createElement('p', { key: 'loading' }, '\u6b63\u5728\u4e3b\u673a\u4e0a\u67e5\u8be2\u91c7\u96c6\u5668\u2026'));
  } else if (state.phase === 'failed') {
    blocks.push(React.createElement('p', { key: 'failed', style: { color: '#c0392b' } },
      '\u6682\u65e0\u59ff\u6001\u6570\u636e: ' + state.error));
    blocks.push(React.createElement('p', { key: 'hint', style: { fontSize: '12px', color: '#666666' } },
      '\u8fd9\u8bb0\u4e3a\u672a\u77e5\u3001\u7edd\u4e0d\u8bb0\u4e3a\u901a\u8fc7\u3002\u82e5\u63d0\u793a\u63d0\u5230\u8def\u7531\u6216\u91c7\u96c6\u5668\u8def\u5f84,\u8bf4\u660e host \u534a\u8fb9\u6ca1\u6709\u5728\u670d\u52a1:\u8981\u4e48\u90a3\u884c\u4ecd\u88ab\u7981\u7528,\u8981\u4e48\u8def\u7531\u6ce8\u518c\u5931\u8d25\u3002'));
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
      '\u5931\u6548\u5173\u95ed: ' + readString(summary.failClosed, '\u4efb\u4f55\u672a\u77e5\u90fd\u4e0d\u5141\u8bb8\u9000\u51fa 0')));
    blocks.push(React.createElement('div', { key: 'provenance', style: { fontSize: '11px', color: '#777777', marginBottom: '10px', fontFamily: 'monospace' } },
      '\u6765\u6e90=' + readString(payload.source, '\u672a\u77e5') +
      '  \u811a\u672c=' + readString(payload.script, '(\u672a\u62a5\u544a)') +
      '  \u751f\u6210=' + readString(summary.generatedAtLocal, '(\u672a\u77e5)')));

    const ordered = checks.slice(0).sort(function (left, right) {
      const delta = severityOf(left.verdict) - severityOf(right.verdict);
      if (delta !== 0) return delta;
      return String(left.id) < String(right.id) ? -1 : 1;
    });
    blocks.push(React.createElement('div', { key: 'itemsHead', style: { fontSize: '12px', color: '#666666', marginBottom: '4px' } },
      '\u5168\u90e8\u5224\u5b9a,\u6700\u4e25\u91cd\u5728\u524d(' + ordered.length + '):'));
    const rows = [];
    for (let index = 0; index < ordered.length; index += 1) rows.push(itemRow(ordered[index], ordered[index].id));
    blocks.push(React.createElement('ul', { key: 'items', style: { listStyle: 'none', paddingLeft: '0', margin: '0 0 12px 0' } }, rows));

    const manual = [];
    for (let index = 0; index < ordered.length; index += 1) {
      if (ordered[index].manualReview === true) manual.push(ordered[index]);
    }
    if (manual.length > 0) {
      blocks.push(React.createElement('div', { key: 'manualhead', style: { fontSize: '12px', fontWeight: 'bold', marginBottom: '4px' } },
        '\u53ea\u80fd\u7531\u4eba\u505a\u7684\u4e8b(\u6b64\u5904\u4ece\u4e0d\u52a8\u624b):'));
      const manualRows = [];
      for (let index = 0; index < manual.length; index += 1) {
        manualRows.push(React.createElement('li', { key: 'm' + manual[index].id, style: { fontSize: '12px', marginBottom: '3px' } },
          manual[index].id + ': ' + manual[index].manualQuestion));
      }
      blocks.push(React.createElement('ul', { key: 'manual', style: { marginTop: '0', marginBottom: '12px' } }, manualRows));
    }
  }

  blocks.push(React.createElement('div', { key: 'credhead', style: { fontSize: '12px', fontWeight: 'bold', marginBottom: '4px' } },
    '\u51ed\u636e\u7eaa\u5f8b\u4e0e\u4e0d\u6539\u52a8\u627f\u8bfa'));
  const notices = [];
  for (let index = 0; index < CREDENTIAL_NOTICES.length; index += 1) {
    notices.push(React.createElement('li', { key: 'c' + index, style: { fontSize: '12px', marginBottom: '2px' } }, CREDENTIAL_NOTICES[index]));
  }
  blocks.push(React.createElement('ul', { key: 'cred', style: { marginTop: '0', marginBottom: '0' } }, notices));

  return React.createElement('div', { style: { padding: '4px 0 8px 0' } }, blocks);
}

function GuardCard() {
  const openPair = React.useState(false);
  const open = openPair[0];
  const setOpen = openPair[1];
  const header = React.createElement('button', {
    type: 'button',
    className: 'dsh-rtg-card__header',
    'aria-expanded': open,
    onClick: function () { setOpen(!open); }
  },
    React.createElement('span', { className: 'dsh-rtg-card__head-text' },
      React.createElement('span', { className: 'dsh-rtg-card__name' }, CARD_TITLE),
      React.createElement('span', { className: 'dsh-rtg-card__desc' }, CARD_DESC)
    ),
    React.createElement('span', { className: 'dsh-rtg-card__chevron' + (open ? ' dsh-rtg-card__chevron--open' : '') }, '\u25be')
  );
  return React.createElement('li', { className: 'dsh-rtg-card' + (open ? ' dsh-rtg-card--open' : '') },
    header,
    open ? React.createElement('div', { className: 'dsh-rtg-card__body' }, React.createElement(GuardPanel, null)) : null
  );
}

function apply(ctx) {
  ctx.effect(function () {
    if (typeof document === 'undefined') return;
    if (document.getElementById(CSS_ID) !== null) return;
    const tag = document.createElement('style');
    tag.id = CSS_ID;
    tag.dataset.plugin = 'remote-tailnet-guard';
    tag.textContent = CARD_CSS;
    document.head.appendChild(tag);
    return function () { tag.remove(); };
  }, 'remote-tailnet-guard: settings card css');
  ctx.slots.inject('settings.plugin.item', function () {
    return ctx.slots.register(
      { name: 'settings.plugin.item', key: SETTINGS_NS, order: CARD_ORDER },
      function () { return React.createElement(GuardCard, null); }
    );
  });
}
// ==== SHARED BODY END ====
export const name = 'remote-tailnet-guard';
export const inject = ['slots'];
export { apply };