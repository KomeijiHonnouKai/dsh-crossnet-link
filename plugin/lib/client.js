/*
 * remote-tailnet-guard - CLIENT half of the persistent DSH plugin - BROWSER BUNDLE.
 * LAST UPDATED : 2026-09-25 (v0.5 - this half ALSO registers one OPTIONAL dsh-better-sidebar tab
 * (id dsh-crossnet-link:posture, order 60, single): a read-only posture view over the host half's
 * own route, read only while the panel is visible. The sidebar service is reached with ctx.get and
 * ctx.inject, never with a declared dependency, so an absent sidebar changes nothing else here.
 * v0.4 - the plugins-page card became a SETTINGS card. Its body is the
 * plugin's own settings form (14 fields, staged drafts, save/discard) over the Host settings
 * namespace; the posture report it used to dump is gone. The header shows the display name
 * dsh-crossnet-link and the plugin purpose from the handover note, and every UI string is Chinese.)
 *
 * WHY THIS FILE IS A BUNDLE AND NOT PLAIN ESM: every client half in this DSH release is served to
 * the page as a classic script that must REGISTER itself with window.__ModuleLoader__.load({id,
 * factory}) - the module system throws "bundle ... loaded without registering ... via
 * __ModuleLoader__.load" when a fetched bundle does not (dsh-client-modules/lib/client.js:248), and
 * its synchronous require only resolves platform seed words or already-materialized rows
 * (dsh-client-modules/lib/client.js:300-310). Both real installed plugins on this machine ship
 * exactly this shape (dsh-ego-browser/lib/client.js, @nanmicoder/dsh-agent-teams/lib/client.js).
 *
 * The only external this bundle requires is the platform seed "react". The seed table is built by
 * the Web shell (dsh-web-frontend/dist/assets/index-*.js) and contains react, react/jsx-runtime,
 * react-dom, react-dom/client, @deepseek-ai/cordis, @deepseek-ai/dsh-client-store,
 * @deepseek-ai/dsh-client-ui-slots, @deepseek-ai/dsh-client-ui-primitives and
 * @deepseek-ai/dsh-client-ui-dockkit. Everything else stays inside this file: the settings scope is
 * reached as the ordinary cordis service "settingsScope" through ctx.get / ctx.inject, which is a
 * service lookup rather than a module dependency, so nothing else has to be required here.
 *
 * The region between the two SHARED BODY markers is byte-identical to the ESM source of the same
 * half (lib/client/index.js); panel/plugin-preflight.ps1 fails if the two ever drift apart.
 */
window.__ModuleLoader__.load({ id: "remote-tailnet-guard", factory: (require) => {
var module = { exports: {} }; var exports = module.exports;
var React = require("react");
// ==== SHARED BODY BEGIN (byte-identical in lib/client.js and lib/client/index.js) ====
const SETTINGS_NS = 'remote-tailnet-guard';
const CARD_ORDER = 100;
const CSS_ID = 'dsh-rtg-card-css';
const CARD_TITLE = 'dsh-crossnet-link';
const CARD_DESC = '\u5728 A \u7535\u8111\u7684 DSH \u91cc,\u901a\u8fc7\u6d4f\u89c8\u5668\u63d2\u4ef6\u9a71\u52a8\u4e00\u4e2a\u5df2\u767b\u5f55\u7684\u901a\u9053\u9875\u9762,\u76f4\u63a5\u64cd\u4f5c B \u7535\u8111\u4e0a\u8fd0\u884c\u7684 DSH \u2014\u2014 \u4e24\u53f0 DSH \u7531\u6b64\u5f62\u6210\u8054\u52a8(agent \u5bf9 agent)\u3002';
const SCOPE_LINE = '\u672c\u673a\u53ea\u8bfb\u4f53\u68c0:\u53ea\u62a5\u4e0d\u6539,\u4e0d\u88c5\u4efb\u4f55\u4e1c\u897f\u3001\u4e0d\u6539\u4efb\u4f55\u914d\u7f6e\u3001\u4e0d\u91cd\u542f DSH\u3002';
const UNAVAILABLE_LINE = '\u8bbe\u7f6e\u670d\u52a1\u4e0d\u53ef\u7528:\u8fd9\u4e2a\u9875\u9762\u8bfb\u4e0d\u5230\u672c\u63d2\u4ef6\u7684\u8bbe\u7f6e\u547d\u540d\u7a7a\u95f4\u3002';
const READONLY_LINE = '\u53ea\u8bfb:\u672c\u673a\u8bbe\u7f6e\u6587\u6863\u5f53\u524d\u4e0d\u53ef\u5199\u3002';
const UNSAVED_LINE = '\u6709\u672a\u4fdd\u5b58\u7684\u4fee\u6539\u3002';
const SAVING_LINE = '\u4fdd\u5b58\u4e2d\u2026';
const SAVED_LINE = '\u5df2\u4fdd\u5b58\u3002';
const REJECTED_LINE = '\u4fdd\u5b58\u6ca1\u6709\u751f\u6548:\u4e3b\u673a\u6ca1\u6709\u63a5\u53d7\u8fd9\u4e9b\u503c\u3002';
const OVERRIDE_MARK = ' \u00b7 \u5df2\u8986\u76d6';
const RESET_LABEL = '\u6062\u590d\u9ed8\u8ba4';
const SAVE_LABEL = '\u4fdd\u5b58';
const DISCARD_LABEL = '\u653e\u5f03';
/**
 * better-sidebar tab (v0.5). A SECOND, read-only surface beside the settings card: the card keeps
 * editing this plugin's check parameters, while the tab renders the posture the host route returns.
 * dsh-better-sidebar is an OPTIONAL service - see apply(): the tab is registered through ctx.get
 * and never through a declared dependency, so an absent sidebar changes nothing else here.
 */
const SIDEBAR_TAB_ID = 'dsh-crossnet-link:posture';
const SIDEBAR_TAB_ORDER = 60;
const TAB_CSS_ID = 'dsh-rtg-tab-css';
/** The host half serves its read-only posture route under the SAME namespace, so one rename moves both. */
const POSTURE_ROUTE = '/' + SETTINGS_NS + '/api/posture';
const TAB_HINT_LINE = '\u53ea\u8bfb\u59ff\u6001:\u672c\u673a\u94fe\u8def\u4f53\u68c0\u7684\u8bfb\u6570\u4e0e\u5224\u5b9a(\u9762\u677f\u4e0d\u53ef\u89c1\u65f6\u4e0d\u8bf7\u6c42)\u3002';
const TAB_IDLE_LINE = '\u5c1a\u672a\u8bfb\u53d6\u3002';
const TAB_LOADING_LINE = '\u8bfb\u53d6\u4e2d\u2026';
const TAB_READY_LINE = '\u5df2\u8bfb\u53d6\u3002';
const TAB_FAIL_PREFIX = '\u8bfb\u53d6\u5931\u8d25: ';
const TAB_EMPTY_LINE = '\u8fd9\u4e00\u6b21\u6ca1\u6709\u68c0\u67e5\u9879\u3002';
const REFRESH_LABEL = '\u5237\u65b0';
const TOTAL_LABEL = '\u603b\u6570';
const EXIT_LABEL = '\u9000\u51fa\u7801';
const PASS_LABEL = '\u901a\u8fc7';
const DEGRADED_LABEL = '\u964d\u7ea7';
const BLOCKED_LABEL = '\u963b\u65ad';
const UNKNOWN_LABEL = '\u672a\u77e5';
const GENERATED_LABEL = '\u91c7\u96c6\u65f6\u95f4';
const CARD_CSS = '.dsh-rtg-card{border:1px solid var(--dsw-alias-border-l2);background:var(--dsw-alias-bg-layer-3);border-radius:12px;list-style:none;transition:border-color .16s,background .16s}.dsh-rtg-card:hover{border-color:var(--dsw-alias-label-dimmed)}.dsh-rtg-card--open{background:var(--dsw-alias-bg-layer-2);border-color:var(--dsw-alias-label-dimmed)}.dsh-rtg-card__header{appearance:none;width:100%;font:inherit;color:inherit;text-align:left;cursor:pointer;background:0 0;border:0;border-radius:12px;align-items:center;gap:12px;padding:14px 16px;display:flex}.dsh-rtg-card__header:focus-visible{outline:2px solid var(--dsw-alias-brand-primary);outline-offset:-2px}.dsh-rtg-card__head-text{flex-direction:column;flex:1;gap:4px;min-width:0;display:flex}.dsh-rtg-card__name{color:var(--dsw-alias-label-primary);font-size:15px;font-weight:600;line-height:1.4}.dsh-rtg-card__desc{color:var(--dsw-alias-label-tertiary);font-size:13px;line-height:1.5}.dsh-rtg-card__chevron{color:var(--dsw-alias-label-tertiary);flex:none;transition:transform .16s;display:inline-flex;align-items:center}.dsh-rtg-card__chevron--open{transform:rotate(180deg)}.dsh-rtg-card__body{border-top:1px solid var(--dsw-alias-border-l2);margin:0 16px;padding:12px 0 4px}.dsh-rtg-card__form{flex-direction:column;gap:14px;display:flex}.dsh-rtg-line{color:var(--dsw-alias-label-tertiary);font-size:12px;line-height:1.6;margin:0}.dsh-rtg-group{flex-direction:column;gap:10px;display:flex}.dsh-rtg-group__title{color:var(--dsw-alias-label-secondary);font-size:12px;font-weight:600}.dsh-rtg-field{flex-direction:column;gap:3px;display:flex}.dsh-rtg-field__label{flex-direction:column;gap:3px;display:flex}.dsh-rtg-field__label--check{flex-direction:row;align-items:center;gap:8px}.dsh-rtg-field__row{align-items:center;gap:8px;display:flex}.dsh-rtg-field__control{font:inherit;font-size:13px;color:var(--dsw-alias-label-primary);background:var(--dsw-alias-bg-layer-4);border:1px solid var(--dsw-alias-border-l3);border-radius:6px;padding:5px 8px;min-width:240px;max-width:340px}.dsh-rtg-field__control:disabled{opacity:.6}.dsh-rtg-field--invalid .dsh-rtg-field__control{border-color:var(--dsw-alias-label-error)}.dsh-rtg-field__reset{appearance:none;font:inherit;font-size:12px;color:var(--dsw-alias-brand-primary);background:0 0;border:0;cursor:pointer;padding:0}.dsh-rtg-field__reset:disabled{color:var(--dsw-alias-label-dimmed);cursor:default}.dsh-rtg-field__hint{color:var(--dsw-alias-label-tertiary);font-size:12px;line-height:1.5}.dsh-rtg-footer{border-top:1px solid var(--dsw-alias-border-l2);align-items:center;gap:8px;margin-top:2px;padding-top:10px;display:flex}.dsh-rtg-footer__status{flex:1;color:var(--dsw-alias-label-tertiary);font-size:12px}.dsh-rtg-footer__status--error{color:var(--dsw-alias-label-error)}.dsh-rtg-button{appearance:none;font:inherit;font-size:13px;color:var(--dsw-alias-label-primary);background:var(--dsw-alias-bg-layer-4);border:1px solid var(--dsw-alias-border-l3);border-radius:6px;cursor:pointer;padding:5px 12px}.dsh-rtg-button--primary{background:var(--dsw-alias-brand-primary);border-color:var(--dsw-alias-brand-primary);color:var(--dsw-alias-label-primary-inverted)}.dsh-rtg-button:disabled{opacity:.5;cursor:default}';
/**
 * Skin-neutral styles for the sidebar tab body: every colour is a --dsw-alias-* design token, so
 * the tab follows the active skin like the card does. The root claims the full height the native
 * tab host gives it (flex:1 + height:100% + min-height:0); the pane body is a block scroller, not a
 * flex container, so a root that only leans on the outer flex collapses to its content height.
 */
const TAB_CSS = '.dsh-rtg-tab{box-sizing:border-box;display:flex;flex-direction:column;gap:10px;height:100%;min-height:0;padding:12px 14px;background:var(--dsw-alias-bg-layer-1);color:var(--dsw-alias-label-primary)}.dsh-rtg-tab__hint{margin:0;flex:none;font-size:12px;line-height:1.6;color:var(--dsw-alias-label-tertiary)}.dsh-rtg-tab__bar{flex:none;align-items:center;gap:8px;display:flex}.dsh-rtg-tab__state{flex:1;min-width:0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary)}.dsh-rtg-tab__state--error{color:var(--dsw-alias-state-error-primary)}.dsh-rtg-tab__body{flex:1;min-height:0;overflow:auto;display:flex;flex-direction:column;gap:8px}.dsh-rtg-tab__summary{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 12px;font-size:12px;line-height:1.6}.dsh-rtg-tab__summary-verdict{font-weight:600;color:var(--dsw-alias-label-primary)}.dsh-rtg-tab__summary-item{color:var(--dsw-alias-label-tertiary)}.dsh-rtg-tab__check{display:flex;flex-direction:column;gap:2px;padding:8px 10px;border:1px solid var(--dsw-alias-border-l2);border-radius:8px;background:var(--dsw-alias-bg-layer-2)}.dsh-rtg-tab__check-head{display:flex;align-items:baseline;gap:8px}.dsh-rtg-tab__check-title{font-size:12px;font-weight:600;color:var(--dsw-alias-label-primary)}.dsh-rtg-tab__check-role{font-size:11px;color:var(--dsw-alias-label-dimmed)}.dsh-rtg-tab__check-verdict{margin-left:auto;font-size:11px;font-weight:600}.dsh-rtg-tab__check-line{margin:0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary)}.dsh-rtg-verdict--pass{color:var(--dsw-alias-state-success-primary)}.dsh-rtg-verdict--degraded{color:var(--dsw-alias-state-warn-primary)}.dsh-rtg-verdict--blocked{color:var(--dsw-alias-state-error-primary)}.dsh-rtg-verdict--unknown{color:var(--dsw-alias-label-tertiary)}';
/**
 * The card's settings surface. Every field name here is a field of the Host-side schema for
 * SETTINGS_NS (plugin/lib/index.js), and every default repeats what that schema declares - the
 * schema stays the authority for what a write actually lands; `def` is only what the reset control
 * shows before the next read-back.
 */
const SETTINGS_GROUPS = [
  {
    key: 'position',
    title: '\u672c\u673a\u5728\u8fd9\u6761\u94fe\u8def\u91cc\u7684\u4f4d\u7f6e',
    fields: [
      {
        field: 'role',
        kind: 'select',
        label: '\u672c\u673a\u89c6\u89d2',
        def: 'both',
        hint: '\u8fd9\u53f0\u673a\u5668\u5728\u8fd9\u6761\u94fe\u8def\u91cc\u662f\u54ea\u4e00\u7aef;\u9009\u5ba2\u6237\u7aef\u65f6\u670d\u52a1\u7aef\u68c0\u67e5\u9879\u4e0d\u51fa\u73b0,\u6458\u8981\u4e5f\u5c31\u4e0d\u4f1a\u62a5\u4f60\u6ca1\u6709\u7684\u670d\u52a1\u7aef\u7f3a\u53e3\u3002',
        options: [
          { value: 'both', label: '\u4e24\u8005' },
          { value: 'client', label: '\u5ba2\u6237\u7aef(\u8fd9\u53f0\u673a\u5668\u53ea\u7528\u8fd9\u6761\u94fe\u8def)' },
          { value: 'server', label: '\u670d\u52a1\u7aef(\u8fd9\u53f0\u673a\u5668\u63d0\u4f9b\u8fd9\u6761\u94fe\u8def)' }
        ]
      }
    ]
  },
  {
    key: 'peer',
    title: '\u5bf9\u7aef\u4e0e tailnet',
    fields: [
      {
        field: 'peer',
        kind: 'text',
        label: '\u5bf9\u7aef\u5730\u5740',
        def: '',
        maxLength: 253,
        hint: '\u5bf9\u7aef\u7684 MagicDNS \u540d\u6216 IP;\u7559\u7a7a\u5c31\u4e0d\u6838\u5bf9\u5bf9\u7aef\u76f8\u5173\u7684\u68c0\u67e5\u9879\u3002 \u00b7 \u9700\u624b\u586b'
      },
      {
        field: 'peerName',
        kind: 'text',
        label: '\u5bf9\u7aef MagicDNS \u540d',
        def: '',
        maxLength: 253,
        hint: '\u5f53\u4e0a\u9762\u586b\u7684\u662f IP,\u6216\u8005\u9700\u8981\u6838\u5bf9\u53ef\u4fe1\u4e3b\u673a\u540d\u65f6,\u586b\u8fd9\u4e00\u9879\u3002 \u00b7 \u9700\u624b\u586b'
      },
      {
        field: 'profile',
        kind: 'text',
        label: '\u672c\u673a DSH profile',
        def: '',
        maxLength: 64,
        hint: '\u4ece\u54ea\u4e2a profile \u8bfb patch \u6587\u4ef6;\u7559\u7a7a\u65f6\u591a profile \u4f1a\u8bb0 unknown,\u91c7\u96c6\u5668\u4e0d\u4f1a\u66ff\u4f60\u9009\u7b2c\u4e00\u4e2a\u3002 \u00b7 \u672c\u673a\u5df2\u81ea\u52a8\u63a2\u6d4b'
      },
      {
        field: 'tailnetDomain',
        kind: 'text',
        label: 'Tailnet \u57df\u540d',
        def: '',
        maxLength: 253,
        hint: '\u8fd9\u6761 tailnet \u7684 DNS \u540e\u7f00;\u7559\u7a7a\u5c31\u7528\u5185\u7f6e\u7684\u540e\u7f00\u6a21\u5f0f\u3002'
      }
    ]
  },
  {
    key: 'scope',
    title: '\u4f53\u68c0\u53e3\u5f84',
    fields: [
      {
        field: 'strictness',
        kind: 'select',
        label: '\u5224\u5b9a\u4e25\u683c\u5ea6',
        def: 'normal',
        hint: '\u4e25\u683c\u6a21\u5f0f\u4f1a\u628a\u66f4\u591a\u68c0\u67e5\u9879\u5224\u4e3a\u963b\u65ad\u3002',
        options: [
          { value: 'normal', label: '\u666e\u901a' },
          { value: 'strict', label: '\u4e25\u683c' }
        ]
      },
      {
        field: 'noNative',
        kind: 'boolean',
        label: '\u7981\u7528\u539f\u751f\u63a2\u6d4b',
        def: false,
        hint: '\u53d7\u9650\u73af\u5883\u6216\u975e\u7ba1\u7406\u5458\u4f1a\u8bdd\u91cc,\u8df3\u8fc7\u9700\u8981\u63d0\u5347\u6743\u9650\u7684\u539f\u751f\u63a2\u6d4b\u3002'
      },
      {
        field: 'lang',
        kind: 'select',
        label: '\u62a5\u544a\u8bed\u8a00',
        def: 'auto',
        hint: '\u62a5\u544a\u6807\u7b7e\u7684\u8bed\u8a00;\u8ddf\u968f\u7cfb\u7edf\u7531\u7cfb\u7edf\u7684\u672c\u5730\u5316\u7a0b\u5ea6\u51b3\u5b9a\u3002',
        options: [
          { value: 'auto', label: '\u8ddf\u968f\u7cfb\u7edf' },
          { value: 'zh', label: '\u4e2d\u6587' },
          { value: 'en', label: 'English' }
        ]
      },
      {
        field: 'port',
        kind: 'number',
        label: '\u672c\u673a DSH \u7aef\u53e3',
        def: '',
        min: 1,
        max: 65535,
        hint: '\u672c\u673a DSH \u7684 loopback \u7aef\u53e3;\u7559\u7a7a\u6309\u73af\u5883\u53d8\u91cf\u4e0e\u5185\u7f6e\u9ed8\u8ba4\u503c\u5224\u65ad\u3002 \u00b7 \u672c\u673a\u5df2\u81ea\u52a8\u63a2\u6d4b'
      }
    ]
  }
];
/** Folded away by default: the values a slow machine or a slow link needs, not the everyday ones. */
const ADVANCED_GROUP = {
  key: 'advanced',
  title: '\u9ad8\u7ea7',
  fields: [
    {
      field: 'tcpTimeoutMs',
      kind: 'number',
      label: 'TCP \u63a2\u6d4b\u8d85\u65f6(\u6beb\u79d2)',
      def: 5000,
      min: 1000,
      max: 60000,
      hint: '\u6162\u7f51\u6216\u6162\u673a\u5668\u4e0a\u52a0\u5927\u5b83,\u907f\u514d\u628a\u7b49\u5f85\u8bfb\u6210\u5931\u8d25\u3002'
    },
    {
      field: 'dnsTimeoutMs',
      kind: 'number',
      label: 'DNS \u67e5\u8be2\u8d85\u65f6(\u6beb\u79d2)',
      def: 4000,
      min: 1000,
      max: 60000,
      hint: '\u89e3\u6790 MagicDNS \u540d\u7684\u65f6\u95f4\u4e0a\u9650\u3002'
    },
    {
      field: 'commandTimeoutMs',
      kind: 'number',
      label: '\u547d\u4ee4\u8d85\u65f6(\u6beb\u79d2)',
      def: 15000,
      min: 1000,
      max: 600000,
      hint: '\u672c\u673a\u5355\u6761\u547d\u4ee4\u7684\u65f6\u95f4\u4e0a\u9650\u3002'
    },
    {
      field: 'dshHome',
      kind: 'text',
      label: 'DSH home \u76ee\u5f55',
      def: '',
      maxLength: 260,
      hint: 'DSH \u7684\u6570\u636e\u76ee\u5f55;\u7559\u7a7a\u6309\u73af\u5883\u53d8\u91cf\u4e0e\u5185\u7f6e\u9ed8\u8ba4\u503c\u63a2\u6d4b\u3002 \u00b7 \u672c\u673a\u5df2\u81ea\u52a8\u63a2\u6d4b'
    },
    {
      field: 'appDir',
      kind: 'text',
      label: 'DSH \u5e94\u7528\u76ee\u5f55',
      def: '',
      maxLength: 260,
      hint: 'DSH \u5e94\u7528\u7684\u5b89\u88c5\u76ee\u5f55;\u7559\u7a7a\u6309\u5185\u7f6e\u9ed8\u8ba4\u503c\u63a2\u6d4b\u3002 \u00b7 \u672c\u673a\u5df2\u81ea\u52a8\u63a2\u6d4b'
    }
  ]
};
/** Every editable field, in card order: the plan builder and the save writer walk this once. */
const FIELD_SPECS = (function () {
  const all = [];
  const groups = SETTINGS_GROUPS.concat([ADVANCED_GROUP]);
  for (let groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
    const fields = groups[groupIndex].fields;
    for (let fieldIndex = 0; fieldIndex < fields.length; fieldIndex += 1) all.push(fields[fieldIndex]);
  }
  return all;
})();

function readString(value, fallback) {
  if (typeof value === 'string' && value.length > 0) return value;
  return fallback;
}

function hasOwn(object, key) {
  return object !== null && typeof object === 'object' && Object.prototype.hasOwnProperty.call(object, key);
}

/** The text a control shows for a field that is not being edited: the Host-resolved value. */
function fieldText(spec, snapshot) {
  const value = snapshot === null || snapshot.value === undefined || snapshot.value === null ? undefined : snapshot.value[spec.field];
  if (spec.kind === 'boolean') return value === true;
  if (value === undefined || value === null) return '';
  return String(value);
}

/**
 * One draft text -> what a save would write, or undefined when the field does not accept it.
 * The same bounds the Host schema declares are checked here, so an invalid draft is marked in
 * place instead of being sent and silently dropped.
 */
function parseField(spec, text) {
  if (spec.kind === 'boolean') return { set: text === true };
  const trimmed = typeof text === 'string' ? text.trim() : '';
  if (trimmed === '') return { clear: true };
  if (spec.kind === 'number') {
    if (!/^[0-9]+$/.test(trimmed)) return undefined;
    const parsed = Number(trimmed);
    if (!Number.isFinite(parsed)) return undefined;
    if (spec.min !== undefined && parsed < spec.min) return undefined;
    if (spec.max !== undefined && parsed > spec.max) return undefined;
    return { set: parsed };
  }
  if (spec.kind === 'select') {
    for (let index = 0; index < spec.options.length; index += 1) {
      if (spec.options[index].value === trimmed) return { set: trimmed };
    }
    return undefined;
  }
  if (trimmed.charAt(0) === '-') return undefined;
  if (spec.maxLength !== undefined && trimmed.length > spec.maxLength) return undefined;
  return { set: trimmed };
}

/** Staged drafts -> the path operations a save would send. An empty text means "drop the override". */
function buildPlan(staged, snapshot) {
  const ops = [];
  const invalid = [];
  for (let index = 0; index < FIELD_SPECS.length; index += 1) {
    const spec = FIELD_SPECS[index];
    const entry = staged[spec.field];
    if (entry === undefined) continue;
    const parsed = parseField(spec, entry.text);
    if (parsed === undefined) {
      invalid.push(spec.field);
      continue;
    }
    const unchanged = entry.clear !== true && String(entry.text) === String(fieldText(spec, snapshot));
    if (unchanged) continue;
    if (entry.clear === true || parsed.clear === true) ops.push({ op: 'unset', path: [spec.field] });
    else ops.push({ op: 'set', path: [spec.field], value: parsed.set });
  }
  return { ops: ops, invalid: invalid };
}

/** The Host is the only authority on whether a write was accepted: read the user layer back. */
function landedAll(ops, user) {
  for (let index = 0; index < ops.length; index += 1) {
    const field = ops[index].path[0];
    if (ops[index].op === 'set') {
      if (!hasOwn(user, field) || user[field] !== ops[index].value) return false;
    } else if (hasOwn(user, field)) {
      return false;
    }
  }
  return ops.length > 0;
}

function renderControl(spec, text, writable, stage) {
  if (spec.kind === 'boolean') {
    return React.createElement('input', {
      key: 'control',
      type: 'checkbox',
      className: 'dsh-rtg-field__check',
      checked: text === true,
      disabled: !writable,
      onChange: function () { stage(spec.field, { text: text !== true, clear: false }); }
    });
  }
  const change = function (event) { stage(spec.field, { text: event.target.value, clear: false }); };
  if (spec.kind === 'select') {
    const options = [];
    for (let index = 0; index < spec.options.length; index += 1) {
      options.push(React.createElement('option', { key: spec.options[index].value, value: spec.options[index].value }, spec.options[index].label));
    }
    return React.createElement('select', {
      key: 'control',
      className: 'dsh-rtg-field__control',
      value: text,
      disabled: !writable,
      onChange: change
    }, options);
  }
  const numeric = spec.kind === 'number';
  return React.createElement('input', {
    key: 'control',
    type: numeric ? 'number' : 'text',
    className: 'dsh-rtg-field__control',
    value: text,
    disabled: !writable,
    spellCheck: false,
    placeholder: numeric && spec.def === '' ? '\u81ea\u52a8' : '',
    min: numeric ? spec.min : undefined,
    max: numeric ? spec.max : undefined,
    step: numeric ? 1 : undefined,
    onChange: change
  });
}

function renderField(spec, snapshot, staged, stage, writable) {
  const entry = staged[spec.field];
  const text = entry === undefined ? fieldText(spec, snapshot) : entry.text;
  const invalid = entry !== undefined && entry.clear !== true && parseField(spec, entry.text) === undefined;
  const overridden = hasOwn(snapshot.user, spec.field);
  const label = spec.label + (overridden ? OVERRIDE_MARK : '');
  const reset = React.createElement('button', {
    key: 'reset',
    type: 'button',
    className: 'dsh-rtg-field__reset',
    disabled: !writable || (entry === undefined && !overridden),
    onClick: function () { stage(spec.field, { text: spec.def, clear: true }); }
  }, RESET_LABEL);
  const row = [];
  if (spec.kind === 'boolean') {
    row.push(renderControl(spec, text, writable, stage));
    row.push(React.createElement('span', { key: 'label', className: 'dsh-rtg-field__label-text' }, label));
  } else {
    row.push(renderControl(spec, text, writable, stage));
  }
  row.push(reset);
  return React.createElement('div', {
    key: spec.field,
    className: 'dsh-rtg-field' + (invalid ? ' dsh-rtg-field--invalid' : '')
  },
    React.createElement('label', {
      className: 'dsh-rtg-field__label' + (spec.kind === 'boolean' ? ' dsh-rtg-field__label--check' : '')
    },
      spec.kind === 'boolean' ? null : React.createElement('span', { key: 'label', className: 'dsh-rtg-field__label-text' }, label),
      React.createElement('span', { key: 'row', className: 'dsh-rtg-field__row' }, row)
    ),
    React.createElement('div', { className: 'dsh-rtg-field__hint' }, spec.hint)
  );
}

function renderGroup(group, snapshot, staged, stage, writable) {
  const fields = [];
  for (let index = 0; index < group.fields.length; index += 1) {
    fields.push(renderField(group.fields[index], snapshot, staged, stage, writable));
  }
  const title = React.createElement('span', { className: 'dsh-rtg-group__title' }, group.title);
  if (group.key !== 'advanced') {
    return React.createElement('div', { key: group.key, className: 'dsh-rtg-group' }, title, fields);
  }
  return React.createElement('details', { key: group.key, className: 'dsh-rtg-group' },
    React.createElement('summary', { className: 'dsh-rtg-group__title' }, group.title),
    fields
  );
}

function SettingsForm(props) {
  const scope = props.scope;
  const snapshotPair = React.useState(scope === null ? null : scope.getSnapshot());
  const snapshot = snapshotPair[0];
  const setSnapshot = snapshotPair[1];
  const stagedPair = React.useState({});
  const staged = stagedPair[0];
  const setStaged = stagedPair[1];
  const statusPair = React.useState({ saving: false, saved: false, error: '' });
  const status = statusPair[0];
  const setStatus = statusPair[1];

  React.useEffect(function () {
    if (scope === null) return undefined;
    setSnapshot(scope.getSnapshot());
    return scope.subscribe(function () { setSnapshot(scope.getSnapshot()); });
  }, [scope]);

  if (scope === null || snapshot === null || snapshot.status !== 'ready') {
    return React.createElement('p', { className: 'dsh-rtg-line' }, UNAVAILABLE_LINE);
  }

  const writable = snapshot.writable === true;
  const plan = buildPlan(staged, snapshot);
  const dirty = plan.ops.length > 0 || plan.invalid.length > 0;

  function stage(field, entry) {
    const next = {};
    const keys = Object.keys(staged);
    for (let index = 0; index < keys.length; index += 1) next[keys[index]] = staged[keys[index]];
    next[field] = entry;
    setStaged(next);
    setStatus({ saving: false, saved: false, error: '' });
  }

  function save() {
    if (!writable || status.saving || plan.invalid.length > 0 || plan.ops.length === 0) return;
    const ops = plan.ops;
    setStatus({ saving: true, saved: false, error: '' });
    scope.mutate(ops).then(function () {
      const after = scope.getSnapshot();
      const landed = landedAll(ops, after === null ? null : after.user);
      if (landed) setStaged({});
      setStatus({ saving: false, saved: landed, error: landed ? '' : REJECTED_LINE });
    }, function (error) {
      setStatus({ saving: false, saved: false, error: '\u4fdd\u5b58\u5931\u8d25: ' + readString(error && error.message, 'unknown error') });
    });
  }

  function discard() {
    setStaged({});
    setStatus({ saving: false, saved: false, error: '' });
  }

  let statusText = '';
  if (status.error !== '') statusText = status.error;
  else if (status.saving) statusText = SAVING_LINE;
  else if (dirty) statusText = UNSAVED_LINE;
  else if (status.saved) statusText = SAVED_LINE;

  const blocks = [];
  blocks.push(React.createElement('p', { key: 'scope', className: 'dsh-rtg-line' }, SCOPE_LINE));
  for (let index = 0; index < SETTINGS_GROUPS.length; index += 1) {
    blocks.push(renderGroup(SETTINGS_GROUPS[index], snapshot, staged, stage, writable));
  }
  blocks.push(renderGroup(ADVANCED_GROUP, snapshot, staged, stage, writable));
  blocks.push(React.createElement('div', { key: 'footer', className: 'dsh-rtg-footer' },
    React.createElement('button', {
      type: 'button',
      className: 'dsh-rtg-button dsh-rtg-button--primary',
      disabled: !writable || !dirty || status.saving || plan.invalid.length > 0,
      onClick: save
    }, SAVE_LABEL),
    React.createElement('button', {
      type: 'button',
      className: 'dsh-rtg-button',
      disabled: !dirty || status.saving,
      onClick: discard
    }, DISCARD_LABEL),
    React.createElement('span', {
      className: 'dsh-rtg-footer__status' + (status.error !== '' ? ' dsh-rtg-footer__status--error' : '')
    }, writable ? statusText : READONLY_LINE)
  ));
  return React.createElement('div', { className: 'dsh-rtg-card__form' }, blocks);
}

function GuardCard(props) {
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
    open ? React.createElement('div', { className: 'dsh-rtg-card__body' }, React.createElement(SettingsForm, { scope: props.scope })) : null
  );
}

/**
 * Read the posture through the plugin's own read-only host route: POST, JSON in, leaf fields out.
 * A failed read is always reported as an error line - never as an empty panel that looks green.
 */
function loadPosture() {
  if (typeof fetch !== 'function') {
    return Promise.reject(new Error('fetch is unavailable on this page'));
  }
  return fetch(POSTURE_ROUTE, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{}',
    credentials: 'same-origin'
  }).then(function (response) {
    return response.json().then(function (payload) {
      return payload;
    }, function () {
      throw new Error('the posture route answered HTTP ' + response.status + ' without a JSON body');
    });
  });
}

/** Only these four verdicts exist; anything else is reported as unknown, never as a pass. */
function verdictKey(verdict) {
  if (verdict === 'pass' || verdict === 'degraded' || verdict === 'blocked') return verdict;
  return 'unknown';
}

/** Numbers arrive as numbers; anything else prints as a dash rather than as a fake zero. */
function countText(value) {
  return typeof value === 'number' ? String(value) : '-';
}

/** One bounded check: title + role + verdict first, then the reason and the remediation line. */
function PostureCheck(props) {
  const check = props.check;
  const lines = [];
  const reason = readString(check.reason, '');
  const remediation = readString(check.remediationAction, '');
  const role = readString(check.role, '');
  if (reason !== '') lines.push(React.createElement('p', { key: 'reason', className: 'dsh-rtg-tab__check-line' }, reason));
  if (remediation !== '') lines.push(React.createElement('p', { key: 'remediation', className: 'dsh-rtg-tab__check-line' }, remediation));
  return React.createElement('div', { className: 'dsh-rtg-tab__check' },
    React.createElement('div', { className: 'dsh-rtg-tab__check-head' },
      React.createElement('span', { className: 'dsh-rtg-tab__check-title' }, readString(check.title, readString(check.id, ''))),
      role === '' ? null : React.createElement('span', { className: 'dsh-rtg-tab__check-role' }, role),
      React.createElement('span', {
        className: 'dsh-rtg-tab__check-verdict dsh-rtg-verdict--' + verdictKey(check.verdict)
      }, readString(check.verdictLabel, 'UNKNOWN'))
    ),
    lines
  );
}

/**
 * The sidebar tab body. It reads once when the panel becomes visible and again on demand, and a
 * hidden panel (`visible === false`) issues no request at all - the performance gate the sidebar
 * contract asks for. The posture stays read-only: nothing here writes, installs or restarts.
 */
function PostureTab(props) {
  const visible = props.visible !== false;
  const statePair = React.useState({ phase: 'idle', data: null, error: '' });
  const state = statePair[0];
  const setState = statePair[1];
  const tickPair = React.useState(0);
  const tick = tickPair[0];
  const setTick = tickPair[1];

  React.useEffect(function () {
    if (!visible) return undefined;
    let cancelled = false;
    setState(function (previous) { return { phase: 'loading', data: previous.data, error: '' }; });
    loadPosture().then(function (payload) {
      if (cancelled) return;
      const ok = payload !== null && typeof payload === 'object' && payload.ok === true;
      setState({
        phase: 'ready',
        data: ok ? payload : null,
        error: ok ? '' : readString(payload && (payload.message || payload.code), 'unknown failure')
      });
    }, function (error) {
      if (cancelled) return;
      setState({ phase: 'ready', data: null, error: readString(error && error.message, 'request failed') });
    });
    return function () { cancelled = true; };
  }, [visible, tick]);

  const summary = state.data === null ? null : state.data.summary;
  const checks = state.data !== null && Array.isArray(state.data.checks) ? state.data.checks : [];
  let stateText = TAB_IDLE_LINE;
  if (state.error !== '') stateText = TAB_FAIL_PREFIX + state.error;
  else if (state.phase === 'loading') stateText = TAB_LOADING_LINE;
  else if (summary !== null && summary !== undefined) stateText = TAB_READY_LINE;

  const bar = React.createElement('div', { className: 'dsh-rtg-tab__bar' },
    React.createElement('span', {
      className: 'dsh-rtg-tab__state' + (state.error !== '' ? ' dsh-rtg-tab__state--error' : '')
    }, stateText),
    React.createElement('button', {
      type: 'button',
      className: 'dsh-rtg-button',
      disabled: state.phase === 'loading',
      onClick: function () { setTick(tick + 1); }
    }, REFRESH_LABEL)
  );

  const body = [];
  if (summary !== null && summary !== undefined) {
    body.push(React.createElement('div', { key: 'summary', className: 'dsh-rtg-tab__summary' },
      React.createElement('span', { className: 'dsh-rtg-tab__summary-verdict' }, readString(summary.verdictLabel, 'UNKNOWN')),
      React.createElement('span', { className: 'dsh-rtg-tab__summary-item' },
        TOTAL_LABEL + ' ' + countText(summary.total) + ' \u00b7 ' + PASS_LABEL + ' ' + countText(summary.pass) +
        ' \u00b7 ' + DEGRADED_LABEL + ' ' + countText(summary.degraded) + ' \u00b7 ' + BLOCKED_LABEL + ' ' + countText(summary.blocked) +
        ' \u00b7 ' + UNKNOWN_LABEL + ' ' + countText(summary.unknown)),
      React.createElement('span', { className: 'dsh-rtg-tab__summary-item' }, EXIT_LABEL + ' ' + countText(summary.exitCode)),
      readString(summary.generatedAtLocal, '') === '' ? null
        : React.createElement('span', { className: 'dsh-rtg-tab__summary-item' }, GENERATED_LABEL + ' ' + summary.generatedAtLocal)
    ));
  }
  for (let index = 0; index < checks.length; index += 1) {
    body.push(React.createElement(PostureCheck, { key: 'check:' + String(index), check: checks[index] }));
  }
  if (checks.length === 0 && state.phase !== 'loading') {
    body.push(React.createElement('p', { key: 'empty', className: 'dsh-rtg-line' }, TAB_EMPTY_LINE));
  }

  return React.createElement('div', { className: 'dsh-rtg-tab' },
    React.createElement('p', { className: 'dsh-rtg-tab__hint' }, TAB_HINT_LINE),
    bar,
    React.createElement('div', { className: 'dsh-rtg-tab__body' }, body)
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
  ctx.effect(function () {
    if (typeof document === 'undefined') return undefined;
    if (document.getElementById(TAB_CSS_ID) !== null) return undefined;
    const tag = document.createElement('style');
    tag.id = TAB_CSS_ID;
    tag.dataset.plugin = 'remote-tailnet-guard';
    tag.textContent = TAB_CSS;
    document.head.appendChild(tag);
    return function () { tag.remove(); };
  }, 'remote-tailnet-guard: sidebar tab css');
  // Reads and writes go through the platform's own per-namespace scope: staged drafts, revision
  // fencing, and the read-back that decides whether a write landed all belong to it, and the
  // namespace stays the one the Host registers. The service is optional here (the card only ever
  // renders under the settings UI that provides it) and the service name is resolved with ctx.get
  // rather than a declared dependency, so this half keeps `inject = ['slots']`.
  let scope = null;
  function bindScope() {
    if (scope !== null) return scope;
    const service = typeof ctx.get === 'function' ? ctx.get('settingsScope') : undefined;
    if (service === undefined || service === null || typeof service.bind !== 'function') return null;
    try {
      scope = service.bind({ namespace: SETTINGS_NS });
    } catch (error) {
      scope = null;
    }
    return scope;
  }
  bindScope();
  if (scope === null && typeof ctx.inject === 'function') {
    ctx.inject(['settingsScope'], function () { bindScope(); });
  }
  ctx.slots.inject('settings.plugin.item', function () {
    return ctx.slots.register(
      { name: 'settings.plugin.item', key: SETTINGS_NS, order: CARD_ORDER },
      function () { return React.createElement(GuardCard, { scope: bindScope() }); }
    );
  });

  // dsh-better-sidebar is an OPTIONAL peer: the service is read with ctx.get, and this half never
  // declares `inject = ['betterSidebar']` - a hard dependency would park the whole plugin in
  // "waiting" whenever the sidebar is absent, and the settings card has to render either way. The
  // direct call covers "sidebar already up"; ctx.inject covers "sidebar comes up later" (the
  // callback runs once the service exists). Registration itself stays inside ctx.effect, so
  // disabling or reloading this row takes the tab and its disposer away with it.
  let sidebarRegistered = false;
  function registerSidebarTab(activeCtx) {
    if (sidebarRegistered) return true;
    const service = activeCtx && typeof activeCtx.get === 'function' ? activeCtx.get('betterSidebar') : undefined;
    if (service === null || service === undefined || typeof service.registerTab !== 'function') return false;
    sidebarRegistered = true;
    activeCtx.effect(function () {
      return service.registerTab({
        id: SIDEBAR_TAB_ID,
        title: CARD_TITLE, // resolves to 'dsh-crossnet-link' - the plugin display name (same string as the card header)
        order: SIDEBAR_TAB_ORDER,
        single: true,
        component: function (tabProps) { return React.createElement(PostureTab, tabProps); }
      });
    }, 'remote-tailnet-guard: better-sidebar tab');
    return true;
  }
  if (registerSidebarTab(ctx) === false && typeof ctx.inject === 'function') {
    ctx.inject(['betterSidebar'], function (sidebarCtx) { registerSidebarTab(sidebarCtx); });
  }
}
// ==== SHARED BODY END ====
exports.name = "remote-tailnet-guard";
exports.inject = ["slots"];
exports.apply = apply;
return module.exports; } });
