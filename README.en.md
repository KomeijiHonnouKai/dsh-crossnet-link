# dsh-crossnet-link

**What this repository does**: read-only checkups for the link between two DSH machines
(posture and prerequisites), a read-only panel, a clean uninstall of the plugin. It is
report-only: installs nothing, forwards no traffic; both write paths are in P2.

**What it does not do**: this repository does not link the two machines itself, and
installing the plugin does not connect them either -- do not expect cross-network access
after installing it. The real linking steps live in the skill copy inside this repository,
`docs/install/skill/dsh-remote-tailnet/SKILL.md`.

[简体中文](README.md) · MIT

## 1 What this is

Four deliverables sharing one detection core:

| Deliverable | Entry | What it does |
| --- | --- | --- |
| Collector | `src/collect.ps1` | Checks link posture, four verdicts, exit 0/1/2 |
| Prerequisite checker | `panel/prereq.ps1` | Install planning; prints commands only |
| Plugin halves | `src/host-half.js` etc. | Read-only panel in the settings page |
| Uninstaller | `tools/uninstall.ps1` | Dry-run by default; clean rollback |

Compatible with Windows 10 or 11 and Windows PowerShell 5.1. No Node, Pester, or modules needed.
Evidence comes in three kinds, never mixed: live end-to-end runs, offline fixtures, static preflight.
What is not yet verified is listed in "6 Known limits".

**Glossary**
- tailnet: the private Tailscale network.
- serve: `tailscale serve` publishes a loopback port on the tailnet.
- ACL: the tailnet access policy.
- fixture: injected probe data, so tests run offline.
- journal: the ledger of changes the uninstaller recorded.
- remediation: the fix the tool suggests.
- profile: the DSH configuration set; patches live here.
- plugin line: one mount line in `cordis.patch.yml`.

## 2 Quick start

Four commands, all read-only, nothing to install.

1. Clone. The second argument is the local directory name, and it must be `dsh-crossnet-link`: the collector walks up from its base to that relative path and reports `collector-missing` otherwise.

```powershell
git clone https://github.com/KomeijiHonnouKai/dsh-crossnet-link dsh-crossnet-link
cd dsh-crossnet-link
```

Expect: clone succeeds, you are inside the directory.

2. Offline smoke, one command that proves itself.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-smoke.ps1
```

Expect: exit 0 all green; 1 means skips but no failures, normal on a clean machine; 2 has failures.

3. Read this machine's posture, read-only.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src\collect.ps1 -CheckOnly
```

Expect: header total=26. Without a peer address the link items report unknown;
a missing trustedHosts reports blocked. Exit 0 all pass, 1 degraded, 2 blocked.
On a fresh machine exit 2 is common; it is a verdict, not a failure.

4. Dry run before uninstall, writes nothing.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\uninstall.ps1 -Plan
```

Expect: on a fresh clone it refuses with journal_required, exit 2. That is by design, not a bug.
The full flow lives in `docs/install/uninstall.md`.
The four commands above install nothing; see section 5 to install or remove the plugin.
To link two machines for real, see `docs/install/link-guide.md`.

## 3 Reading the verdicts

Each check lands on one of four verdicts:

| Verdict | Meaning |
| --- | --- |
| `pass` | The property is proven on this machine |
| `degraded` | Partly true, or evidence from a weak path |
| `blocked` | Violated, or the collector cannot run |
| `unknown` | No probe can answer; never passed |

Verdicts are fail-closed: uncertainty is never reported as pass.
Strict mode lifts unknown to exit 2.

Exit codes:

| Exit | Meaning |
| --- | --- |
| `0` | Every check passed |
| `1` | At least one degraded or unknown |
| `2` | At least one blocked, or nothing judged |

Always call these scripts with `-File`. They set the exit code with exit N, and only `-File` keeps it;
`-Command` and dot-sourcing rewrite exit 2 into 1, hiding real blockers.

## 4 What it checks

The collector spans six groups: host, link, exposure, Tailscale, Windows power and firewall, self-audit.
The prerequisite checker targets install planning, one item per role with rollback.
Full criteria: `docs/collect.md` and `docs/install/prerequisites.md`.
Authoritative wording lives in `i18n/labels.zh.json` and `i18n/labels.en.json`;
expected verdicts for each injected fault live in the cases under `tests/cases/`.

## 5 Install, enable and remove
> **Installing this plugin does not link the two machines.** This repository only does
> read-only checkups, a read-only panel and a clean uninstall. Real linking steps:
> `docs/install/link-guide.md`.

Form 1, the default: a dynamic Cordis package that lives only in process memory.
It disappears on restart, so there is nothing to uninstall.
Entries: `src/host-half.js`, `panel/host-half.js` and `panel/client-half.js`;
steps in `docs/install/install.md`.

Form 2: the persistent plugin package `plugin/`.
Installing it writes into your own DSH profile, so this project only documents it and never installs it.
The single mount line defaults to `disabled: true`; installing it cannot break anything.
"Install" = three paste-ready commands that enable it in the same flow:
back up the profile patch -> `dsh plugin add link:` -> append the enable override line;
restart DSH afterwards and it shows as enabled in Settings > Plugins.
Run the read-only preflight `panel/plugin-preflight.ps1` before installing;
three steps and rollback live in `docs/install/plugin-package.md`;
the plain-language walkthrough for AI lives in `docs/install/agent-brief.md`.

Two ways of "seeing it":

- The line in the plugin list: installed into the profile, disabled lines included.
- The plugin card (a folded card "dsh-crossnet-link" under the Configurable tab):
  the host half registered the settings namespace the card keys on, and it opens as
  a settings form, not a posture report.
- The card is conditional: it appears when the profile can resolve the schema library
  (measured here: it does); when it cannot, only a warning is logged and the list line
  is unaffected.
- A sidebar tab is an integration surface. With dsh-better-sidebar installed, the tab is
  titled "dsh-crossnet-link" and opens a read-only posture panel. Without the sidebar,
  there is no tab, no error and no waiting, and Settings > Plugins keeps this one card.

Removal in three steps: set the line back to `disabled: true`, or delete it, or restore the whole file
from the backup you made before. Read the backup first; it may be an empty patch.
Long version: `docs/install/uninstall.md`.

## 6 Known limits

| Not verified | Current coverage |
| --- | --- |
| Live link with a Win11 client | Not measured (2026-09-25); fixtures + Win10 path only |
| Win11 to Win11 end to end | Not measured (2026-09-25); fixtures only |
| Silent failure on a Public NIC | Not measured (2026-09-25); derived from rules only |
| Server-side HTTPS certificate check | Not measured (2026-09-25); Node/OpenSSL probes |
| Persistent package, real DSH | Measured (2026-09-25); one load, both cells, info log |
| Panel card rendering | Namespace, card seat, sidebar tab: measured (2026-09-25, UI) |

Unverified rows say so, never upgraded; verified rows state date and evidence form.

## 7 FAQ

**Q1** Why exit 2 and a pile of unknown?
Without a peer address the link items cannot probe; in a sandboxed window the Tailscale CLI is denied too.
Those report unknown, as they should. A missing trustedHosts reports blocked.
Exit 2 is a fail-closed verdict, not a command failure.

**Q2** Why must I use `-File`?
The scripts set their exit code with exit N, and only `-File` preserves it.
`-Command` and dot-sourcing rewrite exit 2 into 1 and hide real blockers.

**Q3** The script says fine, but the browser cannot open the page?
TCP reachable is not TLS and HTTP working. Most often a system proxy hijacks the tailnet;
see the collector's `BROWSER_PROXY_TSNET`. It can also be a 401 from an expired cookie,
or a 403 from a missing server-side trustedHosts.

**Q4** Two machines, proxy on or off, four combinations. How to judge?
Each side only reports its own proxy posture, never guessing about the peer.
The client reads `BROWSER_PROXY_TSNET`;
the server reads `SERVER_PROXY_STATE` and `TAILNET_ROUTE_PRESENT`.
Process and fixes: `docs/install/prerequisites.md`.

**Q5** A non-zero prereq exit on a client-only machine, is that normal?
Yes. The default role checks both sides, and a client-only machine genuinely lacks server items.
Pass `-Role client` to see only what this side must satisfy.

**Q6** Will uninstall remove Tailscale or my firewall rules?
No. It only rolls back items recorded in its journal whose current value still equals what it produced.
Tailscale itself, other plugins and your own rules are kept; there is no code path that uninstalls Tailscale.

**Q7** No card in Settings > Plugins?
Form 1 lives in process memory only and vanishes on restart; define and run it again.
Form 2 needs a DSH restart after the three enable steps; the card is conditional, see the list above.
Failure modes: `docs/install/plugin-package.md`.
If none of these match, run `tests\run-smoke.ps1` for first-hand evidence and read its exit code.

## 8 Security and privacy

- **P1** No new network listeners, network routes or firewall rules: the only route this
  plugin registers is a read-only HTTP route on the existing web server (see P9), so the
  listening surface stays exactly DSH's own.
- **P2** Read-only by default; the only component that writes to the system surface is
  the uninstaller, dry-run by default. First load writes 4 settings.yaml keys
  via auto-config -- the plugin's only configuration side effect (see section 5).
- **P3** No automatic writes; `-Apply` is refused.
- **P4** Never reads, prints, stores or transmits credentials.
- **P5** No telemetry, no callbacks, no auto-update.
- **P6** No restart logic; never kills or relaunches the DSH host.
- **P7** Every side effect hangs off ctx.effect and can be removed completely.
- **P8** The panel is display-only; no write button.
- **P9** Routes registered on the existing web server skip DSH web auth. DSH listens on
  loopback by default, so the route is reachable from this machine only; publish the DSH
  port with `tailscale serve` and the same route becomes reachable from the tailnet (the
  same-origin check is void without an `Origin` header). It is read-only, returns posture
  results only, reads no credentials and is not RCE; the risk is a resource-consumption
  surface -- a peer can trigger the collector repeatedly.

Two conclusions from the threat model, `docs/threat-model.md`:
whoever can open that UI can operate that machine;
loopback is trusted by design, and this tool neither changes nor widens that.

Installer hash policy: no vendor hash is pinned in the repository.
Authenticode is verified, and optionally you compute and fill `pinnedSha256`
in `panel/prereq-manifest.json` yourself.
Until it is pinned, the step honestly reports blocked; the checker never downloads or runs anything.

## 9 Document index

- `docs/collect.md` collector criteria and implementation notes.
- `docs/install/prerequisites.md` prerequisites and the four proxy combinations.
- `docs/install/install.md` form 1 dynamic package steps.
- `docs/install/plugin-package.md` form 2 enable, verify, rollback.
- `docs/install/skill/dsh-remote-tailnet/SKILL.md` the full step-by-step linking skill.
- `docs/install/agent-brief.md` the install walkthrough for AI, with the chat output template.
- `docs/install/uninstall.md` the long six-step uninstall.
- `docs/install/rollback.md` rollback for each class of change.
- `docs/threat-model.md` who can see what, and do what.
- `docs/evidence.md` the evidence ledger: measured, cited, not yet verified.
- `docs/decisions.md` open items and deliberate decisions.
- `SECURITY.md` security promises and their verification commands.

## 10 License and contributing

License: **MIT**. `LICENSE` carries the full text and the copyright line.
Read `CONTRIBUTING.md` before contributing; report security issues through `SECURITY.md`,
never as a public issue.
