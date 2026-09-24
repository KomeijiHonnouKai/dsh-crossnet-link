/*
 * remote-tailnet-guard - HOST half of the persistent DSH plugin (t43, phase 1).
 * LAST UPDATED : 2026-09-25 (v0.3 - first-load auto-config: the host half now fills the four
 * machine-detectable settings (port/profile/dshHome/appDir) through the platform settings service,
 * one key at a time and never overwriting. v0.2 declared this plugin's own check parameters instead
 * of an empty schema and mapped the stored values onto the collector's argument list through
 * whitelists; v0.1 was the first persistent-plugin skeleton. The row that mounts this module ships
 * disabled: see plugin/cordis.patch.yml and docs/install/plugin-package.md).
 *
 * This file is a REAL ESM module of the installed package (package.json `main`), NOT the body of a
 * cordis_define call. It is loaded by the profile's own Loader row, not by the dynamic Package
 * runner. Evidence table (file + line) for every claim below is in docs/install/plugin-package.md.
 *
 * READ-ONLY CONTRACT (nothing here is optional):
 *   * it registers ONE read-only HTTP route on the EXISTING DSH web server (no new listener, no new
 *     bind address, no new port) - the same mechanism dsh-ego-browser uses for its own gateway;
 *   * the route only runs the repository's read-only collector
 *     (`src/collect.ps1 -CheckOnly -AsJson ...`). -CheckOnly never writes, and the collector itself
 *     installs nothing, opens no listener and reads no credential material;
 *   * every collector argument the route adds comes from this plugin's OWN settings namespace, and
 *     only after a whitelist walk (enums checked against their allowed set, free text rejected when
 *     it starts with "-" or carries control characters, numbers accepted only inside the schema
 *     bounds). A value can never become an argument the plugin did not intend to pass;
 *   * it returns leaf fields only (bounded checks + counts): raw probe output stays in the host
 *     process and never crosses to the page;
 *   * it installs nothing, changes no system setting and never restarts DSH;
 *   * its only settings writes go through the platform settings service, and only the first-load
 *     auto-fill of the four machine-detectable keys (per-key, and only while the key is absent -
 *     an existing value such as the user's `role: client` is never overwritten); otherwise it only
 *     DECLARES the schema, and the card's own saves are written by that same service.
 *
 * COMMANDS USED while writing this file (read-only; no client Inspect, no long waits):
 *   powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/panel/plugin-preflight.ps1
 *   powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1
 */
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const name = 'remote-tailnet-guard';

/** Route family served on the existing web server (prefix match, longest prefix wins). */
const ROUTE_PREFIX = '/remote-tailnet-guard/api';
/**
 * Settings namespace owned by this plugin. It is ALSO the key of the plugins-page card: the
 * configurable tab renders a `settings.plugin.item` card only while its key is a namespace the
 * Host has registered (dsh-client-ui-settings-plugins/lib/client.js:1144-1145 gates on the served
 * set, :416 renders one card per served namespace). Same string as the client half's SETTINGS_NS.
 */
const SETTINGS_NS = 'remote-tailnet-guard';
/**
 * The schema library is resolved AT RUNTIME and never through a static import. Reason (t46): this
 * package is installed with `link:`, so it has no node_modules of its own, and a static import of a
 * library that does not resolve would take this whole host half down with it. Both specifiers the
 * platform itself uses are tried; when neither resolves the namespace is simply not declared - the
 * card then does not render (fail closed) while every other part of this half keeps working.
 */
const SCHEMA_LIBRARY_SPECIFIERS = ['@deepseek-ai/schemastery', 'schemastery'];
/** The collector lives in the repository checkout that contains this package, resolved relatively. */
const COLLECTOR_REL = '../../src/collect.ps1';
/** Accepted -Role values; anything else falls back to 'both' instead of reaching the child process. */
const ROLES = ['client', 'server', 'both'];
/** Accepted -Strictness / -Lang values (collect.ps1 declares the same sets in its param block). */
const STRICTNESSES = ['normal', 'strict'];
const LANGS = ['auto', 'zh', 'en'];
/**
 * Settings field -> collector argument. One row per free-text parameter; the value is only passed
 * when it survives pickText(), and the length cap keeps a stored value from becoming an unbounded
 * argv element (the caps follow the usual limits for host names, profile names and Windows paths).
 */
const TEXT_ARGUMENTS = [
  { field: 'peer', flag: '-Peer', max: 253 },
  { field: 'peerName', flag: '-PeerName', max: 253 },
  { field: 'profile', flag: '-Profile', max: 64 },
  { field: 'tailnetDomain', flag: '-TailnetDomain', max: 253 },
  { field: 'dshHome', flag: '-DshHome', max: 260 },
  { field: 'appDir', flag: '-AppDir', max: 260 }
];
/** Settings field -> collector argument for the millisecond timeouts (bounds mirror the schema). */
const NUMBER_ARGUMENTS = [
  { field: 'tcpTimeoutMs', flag: '-TcpTimeoutMs', min: 1000, max: 60000, def: 5000 },
  { field: 'dnsTimeoutMs', flag: '-DnsTimeoutMs', min: 1000, max: 60000, def: 4000 },
  { field: 'commandTimeoutMs', flag: '-CommandTimeoutMs', min: 1000, max: 600000, def: 15000 }
];
/**
 * Settings bounds that exist nowhere else: the port has no default (absent means "work it out from
 * the environment"), so it is declared optional and accepted only inside the TCP port range.
 */
const PORT_FIELD = { field: 'port', flag: '-Port', min: 1, max: 65535 };
const BODY_MAX_BYTES = 16384;
const COLLECTOR_GRACE_MS = 120000;
const STDOUT_MAX_BYTES = 8388608;
const STDERR_MAX_BYTES = 262144;

function errorText(error) {
  return String(error && error.message ? error.message : error);
}

/** Log through the host logger when it exists, and stay silent when it does not. */
function logLine(ctx, level, message) {
  const logger = ctx && ctx.logger ? ctx.logger : null;
  if (logger === null) return;
  if (typeof logger[level] === 'function') logger[level](message);
}

/**
 * Resolve a schemastery-compatible schema factory, or null when none is reachable.
 * Never throws: an unresolvable library is a documented degradation, not a load failure.
 */
async function resolveSchemaLibrary(ctx) {
  for (let index = 0; index < SCHEMA_LIBRARY_SPECIFIERS.length; index += 1) {
    const specifier = SCHEMA_LIBRARY_SPECIFIERS[index];
    try {
      const loaded = await import(specifier);
      const candidate = loaded !== null && loaded.default !== undefined ? loaded.default : loaded;
      if (candidate !== null && candidate !== undefined && typeof candidate.object === 'function') return candidate;
    } catch (error) {
      logLine(ctx, 'warn', 'remote-tailnet-guard: schema library "' + specifier + '" is not reachable here: ' + errorText(error));
    }
  }
  return null;
}

function pickString(value, fallback) {
  if (typeof value !== 'string') return fallback;
  if (value.length === 0) return fallback;
  return value;
}

/** Whitelist the role argument: a request body must never become argv text of its own choosing. */
function pickRole(value) {
  if (typeof value === 'string') {
    for (let index = 0; index < ROLES.length; index += 1) {
      if (ROLES[index] === value) return value;
    }
  }
  return 'both';
}

/** Enum values only reach argv when they are one of the accepted words; anything else is dropped. */
function pickEnum(value, allowed, fallback) {
  if (typeof value === 'string') {
    for (let index = 0; index < allowed.length; index += 1) {
      if (allowed[index] === value) return value;
    }
  }
  return fallback;
}

/**
 * Free text only: empty, over-long, leading "-" (the child would read it as a parameter name) and
 * control characters are all dropped, so a stored value can never widen the child's own surface.
 */
function pickText(value, max) {
  if (typeof value !== 'string') return '';
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > max) return '';
  if (trimmed.charAt(0) === '-') return '';
  for (let index = 0; index < trimmed.length; index += 1) {
    const code = trimmed.charCodeAt(index);
    if (code < 32 || code === 127) return '';
  }
  return trimmed;
}

/** Integers inside the schema's own bounds; anything else (float, string, out of range) is dropped. */
function pickNumber(value, min, max) {
  if (typeof value !== 'number' || !Number.isFinite(value) || !Number.isInteger(value)) return null;
  if (value < min || value > max) return null;
  return value;
}

/**
 * This plugin's settings, as one schemastery schema. It is ALSO the wire envelope the browser-side
 * settings scope validates against, so every field stays expressible as plain schema JSON: only
 * enum (union of constants), string, boolean and number are used here.
 *
 * Field list (name -> the collector argument it feeds):
 *   role             -Role               which end of the link this machine is (client|server|both)
 *   peer             -Peer               the other end, MagicDNS name or IP (absent = not checked)
 *   peerName         -PeerName           peer MagicDNS name when -Peer was given as an address
 *   profile          -Profile            which DSH profile to read patch files from
 *   tailnetDomain    -TailnetDomain      this tailnet's DNS suffix (absent = built-in suffix match)
 *   strictness       -Strictness         normal | strict (strict turns more checks into blockers)
 *   noNative         -NoNative           skip the probes that need elevation
 *   lang             -Lang               report label language (auto | zh | en)
 *   port             -Port               this machine's DSH loopback port (absent = env, then built-in)
 *   tcpTimeoutMs     -TcpTimeoutMs       TCP probe timeout
 *   dnsTimeoutMs     -DnsTimeoutMs       name resolution timeout
 *   commandTimeoutMs -CommandTimeoutMs   per-command timeout
 *   dshHome          -DshHome            DSH data directory override
 *   appDir           -AppDir             DSH application directory override
 */
function settingsSchema(schemaFactory) {
  const fields = {
    role: schemaFactory.union(ROLES).default('both'),
    strictness: schemaFactory.union(STRICTNESSES).default('normal'),
    noNative: schemaFactory.boolean().default(false),
    lang: schemaFactory.union(LANGS).default('auto')
  };
  for (let index = 0; index < TEXT_ARGUMENTS.length; index += 1) {
    fields[TEXT_ARGUMENTS[index].field] = schemaFactory.string().default('');
  }
  for (let index = 0; index < NUMBER_ARGUMENTS.length; index += 1) {
    const row = NUMBER_ARGUMENTS[index];
    fields[row.field] = schemaFactory.number().step(1).min(row.min).max(row.max).default(row.def);
  }
  fields[PORT_FIELD.field] = schemaFactory.number().step(1).min(PORT_FIELD.min).max(PORT_FIELD.max).required(false);
  return schemaFactory.object(fields);
}

/** The settings service when this host has one; every read of it stays inside try/catch. */
function readSettings(ctx) {
  let service = null;
  try {
    service = ctx.get('settings');
  } catch (error) {
    service = null;
  }
  if (service === null || service === undefined || typeof service.get !== 'function') return null;
  try {
    const value = service.get(SETTINGS_NS);
    if (value === null || typeof value !== 'object') return null;
    return value;
  } catch (error) {
    return null;
  }
}

/** Trim a string candidate to a non-empty value inside the collector's length cap, else null. */
function pickDetected(value, max) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > max) return null;
  return trimmed;
}

/**
 * The four machine-detectable settings, probed with the SAME discovery chain the collector documents
 * in `-Describe` (src/collect.ps1:1055-1084) and resolves at src/collect.ps1:846-895 / :969-984.
 * Each probe returns a valid value, or null for "undetected" (the key is then left absent, never
 * guessed). The length caps mirror the collector argument whitelist in this file (TEXT_ARGUMENTS).
 */
function probeDshHome() {
  // -DshHome > $env:DSH_HOME > $env:USERPROFILE\.dsh   (collect.ps1:848-851)
  const fromEnv = pickDetected(process.env.DSH_HOME, 260);
  if (fromEnv !== null) return fromEnv;
  try {
    return pickDetected(join(homedir(), '.dsh'), 260);
  } catch (error) {
    return null;
  }
}

function probePort(ctx) {
  // The collector reads -Port > $env:DSH_WEB_URL > builtin 43120 (collect.ps1:859-861). The host
  // half can do better: its own web server's bound port is the value DSH_WEB_URL is derived from
  // (dsh-web-app/lib/index.js:96-100), so the port is measured rather than defaulted.
  try {
    const webServer = ctx.get('webServer');
    const port = webServer && typeof webServer.port === 'number' ? webServer.port : null;
    if (port !== null && Number.isInteger(port) && port >= 1 && port <= 65535) return port;
  } catch (error) {
    /* fall through to the collector's own env extraction */
  }
  const url = process.env.DSH_WEB_URL;
  if (typeof url === 'string' && url !== '') {
    const match = /:([0-9]{2,5})(\/|$)/.exec(url);
    if (match !== null) {
      const port = Number.parseInt(match[1], 10);
      if (Number.isInteger(port) && port >= 1 && port <= 65535) return port;
    }
  }
  return null;
}

function probeAppDir() {
  // -AppDir > $env:DSH_APP_DIR > the running DSH process image dir + \resources\app
  // (collect.ps1:970-983). process.execPath is that process image here; the auto-discovered
  // candidate is only accepted when it actually exists (same Test-Path guard as the collector).
  const fromEnv = pickDetected(process.env.DSH_APP_DIR, 260);
  if (fromEnv !== null) return fromEnv;
  try {
    const candidate = join(dirname(process.execPath), 'resources', 'app');
    if (!existsSync(candidate)) return null;
    return pickDetected(candidate, 260);
  } catch (error) {
    return null;
  }
}

function probeProfile(ctx) {
  // -Profile has no environment source in the collector (collect.ps1:893-895); the active profile
  // name comes from the Desktop profile service's context (profile-service: super(ctx,"desktopProfiles"),
  // `current.name`). No service, no name => null (left blank), never guessed.
  try {
    const profiles = ctx.get('desktopProfiles');
    const name = profiles && profiles.current ? profiles.current.name : null;
    return pickDetected(name, 64);
  } catch (error) {
    return null;
  }
}

/** Whether a plain object owns the key (the raw settings.yaml section, not the resolved value). */
function ownsKey(object, key) {
  return object !== null && typeof object === 'object' && !Array.isArray(object) &&
    Object.prototype.hasOwnProperty.call(object, key);
}

/**
 * Auto-configure the machine-detectable settings on first load. Runs once, after the namespace is
 * registered, and only ever SETS keys still absent from the user's settings.yaml section - an
 * existing value (including the user's `role: client`) is left exactly as it was. Writes go through
 * the platform settings service's mutate() path (the same one the plugins-page card save uses,
 * dsh-settings/lib/index.js:440-448), never by editing settings.yaml directly. An undetected value
 * or a failed write is only logged - never fatal to the load.
 */
async function autoFillSettings(ctx) {
  let settings = null;
  try {
    settings = ctx.get('settings');
  } catch (error) {
    settings = null;
  }
  if (settings === null || settings === undefined ||
      typeof settings.mutate !== 'function' || typeof settings.describe !== 'function') {
    logLine(ctx, 'warn', 'remote-tailnet-guard: auto-config skipped - settings service unavailable in this host');
    return;
  }

  let userSection = null;
  let revision;
  try {
    const descriptors = settings.describe();
    if (Array.isArray(descriptors)) {
      for (let index = 0; index < descriptors.length; index += 1) {
        const descriptor = descriptors[index];
        if (descriptor === null || descriptor === undefined || descriptor.ns !== SETTINGS_NS) continue;
        if (descriptor.user !== undefined && descriptor.user !== null &&
            typeof descriptor.user === 'object' && !Array.isArray(descriptor.user)) {
          userSection = descriptor.user;
        }
        if (typeof descriptor.revision === 'number') revision = descriptor.revision;
        break;
      }
    }
  } catch (error) {
    logLine(ctx, 'warn', 'remote-tailnet-guard: auto-config could not read the current section: ' + errorText(error));
    return;
  }

  const fields = [
    { key: 'dshHome', value: probeDshHome() },
    { key: 'port', value: probePort(ctx) },
    { key: 'appDir', value: probeAppDir() },
    { key: 'profile', value: probeProfile(ctx) }
  ];
  const ops = [];
  for (let index = 0; index < fields.length; index += 1) {
    const field = fields[index];
    if (field.value === null || field.value === undefined) {
      logLine(ctx, 'warn', 'remote-tailnet-guard: auto-config: "' + field.key + '" undetected, left blank');
      continue;
    }
    if (ownsKey(userSection, field.key)) {
      logLine(ctx, 'info', 'remote-tailnet-guard: auto-config: "' + field.key + '" already present, skipped');
      continue;
    }
    ops.push({ op: 'set', path: [field.key], value: field.value });
  }
  if (ops.length === 0) return;

  try {
    await settings.mutate(SETTINGS_NS, ops, revision);
    const keys = ops.map(function (op) { return op.path[0]; }).join(', ');
    logLine(ctx, 'info', 'remote-tailnet-guard: auto-config wrote ' + ops.length + ' machine setting(s) (' + keys + ') through the platform settings service');
  } catch (error) {
    logLine(ctx, 'warn', 'remote-tailnet-guard: auto-config write failed: ' + errorText(error));
  }
}

/**
 * The collector argument tail: every parameter this run passes beyond -CheckOnly -AsJson. The stored
 * settings are the source; when the namespace is not served (no schema library reachable, or no
 * settings service in this host) the request body's role is still honoured, so the route keeps
 * working exactly as it did before the settings existed.
 */
function argumentTail(settings, bodyRole) {
  const stored = settings === null ? {} : settings;
  const tail = ['-Role', pickEnum(stored.role, ROLES, pickRole(bodyRole))];
  const strictness = pickEnum(stored.strictness, STRICTNESSES, '');
  if (strictness !== '') tail.push('-Strictness', strictness);
  const lang = pickEnum(stored.lang, LANGS, '');
  if (lang !== '') tail.push('-Lang', lang);
  if (stored.noNative === true) tail.push('-NoNative');
  const port = pickNumber(stored[PORT_FIELD.field], PORT_FIELD.min, PORT_FIELD.max);
  if (port !== null) tail.push(PORT_FIELD.flag, String(port));
  for (let index = 0; index < TEXT_ARGUMENTS.length; index += 1) {
    const row = TEXT_ARGUMENTS[index];
    const text = pickText(stored[row.field], row.max);
    if (text !== '') tail.push(row.flag, text);
  }
  for (let index = 0; index < NUMBER_ARGUMENTS.length; index += 1) {
    const row = NUMBER_ARGUMENTS[index];
    const value = pickNumber(stored[row.field], row.min, row.max);
    if (value !== null) tail.push(row.flag, String(value));
  }
  return tail;
}

/** Evidence confidence lives on the check in one shape and on check.evidence in the other. */
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

/** One leaf-only projection of a check: no live object, no raw probe text, no credential material. */
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

/** Write a JSON reply on the existing server; the handler owns the whole response. */
function writeJson(res, status, payload) {
  const text = JSON.stringify(payload);
  if (res && typeof res.writeHead === 'function') res.writeHead(status, { 'content-type': 'application/json' });
  if (res && typeof res.end === 'function') res.end(text);
}

/** Read a small JSON body. Bounded on purpose: a plugin route is not a file upload seat. */
async function readJsonBody(req) {
  const chunks = [];
  let bytes = 0;
  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    bytes += buffer.length;
    if (bytes > BODY_MAX_BYTES) throw new Error('request body too large');
    chunks.push(buffer);
  }
  const text = Buffer.concat(chunks).toString('utf8');
  if (text === '') return {};
  const parsed = JSON.parse(text);
  if (parsed === null || typeof parsed !== 'object') return {};
  return parsed;
}

/** Same-origin only: a browser page on another origin must not be able to read this report. */
function guardOrigin(req) {
  const origin = req && req.headers ? req.headers.origin : undefined;
  if (typeof origin !== 'string' || origin.length === 0) return '';
  let originHost = '';
  try {
    originHost = new URL(origin).host;
  } catch (error) {
    return 'invalid Origin header';
  }
  const host = req && req.headers ? req.headers.host : undefined;
  if (typeof host !== 'string' || host.length === 0) return 'missing Host header';
  if (originHost !== host) return 'same-origin requests only';
  return '';
}

/**
 * Run the repository's read-only collector once, with the arguments built from this plugin's
 * settings, and return a bounded report.
 * Failure is always reported as `ok:false` + a machine-readable code - never as an empty pass.
 */
async function runCollector(ctx, collectorPath, tail) {
  if (!existsSync(collectorPath)) {
    return { ok: false, code: 'collector-missing', message: 'not found: ' + collectorPath };
  }
  const subprocess = ctx.get('subprocess');
  if (subprocess === undefined) {
    return { ok: false, code: 'no-subprocess', message: 'the subprocess service is unavailable in this host' };
  }
  let exe = '';
  try {
    exe = await subprocess.resolveExecutable('powershell.exe');
  } catch (error) {
    return { ok: false, code: 'powershell-missing', message: String(error && error.message ? error.message : error) };
  }
  const argv = [exe, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', collectorPath, '-CheckOnly', '-AsJson'].concat(tail);
  let handle = null;
  try {
    handle = subprocess.spawn({
      argv: argv,
      cwd: dirname(collectorPath),
      stdio: {
        stdin: 'ignore',
        stdout: { maxBytes: STDOUT_MAX_BYTES },
        stderr: { maxBytes: STDERR_MAX_BYTES }
      },
      graceMs: COLLECTOR_GRACE_MS
    });
  } catch (error) {
    return { ok: false, code: 'spawn-failed', message: String(error && error.message ? error.message : error) };
  }
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
    source: 'plugin:' + name,
    script: collectorPath,
    exitCode: outcome && typeof outcome.exitCode === 'number' ? outcome.exitCode : 0,
    summary: boundedSummary(report.summary, checks),
    checks: checks
  };
}

/**
 * Mount the read-only route. Everything lives inside ctx.effect, so disabling or unloading this row
 * removes the route again (webServer.register returns the disposer, dsh-host-webserver/lib/index.js:176-183).
 */
export function apply(ctx) {
  const moduleDir = dirname(fileURLToPath(import.meta.url));
  const collectorPath = resolve(join(moduleDir, COLLECTOR_REL));

  ctx.inject(['webServer'], function (wctx) {
    wctx.effect(function () {
      const webServer = wctx.get('webServer');
      if (webServer === undefined || typeof webServer.register !== 'function') {
        if (ctx.logger && typeof ctx.logger.warn === 'function') {
          ctx.logger.warn('remote-tailnet-guard: no webServer service - the settings section will report unknown, never a pass');
        }
        return undefined;
      }
      const dispose = webServer.register({
        kind: 'prefix',
        path: ROUTE_PREFIX,
        handler: async function (req, res) {
          try {
            if (String(req.method || '').toUpperCase() !== 'POST') {
              writeJson(res, 405, { ok: false, code: 'method-not-allowed', message: 'POST only' });
              return;
            }
            const originProblem = guardOrigin(req);
            if (originProblem !== '') {
              writeJson(res, 403, { ok: false, code: 'origin-not-allowed', message: originProblem });
              return;
            }
            const contentType = String((req.headers && req.headers['content-type']) || '').toLowerCase();
            if (!contentType.startsWith('application/json')) {
              writeJson(res, 415, { ok: false, code: 'content-type-not-supported', message: 'application/json required' });
              return;
            }
            const pathname = new URL(String(req.url || '/'), 'http://dsh.invalid').pathname;
            const method = pathname.indexOf(ROUTE_PREFIX + '/') === 0 ? pathname.slice(ROUTE_PREFIX.length + 1) : '';
            if (method !== 'posture') {
              writeJson(res, 404, { ok: false, code: 'not-found', message: 'unknown remote-tailnet-guard API method' });
              return;
            }
            const body = await readJsonBody(req);
            const tail = argumentTail(readSettings(ctx), body.role);
            const result = await runCollector(ctx, collectorPath, tail);
            writeJson(res, 200, result);
          } catch (error) {
            writeJson(res, 500, { ok: false, code: 'internal', message: String(error && error.message ? error.message : error) });
          }
        }
      });
      if (ctx.logger && typeof ctx.logger.info === 'function') {
        ctx.logger.info('remote-tailnet-guard: read-only posture route ready at ' + ROUTE_PREFIX + ' (collector ' + collectorPath + ')');
      }
      return function () {
        try {
          dispose();
        } catch (error) {
          /* already disposed */
        }
      };
    }, 'remote-tailnet-guard: read-only posture route on the existing web server');
  });

  // Plugins-page card seat (t46) + the settings the card edits (t47). The card the client half
  // registers under 'settings.plugin.item' is keyed by this namespace, and the configurable tab
  // renders it only for a SERVED namespace, so the namespace has to exist on this side. Properties:
  //   * the schema DECLARES this plugin's own check parameters (role, peer, profile, timeouts, ...):
  //     that declaration is what makes the card configurable and what every write is validated
  //     against, and the same values are read back in the route above to build the collector argv;
  //   * the card saves through the platform settings service; the only write this half ever issues
  //     is the first-load auto-config above, a single per-key mutate() for keys still absent - never
  //     update()/replace() and never a hand-edit of the settings document;
  //   * the whole step is optional and guarded: an unreachable schema library logs a warning and
  //     skips the registration instead of failing the load.
  ctx.effect(function () {
    let cancelled = false;
    ctx.inject(['settings'], function (sctx) {
      resolveSchemaLibrary(ctx).then(function (schemaFactory) {
        if (cancelled) return;
        if (schemaFactory === null) {
          logLine(ctx, 'warn', 'remote-tailnet-guard: no schema library reachable - settings namespace "' + SETTINGS_NS + '" skipped, so the plugins-page card will not render (everything else keeps working)');
          return;
        }
        try {
          sctx.settings.register(SETTINGS_NS, settingsSchema(schemaFactory), { base: {}, applies: 'live' });
          logLine(ctx, 'info', 'remote-tailnet-guard: settings namespace "' + SETTINGS_NS + '" registered with this plugin\'s check parameters (the plugins-page card can render and save them)');
          autoFillSettings(ctx).catch(function (error) {
            logLine(ctx, 'warn', 'remote-tailnet-guard: auto-config failed: ' + errorText(error));
          });
        } catch (error) {
          logLine(ctx, 'warn', 'remote-tailnet-guard: settings namespace "' + SETTINGS_NS + '" was refused: ' + errorText(error));
        }
      });
    });
    return function () { cancelled = true; };
  }, 'remote-tailnet-guard: settings namespace with this plugin\'s check parameters');
}
