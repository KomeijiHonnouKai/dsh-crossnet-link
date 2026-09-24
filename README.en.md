# remote-tailnet-guard

**中文版 / Chinese edition: [README.md](README.md)** - the Chinese original, which the repository shows by default; this file is the English original.

> LAST UPDATED  : 2026-09-24 (captain closeout - the GitHub account `KomeijiHonnouKai` was filled into
>                 the clone URL, so §17.4's last open item is closed; the GitHub account and the
>                 copyright holder name are the same name (`KomeijiHonnouKai`); before that, task t39 - `tools/`
>                 joined the published release set, §17 gained an uninstall row, §21 documents the
>                 uninstaller's six steps, four classifications, exit codes and the read-only promise
>                 boundary; the stale activation and licence wordings were closed too)
> COMMANDS USED : `powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json`
>                 `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
>                 `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-fixtures.ps1`
>                 `Select-String -Path README.en.md -Pattern 'uninstall'`
>                 `powershell -NoProfile -Command '(Select-String -Path README.en.md -SimpleMatch <the repository name> | Measure-Object).Count'` - expect **1** (the clone URL below is its single source of truth; this header therefore refers to it by description, not by literal)

## Contents

**Preamble**: [What it is for](#what-it-is-for) · [Plugin GUI: the three forms it ships in](#plugin-gui-the-three-forms-it-ships-in) · [How it was built, and by whom](#how-it-was-built-and-by-whom)

**Part I - the checker**: [1. What it is](#1-what-it-is) · [2. What it checks](#2-what-it-checks) · [3. What it deliberately does not do](#3-what-it-deliberately-does-not-do) · [4. Install](#4-install) · [5. Usage](#5-usage) · [6. Support matrix](#6-support-matrix-the-four-windows-combinations) · [7. Security posture](#7-security-posture) · [8. Repository layout and release set](#8-repository-layout-and-release-set) · [9. CI and repository hygiene](#9-ci-and-repository-hygiene) · [10. Residual identifiers](#10-residual-identifiers-in-the-release-set) · [11. Versioning and release steps](#11-versioning-tags-and-release-steps) · [12. Contributing and license](#12-contributing-and-license)

**Part II - activation, evidence and closing**: [Part II heading](#part-ii--detection-contract-activation-wake-up-to-dos-and-evidence-chain-task-t9) · [13. Detection items](#13-detection-items-and-what-each-one-actually-judges) · [14. Path A](#14-activating-the-plugin--path-a-dynamic-cordis-package-the-default) · [15. Path B](#15-path-b--the-persistent-plugin-package-optional-needs-your-explicit-approval) · [16. The four Windows combinations](#16-the-four-windows-combinations--prerequisites-and-traps) · [17. Wake-up to-dos](#17-wake-up-to-dos--the-things-only-a-human-can-do) · [18. Evidence chain](#18-evidence-chain-measured-here-cited-from-other-tasks-still-unverified) · [19. Open items](#19-open-items-and-deliberate-decisions-please-do-not-fix-these) · [20. Delivery checklist](#20-delivery-checklist-and-the-three-commands-a-stranger-needs) · [21. Uninstall and residue](#21-uninstall-and-residue--complete-clean-and-never-silent)

---

## What it is for

**In one line**: inside the DSH on machine A, a browser plugin (ego-browser and the like) drives an
already-authenticated channel page to operate the DSH running on machine B - the two DSH instances then
act as one linked pair, agent to agent. This repository covers the posture check for that link and its
prerequisites, the read-only panel, and a complete clean uninstall. It does not build that link; it
judges what posture the link is in right now, which prerequisites are still missing, and how to remove
it cleanly.

**The prerequisite link that makes that page reachable from A** (the only design it recognises - the
one that was measured end to end):

1. the two machines are **not on the same network** (one at the office and one at home, say);
2. both join the **same tailnet** (Tailscale's private network);
3. on the server machine DSH listens on **loopback only**, and `tailscale serve --bg` exposes that port
   on the tailnet's 443;
4. the tailnet ACL is **narrowed** to admit only client -> server `tcp:443`; every other server port
   stays closed;
5. the browser on the client machine opens that address **once, with a one-time token**, and receives a
   long-lived cookie in exchange;
6. from then on, the browser plugin on A drives that channel page (already authenticated, so no
   further token) and thereby operates the DSH running on B - the two DSH instances are linked,
   agent to agent. Which is also why **being able to open that page equals being able to operate that
   machine** (§7).

**Which link in the chain this repository is**:

| Link in the chain | Where it lives |
| --- | --- |
| the how-to for building the link | the `dsh-remote-tailnet` skill, **not in this repository** |
| the **read-only verdict** on the link's current posture (four states, fail-closed exit codes) | `src/collect.ps1` here (24 checks) |
| the **prerequisite check** (installed? signed in? does a human still have to act?) | `panel/prereq.ps1` + `panel/prereq-manifest.json` here (13 items) |
| the **read-only panel inside the DSH settings page** | `panel/client-half.js` + `panel/host-half.js` here |
| the **uninstaller** that removes it completely and cleanly (dry-run by default) | `tools/uninstall.ps1` here (§21) |

**The boundary, in one line**: it is **not** remote-control software, it is **not** a proxy, it
**forwards no traffic**, and it **changes none of your settings**. It reads and reports; whether and how
to fix anything is your call, and every suggestion ships with its rollback.

## Plugin GUI: the three forms it ships in

**The GUI exists** - it is one read-only panel, titled `Remote access link (read-only posture)`,
showing the read-only posture (the four states `pass / degraded / blocked / unknown`), the
credential-discipline notices and the promise that nothing is changed. The panel is a **display only**
- it carries no write button.

It ships in **three forms**; all three render that same panel, and they differ in **which seat they
register** and **how long they live**:

| # | form | how it loads | seat it registers | lifetime |
|---|---|---|---|---|
| 1 | **dynamic Cordis package** (the default) | `cordis_define` + `cordis_run` from `panel/host-half.js` + `panel/client-half.js`; see §14 | `settings.section` - a read-only section inside the settings page | **process memory only** - a restart makes it disappear, nothing is written to disk, so there is nothing to uninstall |
| 2 | **persistent plugin package** (`plugin/`, published) - the settings-page **section** | `plugin/package.json` (`type: module`, `main: ./lib/index.js`, `exports["./client"]` → `./lib/client.js`, a `dsh.client` block, `dsh.bundle.patch`) plus the mount row in `plugin/cordis.patch.yml`; see §15 | `settings.section` (id `remote-tailnet-guard`, order 100, label `Remote access link (read-only posture)`) | on disk: it survives a restart until the row is removed |
| 3 | the same persistent package - the **card** on DSH's "Settings → Plugins" page | the same package, the same mount row, the same client half | `settings.plugin.item`, **keyed** by `SETTINGS_NS` = `'remote-tailnet-guard'` = the package name; the host half registers a settings namespace with that same name (an **empty** schema) so the seat owner renders the card | on disk, exactly like form 2 |

Form 1's registration is in `panel/client-half.js`:
`ctx.slots.register({ name:'settings.section', id:'remote-tailnet-guard', order:100, label:'Remote access link (read-only posture)' }, …)` inside `ctx.slots.inject('settings.section', …)`. Forms 2 and 3 come from one client half (`plugin/lib/client.js`, duplicated byte-for-byte in `plugin/lib/client/index.js`) plus the host half `plugin/lib/index.js`: the section seat is the same one form 1 registers, and the card seat is registered beside it as `ctx.slots.register({ name:'settings.plugin.item', key: SETTINGS_NS, order: 100 }, …)` inside `ctx.slots.inject('settings.plugin.item', …)` (`plugin/lib/client.js:251-256`, section at `:242-247`).

**The card is a seat, not an entitlement - it is implemented, and still unverified.** The card seat
ships inside the package (t46), but **nobody has loaded this package in a real DSH** (see §19.2 and the
unverified list in [`docs/install/plugin-package.md`](docs/install/plugin-package.md) §9). It has one
gate that is easy to trip: the card `key` is **not** an arbitrary string - the owner renders one card
per **served** settings namespace, so the key must equal a settings namespace the host half actually
**registered** (`ctx.settings.register`), which is why both halves declare `SETTINGS_NS` =
`'remote-tailnet-guard'` = the package name. When that registration does not happen (sharpest case: a
`link:` install where the schema library cannot be resolved at run time) the package logs a warning,
the card simply **does not appear**, and **everything else keeps working**. Recorded failure modes and
what they look like: `docs/install/plugin-package.md` §9 item 7.

**All three forms are inert until you say so.** Forms 2 and 3 are one package behind one mount row,
and that row ships **`disabled: true`** - the only `- insert:` block in `plugin/cordis.patch.yml`
holds exactly one row, so neither the section nor the card can appear before you enable it.

**Why form 2 is a second, opt-in step and ships `disabled: true`.** Installing it writes into **your
own** DSH profile (`dsh plugin --profile <name> add <the package>` installs the package and reconciles
it into the profile's bundle list) and that one row affects **every session** of that profile; a wrong
client entry parks the whole GUI in "Failed to load plugins" recovery mode (a real trap recorded in
this machine's `AGENTS.md`, not a theoretical risk). So the single mount row in
`plugin/cordis.patch.yml` is **disabled by default**: while it stays disabled the loader never starts
the row and the client-module scan skips disabled entries - both anchors are recorded in that file's
own comment (`cordis-plugin-loader/lib/index.js:391`, `dsh-client-modules/lib/index.js:778`) - so
installing the package **does nothing at all** until you enable it. Enable it only after the read-only
preflight is green (`panel/plugin-preflight.ps1`, exit codes 0/1/2), and prefer a **throwaway profile**
for the first run.

**The preflight, measured (this revision).** `panel/plugin-preflight.ps1` is the read-only gate for
forms 2 and 3. These numbers come from re-running it on 2026-09-24, not from an earlier README:

```powershell
# the gate: 66 assertions, 0 failed, 3 skipped (node is not on PATH on this machine), exit 0
powershell -NoProfile -ExecutionPolicy Bypass -File panel/plugin-preflight.ps1
#   checks: 66  passed: 66  failed: 0 (blocking: 0, advisory: 0)  skipped: 3
#   exit code: 0   contract: 0 = all blocking checks passed (skips allowed) | 1 = advisory findings only | 2 = blocking finding or nothing judged

# the fault-injection self-test: 7 injected faults, all 7 matched, exit 0
powershell -NoProfile -ExecutionPolicy Bypass -File panel/plugin-preflight.ps1 -SelfTest
#   self-test: 7 cases  matched: 7  mismatched: 0

# the release-set hygiene gate: CLEAN, 110 files under the default roots, exit 0
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
#   files     : 110 under those roots (release set by default)
#   verdict: CLEAN (0 blocking finding(s))
```

**The exit-code contract, and the calling convention it depends on**: `0` = every blocking check
passed (registered skips are printed, never silent, and do not change the code), `1` = advisory
findings only, `2` = a blocking finding **or nothing could be judged** (fail closed: an unreadable or
unparsable input ends as `2`, and an internal `trap` converges any unexpected exception to `2`).
**Always call the script with `-File`**: it sets its code with `exit N`, and PowerShell only preserves
that under `-File` - `-Command "& '<script>'"` and dot-sourcing were measured to rewrite the code to
**`1`**, which would hide a real `2`.

**First action when it goes wrong**: put the row back to `disabled: true` (or delete those three lines)
and restart DSH from its own menu; if the GUI is already broken, restore the whole `cordis.patch.yml`
from the step-1 backup. That is [`docs/install/plugin-package.md`](docs/install/plugin-package.md) §6
(four-step rollback) and §7 (the first action); §5 of the same file is the three-step enable and §4 the
read-only preflight.

**What is verified and what is not**: the package's shape, encodings, single disabled row, both seat
registrations and the byte-identical client shared body are covered by the offline preflight (66
assertions, above) and by the static case `tests/cases/plugin-package-shape/`; **loading it in a real
DSH has not been verified**, and neither has the card rendering - that needs you to enable the row
(§15, or the throwaway-profile route in `docs/install/plugin-package.md` §8). Keep the three sightings
apart, exactly as `docs/install/plugin-package.md` §9 does: **the section appearing** = the skeleton
loaded; **the row appearing in the plugin inventory** = the row really landed in the profile (a
disabled row is listed there too); **the card appearing** = the host half successfully registered the
settings namespace the card is keyed by.

Activation, observation points, success/failure criteria and rollback: §14 (form 1, the default) and
§15 (forms 2 and 3, which need your explicit authorisation).

## How it was built, and by whom

This section states plainly **how this repository was produced**: which software, which plugins, and
which steps a human performed.

**In one line**: the repository was **implemented end to end by AI** (code, documents, tests and the
self-checks), while **a human owned the requirements, the naming and licence decisions and the final
acceptance**, and personally performed the machine-level actions. One model was used throughout:
`deepseek-official/deepseek-v4-flash-vision-exp` (DeepSeek V4 Flash).

1. **Runtime**: DSH Desktop 2.0.13 (an Electron application whose UI is served on `127.0.0.1:43120`);
   Windows 10 / Windows 11 with Windows PowerShell 5.1. Every script in the repository has **zero
   external dependencies** - no Node, no Pester, no module of any kind; when `node` is not on `PATH`
   the preflight prints `[SKIP]` and the exit code does not move.
2. **Model**: `deepseek-official/deepseek-v4-flash-vision-exp` (DeepSeek V4 Flash), used for every
   inference in this project - there was no second line.
3. **How the multi-agent work was organised**: the **AgentTeams plugin
   (`@nanmicoder/dsh-agent-teams`)** turned the work into **contract-shaped tasks** (each with
   inScope, acceptance and verify commands) and split the roles into captain, research, engineering,
   testing, technical writing, security review, independent acceptance and release. Two rules governed
   the reporting: **artefacts land on disk first**, and **a report quotes raw, reproducible output**.
4. **The toolchain that mattered** (software / plugin -> what it did here):

   | Software / plugin | What it did in this development |
   | --- | --- |
   | `@nanmicoder/dsh-agent-teams` | team orchestration, task dependencies, member mailboxes |
   | `dsh-ego-browser`, `@yuxianglin/dsh-bridge-browser` | the browser bridge: running the real measurement on the peer machine, and reading pages through the browser when this machine's GitHub API was blocked |
   | `dsh-approval-gate` + `@deepseek-ai/dsh-permission-presets` | the sandbox and approval policy (which actions must be authorised by a human) |
   | `@deepseek-ai/dsh-client-ui-settings-plugins` and Slots (`settings.section`, `settings.plugin.item`) | the two seats that put the panel into the settings page |
   | Windows PowerShell 5.1 · git · Python 3.11 + PyYAML (workflow validation) · PSScriptAnalyzer 1.22.0 (CI static analysis) · GitHub Actions (`windows-latest`) · Tailscale (the software of the inspected link) | build, validation and the external judge |
   | a background inspection loop every 5 minutes | watching the long runs: repository state / deliverables / listening surface / network / member activity |

5. **Why the conclusions can be trusted**: every verdict is reproducible with **one command**; the
   whole suite runs on a **frozen snapshot** (so concurrent edits cannot colour the result); key
   assertions carry **positive controls** (break the thing on purpose and the assertion must go red,
   which proves it is not idling); and **CI is used as an external judge** - it did catch 6 cases that
   depended on the reference machine, and the fix was to pin the tools inside the fixtures, add
   `-SimulateCleanHost`, and wire the simulated clean host into the standing CI gate.
6. **The human / AI split**: AI implemented the code, the documents and the tests, and self-checked
   them; the human owned the requirements, the naming and licence decisions and the final acceptance,
   and personally performed the **machine-level actions** (installing plugins, editing the profile,
   `git push`, firewall and power changes). So this is **not an AI self-publishing project** - it is
   **AI implements + a human decides and executes**.
7. **One distinction worth stating**: the plugins used to **build this repository** (AgentTeams /
   ego-browser / approval-gate and so on) are **not** the plugin this repository **produces**
   (`remote-tailnet-guard`). The former are the tools we worked with; the latter is the deliverable.

That is also why nothing here is a self-declared claim: every acceptance result comes from a
**reproducible command** - the gate `.github/scripts/repo-hygiene.ps1`, the offline suite
`tests/run-tests.ps1`, the fixture suite `tests/run-fixtures.ps1` and the smoke entry
`tests/run-smoke.ps1`. Run them instead of trusting this paragraph.

The licence line is untouched: `LICENSE` is the final MIT text with the copyright line
`Copyright (c) 2026 KomeijiHonnouKai` (see §12).

Read-only posture detector for a **cross-network remote-access link**: [Tailscale](https://tailscale.com/)
plus `tailscale serve` fronting a **loopback-only** DSH port, so a browser plugin on one machine can
drive an authenticated channel page that operates the DSH of another machine in the same tailnet -
the two DSH instances then act as one linked pair (agent to agent).

- **Status**: `0.1.0` pre-release, not tagged yet.
- **License**: **MIT** - settled by the maintainer, so [`LICENSE`](LICENSE) is the final text and
  not a draft. The copyright line is `Copyright (c) 2026 KomeijiHonnouKai`.
- **Repository**: `git clone https://github.com/KomeijiHonnouKai/dsh-crossnet-link remote-tailnet-plugin` —
  the **target directory name is not optional**, and the GitHub account is already filled in
  (`KomeijiHonnouKai`); create that repository on GitHub before the first `git push`.
  The plugin's host half pins the collector to the repository-relative path
  `remote-tailnet-plugin/src/collect.ps1` (`COLLECTOR_REL`, `src/host-half.js:56` and
  `panel/host-half.js:18`, located by walking up from the fs base), so a checkout directory with any
  other name can only ever answer `collector-missing`. Every command in this file is written from the
  **workspace root** — the directory that *contains* `remote-tailnet-plugin/`.
- **Security policy**: [`SECURITY.md`](SECURITY.md) — threat model, disclosure channel and
  eight promises (P1–P8), each with the command that re-checks it.
- **Platform**: Windows 10 / Windows 11, Windows PowerShell 5.1. No module, no node, no
  network access required to run the checks.

Clone and take the first self-check — four lines, two different roots:

```powershell
# from the workspace root (for example D:\DSH): run the clone command above, then
cd remote-tailnet-plugin
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1
```

The last two lines run **inside the repository**, not from the workspace root, and neither takes a
path argument: the gate's `-ScanRoot` defaults to the repository the script itself lives in
(`repo-hygiene.ps1:67-70`, default resolved at `:93-94`), and `tests/run-tests.ps1` derives its plugin
root from `$PSScriptRoot\..` (`:68-70`). There is no third calling convention. Every **other** command
in this README is written from the **workspace root** instead — for example
`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly`,
which only resolves if the checkout directory is called `remote-tailnet-plugin`.

The **Chinese original** - section by section, with a per-section completeness note - is the default
[`README.md`](README.md) that GitHub shows; this file is its English counterpart, published as
`README.en.md`.

---

## 1. What it is

Four deliverables that share one detection core:

| Piece | Entry point | What it is |
|---|---|---|
| Collector / judge | `src/collect.ps1` | 24 checks, four verdicts, exit codes 0/1/2, fixture-injectable |
| Prerequisite checker | `panel/prereq.ps1` + `panel/prereq-manifest.json` | 13 prerequisite items with role, detection method, install command to *show*, verification and rollback |
| DSH plugin (dynamic Cordis package) | `src/host-half.js`, `panel/host-half.js`, `panel/client-half.js` | host half exposes a bounded posture read; the settings panel is display-only |
| Persistent plugin package | `plugin/package.json`, `plugin/cordis.patch.yml`, `plugin/lib/index.js` (host half), `plugin/lib/client.js` (loader bundle), `plugin/lib/client/index.js` (ESM twin) | the same read-only settings section as an installable bundle; its single mount row ships `disabled: true`, so installing it does nothing until you enable it |

Supporting material: `i18n/labels.{en,zh}.json` (all non-ASCII text), `docs/collect.md`
(implementation notes), `docs/threat-model.md` (who can see and do what),
`docs/install/{prerequisites,install,rollback}.md`, `docs/install/plugin-package.md` (enable, verify
and roll back the persistent package), `panel/plugin-preflight.ps1` (its read-only preflight, exit
0/1/2), and the offline suite `tests/run-tests.ps1` (one case per directory under `tests/cases/`).

## 2. What it checks

| Group | Checks |
|---|---|
| Host | `OS_BUILD`, `HOST_PS_ENV` (probe capability), `PRIVILEGE_LEVEL` |
| Link | `TAILNET_ADDRESS`, `MAGICDNS_RESOLVE`, `PEER_TCP_443` (connected / refused / timeout), `PEER_ISOLATION_PROBES` (135, 5357 and the DSH port must **not** answer), `SERVE_PRESENT` |
| Exposure | `DSH_LOOPBACK_ONLY`, `WILDCARD_LISTENER_INVENTORY`, `DSH_NETWORK_EXPOSURE`, `TRUSTED_HOSTS_PATCH`, `NO_NEW_WILDCARD_LISTENER` (before/after self-proof) |
| Tailscale | `TAILSCALE_CLI_LAYER`, `TAILSCALE_SERVICE`, `TAILSCALE_PROCESS_EDGE_DB`, `TAILSCALE_IN_RULES` |
| Windows posture | `FIREWALL_PROFILES`, `NIC_PROFILE_ATTRIBUTION`, `POWER_STANDBY_IDLE_AC_DC`, `POWER_S0_CAPABILITY`, `BROWSER_PROXY_TSNET` |
| Client-only | `HTTPS_CLIENT_ONLY` (needs a Node/OpenSSL probe; `curl` under schannel fails falsely) |
| Self-audit | `CREDENTIAL_DISCIPLINE` (re-audits every probe command string it executed) |

Verdicts are **fail-closed**:

| Verdict | Meaning |
|---|---|
`pass` | the property was proven on this machine |
`degraded` | the property holds only in part, or the evidence was read through a localized/fallback path (`confidence: low` in the report) |
`blocked` | the property is violated, or the collector could not run at all |
`unknown` | no probe could answer. **Never** silently treated as a pass; `-Strictness strict` raises it to exit 2 |

Exit codes: `0` every judgement passed, `1` at least one degraded/unknown, `2` at least one
blocked or the collector could not run.

## 3. What it deliberately does **not** do

**The plugin is read-only and report-only.** It never modifies the firewall, never asks you to
change an existing DSH profile or another plugin's configuration, and never restarts DSH; every fix
it suggests is executed by you, and each one ships with its rollback and its affected surface
([`docs/install/rollback.md`](docs/install/rollback.md)). Everything below is a specific case of
that stance.

- **No installation, ever.** No `msiexec`, no `Start-Process`, no `runas`, no scheduled task,
  no execution-policy change. A missing prerequisite produces a printable command for a human.
- **No new listener, route, firewall rule or `tailscale serve` publish.** `-Apply` is accepted
  and **refused** (exit 2) because this revision has no write path. The tailnet ACL stays a
  human action in the Tailscale admin console.
- **No credential handling.** It never opens the DSH credential store, the bridge token file,
  a browser cookie database or a session log; it never prints, stores or transmits secret
  material.
- **No telemetry, no callback, no auto-update.**
- **No restart logic.** The DSH host is an Electron `utilityProcess` child that fails without
  its supervisor, so "kill and relaunch the host" designs break the product. None is present.
- **No LAN/desktop/non-Windows path.** This tool covers one measured setup only: same tailnet,
  server-side `tailscale serve`, a narrow ACL that admits only the client to the server's
  TCP 443, and a browser that exchanges the token URL for a long-lived cookie. It is not a
  general remote-access manager and offers no fallback mechanism.
- **No automatic soak test and no automatic remediation.** Long-running observation and every
  fix stay manual by design.

## 4. Install

**Path A (default): dynamic Cordis package — in process, nothing written to disk.** Define the
package from `panel/host-half.js` and `panel/client-half.js`, run it, and the panel appears in
the settings section. Nothing survives a process restart, so there is nothing to uninstall.
Full steps and success/failure criteria: [`docs/install/install.md`](docs/install/install.md) §1.

**Path B: persistent plugin package — needs explicit approval.** The package now ships in `plugin/`,
but installing it writes into your own DSH profile (`<DSH_HOME>/profiles/<name>/…`), so it is
documented and **never performed** by this project: run the read-only preflight, back up the profile
patch, install, verify the settings section appears, then roll back by restoring the row to
`disabled: true` or by restoring the whole file. Three steps, four rollback steps and the throwaway
profile: [`docs/install/plugin-package.md`](docs/install/plugin-package.md) §5 / §6 / §8; the older
hand-written row variant: `docs/install/install.md` §4 and
[`docs/install/rollback.md`](docs/install/rollback.md).

Prerequisites (Tailscale, sign-in, the DSH port being loopback-only, the firewall rules, the
ACL, the first token open, the proxy bypass) are listed with per-role detection and rollback in
[`docs/install/prerequisites.md`](docs/install/prerequisites.md).

## 5. Usage

### Collector

```powershell
# default: human-readable, read-only
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly

# machine-readable report
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -AsJson

# one side only (a client-only machine does not need the server checks)
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -Role client `
  -Peer <PEER_IP> -PeerName <HOST>.<TAILNET_DOMAIN>

# what the script resolved and from where (param > environment > discovery > default)
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -Describe

# offline: judge a captured fixture, forbid real probes entirely
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -FixturePath tests/fixtures/en.json -NoNative

# opt-in writes (the ONLY writes this script can perform)
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -AsJson -OutFile $env:TEMP\rtg-report.json
```

Other switches: `-Lang auto|zh|en`, `-LabelsDir`, `-Port`, `-TailnetDomain`, `-Profile`,
`-DshHome`, `-AppDir`, `-Strictness normal|strict`, `-TcpTimeoutMs`, `-DnsTimeoutMs`,
`-CommandTimeoutMs`, `-ToolPath`, `-TrustedHostPattern`, `-DumpFixture`, `-ShowRaw`,
`-Apply` (refused).

Measured on the reference machine (2026-09-24, Windows 10 Pro 19045, Windows PowerShell
5.1.19041, no `-Peer` given, ~12 s):

```text
total=24  pass=15  degraded=2  blocked=1  unknown=6   exit=2
```

Read that honestly: the `blocked` item is the local DSH `trustedHosts` patch (this machine has
not applied it) and the six `unknown` items are the ones that need a peer address or an
ordinary (non-sandboxed) terminal window. On a fully configured pair the same command reports
no unknowns; the point of the tool is that neither case is guessed.

### Prerequisite checker

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -CheckOnly -Role client
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -CheckOnly -Role server -ShowInstallPlan
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -CheckOnly -AsJson
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -Describe
```

`-Role both` (the default) checks the server *and* the client requirements, so a client-only
machine legitimately exits non-zero - that is the fail-closed verdict, not a command failure.
Other switches: `-Manifest`, `-Lang`, `-DshHome`, `-AppDir`, `-Port`, `-MsiPath`,
`-CommandTimeoutMs`, `-NetstatStdoutFixture`, `-NetstatStatePattern`. Measured here
(`-CheckOnly -AsJson`, read-only): `total=13 pass=6 blocked=1 unknown=6 exit=2`.

### Test suite

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1 -List
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1 -Filter locale
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1 -Only isolation
```

One case per directory under `tests/cases/` (64 today) runs the real collector against injected
fixtures: peer offline/refused/timeout, serve moved or absent, a changed DSH port, a cookie that
expired (401), a missing `trustedHosts` key, non-admin probes, Tailscale absent/logged out/
unreadable, a path with spaces and Chinese characters, locale traps (including a Chinese-tool-output
culture set to `en-US`), write isolation and the zero-hardcoding scan - plus its own positive
controls. One case is not a collector run but a static shape check of the persistent package:
`tests/cases/plugin-package-shape/` asserts 37 static facts (parse, encoding and the classic-script
shape of `plugin/lib/*.js`, the `package.json` fields, the single `- insert` row and its `disabled`
key, and that the marked SHARED BODY region is byte-identical in `plugin/lib/client.js` and
`plugin/lib/client/index.js`). Requirements: `tests/run-tests.ps1` only needs Windows PowerShell 5.1.

The suite is its own source of truth for the numbers: it prints `cases run / passed / failed /
xfail held / xpass` in its header and its exit code is the verdict, so read those rather than a
frozen snapshot (the case count is simply the number of directories under `tests/cases/`). An
`xfail` marker is how a known spec gap is carried without hiding it; the suite currently holds
none. Requirements: Windows PowerShell 5.1 only - no Pester, no module, no network.

## 6. Support matrix (the four Windows combinations)

The detector is OS-version agnostic: it reads the OS build, the firewall state and the power
capability **structurally**, and it never infers standby behaviour from "is this Windows 11".

| # | Client | Server | Evidence level |
|---|---|---|---|
| A | Windows 10 | Windows 11 | the **only** combination with a live end-to-end run (client + server side by side, 2026-09-24) |
| B | Windows 11 | Windows 10 | server side live-verified on Windows 10; the client path is the same code path as A but no live Windows 11 client was available |
| C | Windows 10 | Windows 10 | server side live-verified; client path same as A |
| D | Windows 11 | Windows 11 | **not live-verified**; the Windows 11 server posture is covered by fixture `tests/fixtures/win11-server.json` |

"A Windows 11 machine must be entering modern standby, therefore the link will drop" is not a
supported conclusion here - `POWER_S0_CAPABILITY` reports what `powercfg /a` actually says on
that machine and leaves the interpretation to a human. Anything marked `degraded`/`unknown`
above is reported as such in the output.
### 6.1 Two machines × proxy on/off = the four cases

The link has **two ends**, and each end may run its own proxy, so there are four combinations. But
**this tool runs on one machine at a time and reports only that machine's proxy posture for the role
it was given**: the client end is `BROWSER_PROXY_TSNET`, the server end is `SERVER_PROXY_STATE` plus
`TAILNET_ROUTE_PRESENT`. The other end's proxy state **cannot be observed from here**, so it is never
guessed - it simply does not appear in this end's verdicts.

| # | Client proxy | Server proxy | (1) What the client sees | (2) What the server sees | (3) How to judge (commands below) | (4) Fix / (5) Rollback | Evidence level |
|---|---|---|---|---|---|---|---|
| 1 | off | off | the browser goes straight to `https://<HOST>.<TAILNET_DOMAIN>/`, no proxy in the path; if it fails, the proxy is **not** the cause | the inbound path has nothing to do with WinINET | client `pass/proxy_ok(disabled)`; server `pass/proxy_ok(disabled)` | nothing to fix; rollback: none | **derived** (this machine is not in this case) |
| 2 | on | off | the browser **goes through the proxy**: `*.ts.net` is resolved/connected by the proxy and usually times out or errors, while the script's direct TCP probe **succeeds** | the inbound path is normal; the server cannot see the client's proxy settings | client **`degraded/proxy_hijack`**; server `pass` | client: path 1 or path 2; rollback: delete the bypass entry / put the system-proxy switch back | client **measured**; server half **unverified** |
| 3 | off | on | a WinINET system proxy **does not touch the inbound path**, so the browser opens the page normally; if the server runs a **TUN-mode** proxy it looks like `timeout` instead | `SERVER_PROXY_STATE` = **`degraded/proxy_active_route_intact`** (`confidence=low`); in TUN mode also `TAILNET_ROUTE_PRESENT` = `blocked/route_tailnet_missing` | the two server items (commands below) | only TUN mode needs action: the server walks path 1; rollback: put the proxy back exactly as it was | server **measured**; the TUN branch **unverified** |
| 4 | on | on | exactly like case 2 (the browser end only sees the client's proxy) | exactly like case 3 | client + server **both `degraded`** | each end follows path 1 / path 2 | **measured (both ends)** - this machine was in this case when the section was written |

> **This machine's real state** (the machine that wrote this README - not an example):
> `ProxyEnable=1`, `ProxyServer=127.0.0.1:7897`, and `ProxyOverride` contains neither `ts.net` nor
> `100.64.`, so it sits in **case 4**; measured `BROWSER_PROXY_TSNET = degraded/proxy_hijack` and
> `SERVER_PROXY_STATE = degraded/proxy_active_route_intact`. **No other case is claimed as
> end-to-end verified**: cases 2 and 3 each have only one half measured here (the other half is the
> peer's state, which is not observable from this end), and case 1 is derived.

**(3) How to judge: three commands, paste them one at a time**

```powershell
# (1) is this end running a proxy? (run it once on each end; ProxyEnable=1 means yes)
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select-Object ProxyEnable, ProxyServer, ProxyOverride

# (2) tailnet route: look for the 100.64.0.0/10 row (netmask 255.192.0.0)
route print -4

# (3) the tool's own verdict: run it once on each machine, with the roles the right way round
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -Role client
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -Role server
```

**Raw output of (1) - measured on this machine**

```text
ProxyEnable   : 1
ProxyServer   : 127.0.0.1:7897
ProxyOverride : localhost;127.*;192.168.*;10.*;172.16.*;…;172.31.*;<local>
```

How to read it: `ProxyEnable=1` means the system proxy is on; `ProxyOverride` is a
**semicolon-separated list of wildcards**, and it contains neither `ts.net` nor `100.64.`, so a
browser visiting a tailnet page goes through the proxy, and that proxy most likely does not know
`*.ts.net`. With `ProxyEnable=0` the other two values have no effect even if they are still there.

**Raw output of (2) - measured on this machine, tailnet rows only (the local and peer addresses are
replaced by this repository's sanitized example addresses)**

```text
Network Destination        Netmask          Gateway       Interface  Metric
     100.64.0.11  255.255.255.255         On-link     100.64.0.12      5
     100.64.0.12  255.255.255.255         On-link     100.64.0.12      5
```

⚠️ One measured lesson worth keeping: **the link worked while this table had no `100.64.0.0/10`
aggregate row.** This machine carried only a few /32 host routes (its own tailnet address, the peer
address, and the tailnet's own DNS address), and at the same moment the `-Peer` probe measured
`connected` (15-19 ms). So when `TAILNET_ROUTE_PRESENT` answers `blocked/route_tailnet_missing`, read
it as a **lead**, not as a verdict that the link is down: look at the tri-state below first, then at
the fix for the case you are in.

**Raw output of (3) - measured on this machine**

```text
[DEGRADED] BROWSER_PROXY_TSNET (client) - Browser proxy hijacking the tailnet
    A system proxy is enabled and the bypass list has no entry for ts.net / 100.64.0.0/10 - the browser may time out while scripted probes succeed.
    fix: Add the tailnet name/range to the proxy bypass list, or disable the system proxy while using the link.
    cmd: Add the tailnet name/range to the proxy bypass list, or disable the system proxy while using the link
    rollback: remove the bypass entry you added
[DEGRADED] SERVER_PROXY_STATE (server) - server_proxy_state
    proxy_active_route_intact
    cmd: A system proxy on the server does not open or close the inbound path; if the client times out while this is on, look for a TUN-mode proxy and check the tailnet route (TAILNET_ROUTE_PRESENT)
    rollback: nothing to roll back: this collector changes no proxy setting
```

Under `-AsJson` the two items carry `verdict`/`reason` = `degraded`/`proxy_hijack` and
`degraded`/`proxy_active_route_intact`; `raw.confidence=low` on the server item means it proves only
"a system proxy is on" - not that it influences the inbound path.

**(4) The connectivity tri-state (client side, `-Peer` pointing at the server)** - all three results
were measured on this machine; the raw shapes are:

```text
# connected: the TCP handshake succeeded (measured here at 15-19 ms) - TCP layer only, no TLS/certificate proof
[PASS] PEER_TCP_443 (client) - Peer 443 TCP tri-state
    TCP handshake to the peer's 443 succeeded (19 ms) - TCP-layer reachable (TCP only, no TLS/HTTP).

# refused: the path works but nothing listens on 443 (serve not running / wrong port) (measured here at 2043 ms) - nothing to do with a proxy
[BLOCKED] PEER_TCP_443 (client) - Peer 443 TCP tri-state
    The peer actively refused 443 (2043 ms) - path works but nothing listens on 443 (serve not running or wrong port).

# timeout: packets are dropped (ACL/firewall), or the peer is asleep (measured here at 3012 ms) - a proxy hijack looks the same
[BLOCKED] PEER_TCP_443 (client) - Peer 443 TCP tri-state
    Timed out after 3000 ms (dropped, not refused) - packets are dropped by an ACL/firewall, or the peer is asleep. This is not an active refusal.
```

How to use them: **connected** means the TCP layer is fine - if the page still will not open, look at
the proxy (cases 2 and 4); **refused** has nothing to do with a proxy - it is a serve/port problem;
**timeout** means suspect a proxy hijack and the server-side route first (cases 3 and 4), then the ACL
and the peer's power state.

**Three easy traps**

1. **WinINET's `ProxyOverride` does not support CIDR.** To bypass, write `*.ts.net;100.64.*`;
   **writing `100.64.0.0/10` does nothing** - the field only understands semicolon-separated
   wildcards, not network syntax. Note that the collector's test is a **string match** (`ts.net` or
   `100.64.`), so writing `100.64.0.0/10` makes it answer `pass` while the browser still does **not**
   bypass - a passing verdict is not proof that the browser really goes direct; the page opening is.
2. **git's proxy is a separate thing from the system proxy.** git reads
   `git config --global http.proxy` (or the `HTTP_PROXY` / `HTTPS_PROXY` environment variables) and
   does **not** read `ProxyEnable`. So "turn the system proxy off so the browser reaches the tailnet
   directly" and "git keeps using a proxy to push to GitHub" can both be true at once: turning the
   system proxy off does **not** cut git off, and neither does the reverse.
3. **Under a TUN / transparent proxy you cannot read the third-party proxy's internal rules.** Such a
   proxy can take over the route, and all this tool can prove is the other half - that the aggregate
   route is **gone** from `route print -4`. Whether that proxy did it, and whether its rules let
   `100.64.0.0/10` through, **cannot be decided** ⇒ the verdict stays `unknown` honestly (the related
   item answers `route_tailnet_missing`, the attribution is reported as undecidable), and **nothing
   is guessed**.

**(4)(5) Fix and rollback for every case: two paths**

**Path 1 (recommended, one-off): make the tailnet direct (DIRECT).**
- Client: add `*.ts.net` and `100.64.0.0/10` to the **proxy software's own** direct/bypass rules
  (vendors call this "bypass", "direct rules" or "custom rules"). If all you can edit is Windows'
  system-proxy bypass field, write `*.ts.net;100.64.*` (trap 1).
- Server: only a **TUN-mode** proxy needs this - let `100.64.0.0/10` skip the proxy tunnel. A
  **WinINET system proxy does not affect the inbound path**, so turning it off for inbound traffic
  achieves nothing.
- Blast radius: only tailnet traffic leaves the proxy; everything else keeps using it.
- **Rollback**: delete the two direct rules you added (in the system-proxy field, that means removing
  the `*.ts.net;100.64.*` segment).

**Path 2 (least effort): turn the system proxy off while you use the link, back on afterwards.**
- Client: Settings → Network & Internet → Proxy → switch "Use a proxy server" off.
- Server: again only meaningful in TUN mode; the WinINET field can stay as it is.
- Blast radius: while it is off, **all** browser traffic goes direct - sites that need the proxy will
  stop opening.
- **Rollback**: flip the switch back and paste the old `ProxyEnable` / `ProxyServer` /
  `ProxyOverride` values back in - **keep the output of `Get-ItemProperty …` before you change
  anything**; that output is your backup.

> This tool **never modifies** any proxy setting, so it has no rollback action either; every step in
> the two paths above is done by **you**, and so is the rollback.

## 7. Security posture

- [`SECURITY.md`](SECURITY.md) holds the promise index and the exact verification command for
  each: **P1** no new listening socket/route/firewall rule, **P2** read-only by default,
  **P3** no automated write and `-Apply` refused, **P4** no credential read/print/store/send,
  **P5** no telemetry or callback, **P6** no restart logic, **P7** every side effect hangs off
  `ctx.effect` and is removable, **P8** the panel is display-only.
- [`docs/threat-model.md`](docs/threat-model.md) answers the "who can see what" questions:
  other tailnet nodes, DERP relays (metadata only - traffic is WireGuard-encrypted), a
  compromised client, whoever holds a token URL, and other processes on the server. The two
  conclusions worth repeating: **being able to open the UI equals being able to operate that
  machine**, and **loopback is trusted by design** (this tool does not change that, and never
  widens it).
- Client-to-host traffic crosses only a bounded field whitelist; raw blocks never leave the
  host half.

### Installer hash policy

This repository does **not** bake in vendor installer hashes. A hash pinned in a repository
goes stale with the next upstream release, and a stale pin either blocks a legitimate install
or hides a tampered one - both are worse than the alternative. `panel/prereq.ps1` therefore
verifies the Authenticode signature and supports an **optional** pin
(`panel/prereq-manifest.json` → `hashPolicy.pinnedSha256`), which the operator sets from their
own download. Until a hash is pinned the hash gate reports `blocked (hash_not_pinned)`; it
never guesses, and the checker never downloads or runs anything.

## 8. Repository layout and release set

```text
src/                collect.ps1 (collector), host-half.js (plugin host half)
i18n/               labels.en.json, labels.zh.json
panel/              prereq.ps1, prereq-manifest.json, plugin-preflight.ps1 (read-only, exit 0/1/2), client-half.js, host-half.js
tools/              uninstall.ps1 (the only optional write component: dry-run by default, §21)
plugin/             package.json, cordis.patch.yml (the single mount row ships disabled), lib/index.js (host half), lib/client.js (loader bundle), lib/client/index.js (ESM twin) - the persistent package
docs/collect.md     implementation notes for the collector (published)
docs/threat-model.md  threat model (published)
docs/install/       prerequisites.md, install.md, rollback.md, uninstall.md, plugin-package.md (published)
tests/              run-tests.ps1, run-fixtures.ps1, run-smoke.ps1, cases/, fixtures/
.github/            workflows/ci.yml, scripts/repo-hygiene.ps1, scripts/check-workflows.py
LICENSE  README.md  README.en.md  CHANGELOG.md  SECURITY.md  CONTRIBUTING.md  .gitignore  .editorconfig  .gitattributes
```

The release set is exactly those paths, and **`panel/` is part of it**: the prerequisite checker
(`panel/prereq.ps1`), its machine-readable manifest (`panel/prereq-manifest.json`) - including the
`hashPolicy` block the operator edits to pin a hash - and both halves of the plugin
(`panel/host-half.js`, `panel/client-half.js`) are **shipped with the repository**. The panel is not
an optional extra: `.gitignore` does not exclude it, and the hygiene gate scans it as a **default
root** (it used to need an `-ExtraRoots panel` argument, which meant a published file could have
escaped the gate by living in the wrong directory).

**`tools/` is part of it too**: `tools/uninstall.ps1` — the repository's only **optional write**
component (dry-run by default, `-Apply` required, backup written first, §21) — ships with the
repository and is a **default scan root** as well, because a clone that lacks the uninstaller cannot
support the claim "complete, clean removal".

**Both READMEs ship with the release set**: `README.md` is the Chinese original - the file GitHub
shows by default - and this file is its English counterpart, published as `README.en.md`. They carry
the same layout and release-set list, and both are registered in the hygiene gate's default roots, so
neither can drift out of the gate's scope.

**`plugin/` is part of the release set too**: the persistent plugin package
(`plugin/package.json`, `plugin/cordis.patch.yml`, `plugin/lib/index.js`, `plugin/lib/client.js`,
`plugin/lib/client/index.js`) ships with the repository and is a **default scan root**; its read-only
preflight (`panel/plugin-preflight.ps1`) and the Chinese enable/verify/rollback write-up
(`docs/install/plugin-package.md`) are published as well. The mount row inside
`plugin/cordis.patch.yml` ships **`disabled: true`**, so the published package is inert until an
operator enables it (§15).

**Internal analysis and review material does not ship with the repository**: the research notes,
review reports and verification transcripts listed in section 1 of `.gitignore` are working documents
that contain machine specifics gathered while the checks were designed. They are excluded by
`.gitignore`, and the hygiene gate fails if that exclusion list is incomplete (the gate, not this
file, is the list of record).

## 9. CI and repository hygiene

`.github/workflows/ci.yml` runs on a **windows** runner and performs, in two jobs:

1. the release-set hygiene gate `.github/scripts/repo-hygiene.ps1` (blocked identifiers,
   private ranges and node suffixes, credential *value* shapes, encodings, binary products, the
   removed client-runtime reference, internal-material exclusions, document markers) plus its
   own positive/negative **self-test**;
2. the workflow parse + schema gate `.github/scripts/check-workflows.py` (PyYAML 6.0.2 pinned
   as the authoritative parser, plus a zero-dependency fallback so the gate also runs offline);
3. the full test suite `tests/run-tests.ps1` under Windows PowerShell 5.1;
4. static analysis with **PSScriptAnalyzer 1.22.0**, installed with a pinned version; error
   severity fails the build, warning severity is printed for information.

The hygiene gate is deliberately strict: **0 hits** for blocked identifiers, private ranges and
node suffixes, **0** credential value shapes, and **0 unclassified tokens** - a token that no allow
rule explains is itself a blocking finding, so the allow list can never become a blindfold. It
reports `verdict: CLEAN` over the release set, which includes all four files under `panel/`, and it
prints the live file count in its header (85 when this line was first written; with `tools/`,
the second README and `plugin/` among the default roots it was 109 at that snapshot, and **110** is measured for this revision); the CI job passes no scan-root argument
because the release set *is* the default scope. The classification of everything the gate does *not*
treat as blocking is in section 10. Run the same gates locally:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -SelfTest
python .github/scripts/check-workflows.py --selftest
```

## 10. Residual identifiers in the release set

**None.** The gate reports `verdict: CLEAN` (0 blocking findings) over the release set. Two
documentation lines used to carry a residual absolute application path from the development
machine; both were replaced with the `<DSH_APP>` / `<APP_DIR>` sanitized values by the follow-up
documentation task (t20, 2026-09-24). The gate is the proof, and it classifies everything it
finds instead of only counting it:

| Hit class | Measured 2026-09-24 (the gate prints the live numbers) | Judgement |
|---|---|---|
| blocked identifiers (real addresses, host names, user paths) | 0 | must be 0 |
| private /24 prefixes and ULA node suffixes outside the documented prefix | 0 | must be 0 |
| credential value shapes (`tskey-…`, a JWT, `key = <12+ characters>`) | 0 | must be 0 |
| credential words as field names, "never read" declarations, fixture vocabulary | reported per file when you run it (a few hundred) | allow-listed; reported for human confirmation, never fatal on its own (the gate prints the live number and its per-file breakdown, which moves whenever a doc mentions one of the five words) |
| product constants and sanitized replacement values | 12 distinct tokens, 135 occurrences (119 before the second README joined the release set) | allow-listed **by token** from the single shared allow list at the top of `.github/scripts/repo-hygiene.ps1`; **0 unclassified tokens**, and an unclassified token would fail the gate |
| unapproved token (nothing on the allow list explains it) | 0 | must be 0 - the gate's self-test plants one and proves it alone flips the verdict to FAIL |
| removed client-runtime package | 0 code references, 2 documentation mentions | code must be 0; the docs quote the ban and the check command on purpose |
| encodings, binary products, internal-material exclusions, document markers | 0 | must be 0 |
| line endings | LF everywhere; 2 CRLF files today | both are the captured-output fixtures under `tests/fixtures/` (CRLF on purpose), and the gate now reports **no line-ending note at all** - the last one, `tests/cases/README.md`, was converted to LF; `repo-hygiene.ps1 -StrictLineEndings` still promotes any non-fixture CRLF file to a blocking finding |

Reproduce it with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -SelfTest
```

`-SelfTest` plants one file per violation class in `%TEMP%` and asserts that the gate reports
each of them, then plants a clean tree and asserts 0 findings - so a gate that had quietly
stopped matching would fail its own control instead of reporting a false green.

## 11. Versioning, tags and release steps

Semantic Versioning: `MAJOR.MINOR.PATCH`. `MAJOR` changes when a verdict meaning, an exit code
or a JSON field changes incompatibly; `MINOR` adds checks, cases or documentation; `PATCH`
fixes text or detection logic without changing a contract. Tags are annotated and named
`vMAJOR.MINOR.PATCH` (release candidates `vX.Y.Z-rc.N`), created by a maintainer only.

Release steps:

1. `LICENSE` is the final MIT text with the maintainer's copyright line (settled - task t24).
2. `tests/run-tests.ps1` is green on Windows.
3. `.github/scripts/repo-hygiene.ps1` prints `verdict: CLEAN`.
4. `python .github/scripts/check-workflows.py --require-pyyaml` is green.
5. Move the `Unreleased` changelog entries under the new version heading with the release date.
6. Commit, create the annotated tag, push the tag.
7. Attach no binaries: this repository is text-only by policy.

## 12. Contributing and license

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the hard rules (read-only, fail-closed, zero
hardcoding, the encoding table, the sanitization rules) and the commands to run before opening
a pull request. Security problems go through [`SECURITY.md`](SECURITY.md), not a public issue.

License: **MIT**. [`LICENSE`](LICENSE) carries the full MIT text with the copyright line
`Copyright (c) 2026 KomeijiHonnouKai`, and `CHANGELOG.md` states the same. The choice is settled,
so everything in this repository is released under MIT with nothing outstanding.

---

### Verification commands used for this delivery (2026-09-24, task t12)

```powershell
Get-ChildItem remote-tailnet-plugin -File | Select-Object -ExpandProperty Name
(Get-ChildItem remote-tailnet-plugin -Recurse -File | Select-String -Pattern '<blocked-identifier regex>' | Measure-Object).Count
Test-Path remote-tailnet-plugin/.github/workflows
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/.github/scripts/repo-hygiene.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/.github/scripts/repo-hygiene.ps1 -SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1
python remote-tailnet-plugin/.github/scripts/check-workflows.py --selftest
```

The blocked-identifier regex is not quoted here on purpose: the list lives in
`.github/scripts/repo-hygiene.ps1` section 0, assembled from fragments so that the gate is not
its own only hit.

---

# Part II — detection contract, activation, wake-up to-dos and evidence chain (task t9)

> **LAST UPDATED**: 2026-09-24 (task t9 — integration and hand-off; sections 13–20 below).
> **COMMANDS USED** (all read-only; no `platform:"client"` Inspect, no `ego_*`, no long waits):
> `powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json`
> (first-hand: `verdict: CLEAN (0 blocking finding(s))`, `blockedHits=0`, `credValueHits=0`,
> `unclassified=0`; the gate prints the live file count, so it is not quoted here); `[Net.Sockets.TcpClient]` 5 s probe (peer 443 = `timeout` at 18:25 local);
> `Select-String` scans for the check ids, the allow-listed sanitized values and the four-quadrant
> criteria (raw outputs quoted in §18); `Get-ChildItem` / `Get-FileHash` inventory of the release
> set. Sections 1–12 are the repository-level README (tasks t12/t24); this part adds the
> **detection contract, the activation paths, the human to-dos and the evidence chain** without
> repeating them.

## 13. Detection items and what each one actually judges

Two independent item sets ship here: the **collector** (24 checks, one JSON report, exit 0/1/2) and
the **prerequisite checker** (13 items, install-plan oriented). They share the vocabulary but not
the thresholds.

### 13.1 Collector checks (24)

`role` is the side a check belongs to; the report tags every item with it so a client-only run does
not look "broken" because server items are missing. `evidence` is what the verdict is read from -
never a config file, and never a localized string without a `confidence: low` downgrade.

| # | id | role | what it judges | how pass / degraded / blocked / unknown is decided | evidence source |
|---|---|---|---|---|---|
| 1 | `OS_BUILD` | both | OS build and branch | build numbers read structurally; `branch = win10 / win11` ⇒ pass; a non-Windows host ⇒ `unsupported-platform` blocked | registry / CIM fallback |
| 2 | `HOST_PS_ENV` | both | PowerShell host + probe capability | PS 5.1 Desktop ⇒ pass; a host that cannot answer ⇒ degraded/unknown, never pass | `$PSVersionTable`, host name |
| 3 | `PRIVILEGE_LEVEL` | both | current process elevation | non-elevated is a legitimate state; it is reported so every later "probe denied" reads as unknown | token elevation |
| 4 | `TAILNET_ADDRESS` | both | local tailnet address / membership | a `100.64.0.0/10` or `fd7a:115c:a1e0::/48` address in the address table ⇒ pass; **not found ⇒ unknown** (signed out is not blocked) | `netsh interface ip show addresses` |
| 5 | `DSH_LOOPBACK_ONLY` | server | the DSH port is reachable on loopback only | a listener row whose remote column is `0.0.0.0:0` **plus** a real TCP connect ⇒ pass; probe unusable ⇒ unknown (`dsh_no_listener`) | `netstat` row shape + `TcpClient` |
| 6 | `WILDCARD_LISTENER_INVENTORY` | both | non-loopback listeners, stated separately from the DSH port | rows parsed ⇒ pass/degraded; probe unavailable / state word unreadable / zero rows ⇒ `unknown` (`netstat_unavailable`) | `netstat` (+ injectable state regex) |
| 7 | `TAILSCALE_CLI_LAYER` | both | CLI layering | `ip` / `serve` exit codes decide; the named pipe being denied ⇒ `unknown` (`ts_pipe_denied`), **never** "not signed in" | `tailscale ip -4`, `serve status` |
| 8 | `TAILSCALE_SERVICE` | both | Tailscale service state | service present/running ⇒ pass; absent/stopped ⇒ blocked/degraded | `Get-Service Tailscale` |
| 9 | `TAILSCALE_PROCESS_EDGE_DB` | server | the **stored** `Edge=` of rule `Tailscale-Process` | `Edge=FALSE` ⇒ pass; `Edge=TRUE`/absent ⇒ **blocked** (`edge_false` drift); the `Tailscale-In` rules are deliberately a different item | registry `FirewallRules` (non-elevated read) |
| 10 | `TAILSCALE_IN_RULES` | server | the built-in `Tailscale-In` inbound allows | `Edge=No` there is **normal** ⇒ pass; absence is reported, not guessed | registry `FirewallRules` |
| 11 | `NIC_PROFILE_ATTRIBUTION` | server | which firewall profile the Tailscale adapter is in | enum source ⇒ pass, `confidence: high`; localized-text path ⇒ **degraded**, `confidence: low`; unreadable ⇒ unknown | `Get-NetConnectionProfile` → `netsh advfirewall monitor show currentprofile` |
| 12 | `FIREWALL_PROFILES` | server | the three profile states | all three read ⇒ report; a profile that cannot be read is unknown, not "off" | `netsh advfirewall show allprofiles` |
| 13 | `POWER_STANDBY_IDLE_AC_DC` | server | AC/DC idle-standby seconds | AC=DC=0 ⇒ pass; DC≠0 ⇒ **degraded** (`power_dc_only`, e.g. 3600 s) - the link dies on battery | `powercfg /query` hex indices |
| 14 | `POWER_S0_CAPABILITY` | server | S0/S3 capability and what `powercfg /a` says about link loss | structure-parsed ⇒ `degraded` + `confidence: low`; the raw line is preserved for a human | `powercfg /a` |
| 15 | `DSH_NETWORK_EXPOSURE` | server | `networkExposure` | `loopback` ⇒ pass; `lan` ⇒ **blocked** (that is a new wildcard listener by definition) | settings / `-Describe` resolution |
| 16 | `TRUSTED_HOSTS_PATCH` | server | `trustedHosts` in the **actually loaded** patch | a bare `host[:port]` entry ⇒ pass; empty/absent ⇒ **blocked** (`/api` 403 for the remote UI) | profile patch file |
| 17 | `SERVE_PRESENT` | server | the tailnet-side 443 serve listener | **t23 semantics**: evidence comes only from a **readable `tailscale serve status` proxy target port**; unreadable ⇒ `unknown`; the `netstat` shape is corroboration only, never the verdict | `tailscale serve status` (→ `netstat` corroboration) |
| 18 | `PEER_TCP_443` | client | the peer's 443 tri-state | connected / refused / timeout, reported verbatim; no `-Peer` ⇒ `unknown` (`peer_not_provided`) | `[Net.Sockets.TcpClient]` |
| 19 | `PEER_ISOLATION_PROBES` | client | the peer's non-443 ports must **not** answer | all probes unanswered ⇒ pass; any port answering ⇒ degraded (the ACL is not narrow) | `[Net.Sockets.TcpClient]` |
| 20 | `MAGICDNS_RESOLVE` | client | the peer's MagicDNS name resolves | resolution ⇒ pass; failure ⇒ blocked/unknown, separated by cause | DNS |
| 21 | `BROWSER_PROXY_TSNET` | client | a browser proxy hijacking the tailnet | proxy bypass present ⇒ pass; a hijack whose symptom is "the script is fine, the browser times out" ⇒ degraded | `HKCU:\...\Internet Settings` |
| 22 | `HTTPS_CLIENT_ONLY` | client | HTTPS/certificate verdict | needs a Node/OpenSSL probe: `curl` under schannel fails falsely, so its `000` is **not** evidence (see the skill's probe-capability table) | https request with `rejectUnauthorized:true` |
| 23 | `CREDENTIAL_DISCIPLINE` | both | self-audit | re-scans every probe command string this run executed; any credential shape ⇒ blocked | own report |
| 24 | `NO_NEW_WILDCARD_LISTENER` | both | read-only self-proof | the wildcard listener set before/after the run must be identical; a probe that cannot answer ⇒ `unknown` (`ro_probe_unavailable`) | own before/after snapshot |

Authoritative wording lives in `i18n/labels.{en,zh}.json` (`title` / `reason` per id, per verdict),
and the expected verdict per injected fault lives in `tests/cases/<name>/case.json`. The table above
is a reading guide, not a second source of truth: if they ever disagree, the labels and the case
expectations win.

### 13.2 Prerequisite-checker items (13)

Every item carries `roles`, `os`, `title`, `detect`, `whenMissing` and (usually) `install`.

| id | roles | detection | rollback in manifest |
|---|---|---|---|
| `TAILSCALE_INSTALLED` | server+client | command `tailscale version` → registry fallback | yes (uninstall command) |
| `TAILSCALE_CLI_LAYER` | server+client | command exit codes (not `version`) | no |
| `TAILSCALE_SIGNED_IN` | server+client | listener / daemon state | no |
| `DSH_RUNNING_LOOPBACK` | server+client | listener probe | no |
| `SERVE_ON_TAILNET_443` | server | listener probe | yes (`tailscale serve reset` — see §15.3) |
| `TRUSTED_HOSTS_CONFIGURED` | server | delegate to the collector item | yes (remove the row) |
| `NARROW_INBOUND_ALLOW` | server | registry | yes (`Remove-NetFirewallRule`) |
| `SERVER_POWER_IDLE_SLEEP` | server | command (`powercfg`) | yes |
| `TAILNET_ACL_NARROW` | server | **manual** (admin console) | no |
| `CLIENT_FIRST_OPEN_TOKEN` | client | **manual** (a human pastes the URL once) | no |
| `CLIENT_MAGICDNS` | client | delegate | no |
| `CLIENT_PROXY_BYPASS` | client | registry | yes |
| `HOST_SERVICE_FOR_PANEL` | server+client | delegate to the plugin host half | no |

Three manifest-level policies matter more than the rows:

- **`install.automatic` is `false` for all 13.** The checker prints the command for a human; it has
  no execution path. `automationBoundary.never` additionally forbids `runas`,
  `Start-Process -Verb RunAs`, scheduled tasks, loosening `ExecutionPolicy` / UAC / firewall /
  Defender / `networkExposure`, signing in, installing restart plugins, and adding
  listeners/routes/rules.
- **Hash policy**: no vendor hash is baked in. Until the operator pins one in
  `hashPolicy.pinnedSha256`, the install step is reported `blocked (hash_not_pinned)` — computed and
  pinned side by side, never guessed.
- **Unreadable probe text**: `probeUnavailable` supplies the sentence used when a probe cannot be
  read, and the verdict is `unknown`, never `pass` (t16 F5: the netstat state word is injectable and
  a localization that matches nothing lands on unknown).

### 13.3 What this project does **not** cover (the explicit unsupported list)

Beyond §3 (no install, no writes, no credentials, no telemetry, no restart logic, no LAN/desktop
path), the specification fixes this list, and it must stay identical in `-Describe` output:

1. **Non-Windows** hosts — `unsupported-platform`, exit immediately; no half-implementation.
2. **Non-Tailscale cross-network designs** — desktop sharing, LAN HTTPS, third-party remote control,
   SSH tunnels. Exactly one path is recognised: same tailnet + server-side `tailscale serve --bg` +
   a narrow ACL admitting only client → server `tcp:443`.
3. **Any new listener** — `networkExposure: lan`, `serve --tcp` on `0.0.0.0`, or a reverse proxy ⇒
   **blocked** (the harness asserts an invariant and throws).
4. **Restart behaviour or restart plugins** — the host is an Electron `utilityProcess.fork` child; a
   plugin must not kill or relaunch it.
5. **Localized tool text as a security verdict** — the `confidence: low` downgrade exists for this.
6. **Reading, printing or transmitting credentials** (token, cookie, key file, credential store).
7. **Default write operations** — a write needs all four gates (opt-in switch + a named directory +
   a printed rollback + idempotence) or it is not implemented.
8. **PowerShell 7-only syntax** — the floor is Windows PowerShell 5.1.
9. **Unverified DSH Desktop versions** — it runs but is not guaranteed; the start-up banner prints
   the verified pair only.
10. **Anything a human must do** — install, sign-in, ACL narrowing, the first token open, soak, and
    every fix: the tool prints the exact step and the exact rollback instead of performing it.

## 14. Activating the plugin — path A (dynamic Cordis package, the default)

There is nothing to install on this path: the two halves are handed to the harness as plugin code
and live in **process memory only**.

| package | halves | what it contributes |
|---|---|---|
| `guard-1` / `pkg-4` (host only) | `src/host-half.js` | Service `remoteTailnetGuard`, private method `remote-tailnet-guard/posture`, tool `remote_tailnet_posture` |
| `panel-2` / `pkg-5` (host + client) | `panel/host-half.js`, `panel/client-half.js` | private method `remote-tailnet-guard/panel/posture` + a read-only `settings.section` panel |

Steps (a human performs them once, in a **normal interactive session** — not a team-member session;
see the trap below):

1. `cordis_run(pluginId="guard-1", packageId="pkg-4", mode="run")` — optional: the panel's host half
   runs the collector itself (`source=direct`) when the shared Service is absent, and that is **not**
   a failure.
2. `cordis_run(pluginId="panel-2", packageId="pkg-5", mode="run")` — because there is a client half,
   the first activation returns `awaiting-approval`; **approve it in the UI**: a single tick
   authorises this package only, a double tick authorises future versions of the same plugin.
   `awaiting-approval` and `starting` are both "not finished yet"; wait for the final state.
3. Reversibility: `cordis_stop("panel-2")` removes the panel section and the private method (no
   file, no setting, no listener is left behind); `cordis_stop("guard-1")` also terminates the
   collector child process; `cordis_undefine(...)` deletes the definitions permanently.

### 14.1 ⚠️ The session-ownership trap (measured — and it is what the parked approval will hit)

A package with a client half is activated by the browser through the host runner, which is handed
**the id of the session that defined the plugin**. A session owned by subagent routing is rejected
by design (`session/agent-busy`, `hasApiSessionSubagentOwner`), the host half's `apply()` is never
evaluated, and no host-side change can help. Measured failure text (2026-09-24, a team-member
session, *after* the approval had been clicked):

```text
host-half-failed
message: session/agent-busy: session "<SUBAGENT_SESSION_ID>" is owned by subagent routing
currentPackageId: none
nextPackageId: pkg-5
```

Three simultaneous symptoms confirm it: the id in the message is the defining session; the approval
card *can* be clicked and then flips to `failed` while `currentPackageId` stays `none`; and a
host-only package in the same session still runs normally (the control experiment). **The minimum
correct move is to define a new plugin from a normal interactive session** (new 3–6 letter
idPrefix, e.g. `rtgp`, with `panel/host-half.js` and `panel/client-half.js` as `code.host` /
`code.client`) and approve that one — re-clicking the parked card burns another approval for the
same result. Rollback for either is `cordis_stop("<id>")`.

**Measured success — the constructive half of this trap (2026-09-24, default workspace session).**
A **new** package was defined from this repository's `panel/client-half.js` plus an equivalent host
half (`panel/host-half.js` as `code.host`) under a fresh idPrefix — `rtgpnl-3` / `pkg-6` — and
`cordis_run(pluginId="rtgpnl-3", packageId="pkg-6", mode="run")` returned `awaiting-approval`. After
the tick in the UI the run reached **completed** (run 6) and the panel appeared in the settings
navigation on the left. So the correct sequence is: **do not click the parked card that belongs to
the member session; define a new package in an ordinary workspace-level session and approve that
one.** Success criteria, the `awaiting-approval`/`starting` caveat and the rollback are in §17.2.

Full evidence, the source-code anchors and the failure table: `docs/install/install.md` §1.4 and §2.

## 15. Path B — the persistent plugin package (optional, needs your explicit approval)

On this path the package is installed into the user's own DSH profile; the project ships it and
documents it, and **never performs the install for you**. The repository-side prerequisites now exist:
[`plugin/package.json`](plugin/package.json) (`type: module`, `main: ./lib/index.js`,
`exports["./client"]` → `./lib/client.js`, a `dsh.client` block and `dsh.bundle.patch`) and
[`plugin/cordis.patch.yml`](plugin/cordis.patch.yml) (exactly one `- insert:` block holding exactly one
row, `disabled: true`). `panel/plugin-preflight.ps1` checks that shape read-only before you touch
anything, and the three-step enable, the four-step rollback and the throwaway-profile recipe are in
[`docs/install/plugin-package.md`](docs/install/plugin-package.md) §5 / §6 / §8. The older hand-written
one-row variant is still described in `docs/install/install.md` §4.

**Not verified here**: nobody has loaded this package in a real DSH yet. Enabling the row is the
operator's step, and the section appearing in the settings page is the success criterion to check for -
`docs/install/plugin-package.md` §5 (enable) and §9 (what is unverified and why).

### 15.1 Prerequisites

- A normal interactive session (same ownership rule as §14.1) and the plugin's own files present.
- The profile directory resolved at run time (`$env:DSH_HOME`, else the user profile) — never a
  hard-coded path; with several profiles, select one explicitly.

### 15.2 Backup (step 0, mandatory)

```powershell
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$patch   = Join-Path $dshHome 'profiles\desktop\cordis.patch.yml'      # multi-profile: choose explicitly
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup  = "$patch.bak-$stamp"
Copy-Item -LiteralPath $patch -Destination $backup -Force
"backup = $backup"
(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
(Get-FileHash -LiteralPath $patch  -Algorithm SHA256).Hash   # identical to the line above
```

### 15.3 The row, the switch and the rollback

```yaml
# the row shipped in plugin/cordis.patch.yml (id and name must both equal package.json's `name`)
- insert:
    - id: remote-tailnet-guard
      name: remote-tailnet-guard
      disabled: true      # the shipped state; flip to false to enable
```

`docs/install/plugin-package.md` §5 appends the same three lines with `disabled: false` to the profile
patch and then restarts DSH from its own menu; §6 step 1 puts it back to `disabled: true` (or the three
lines are deleted) and step 2 restores the whole file from the backup.

Rollback, cheapest first: **(A)** set `disabled: true` on the row; **(B)** delete the row;
**(C)** restore the whole file from the backup — **but read the backup first**, because a pre-change
`.bak` can be an empty patch (`[]`) and restoring it would delete unrelated preset rows:

```powershell
Get-Content -LiteralPath $backup -Encoding UTF8      # explicit UTF8: PS 5.1 reads BOM-less UTF-8 as ANSI
(Get-Item -LiteralPath $backup).Length
Copy-Item -LiteralPath $backup -Destination $patch -Force   # only after the check above passes
(Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash   # byte-identical to the recorded value
```

Prerequisite-side rollbacks live in `docs/install/rollback.md`. The one that used to be wrong and is
now fixed: undoing a `serve` publish is **`tailscale serve reset`** (it clears the whole serve
config on that machine — it is not a per-port stop); verify with `tailscale serve status`. The
evidence ledger (`tailscale serve --help`, exit 0: USAGE lists only `<target>` / `status [--json]` /
`reset`, and there is **no** `off`) is recorded in `docs/install/rollback.md` §3.1.

## 16. The four Windows combinations — prerequisites and traps

The detector never infers a capability from the OS label: it reads the build, the firewall state and
the power capability structurally. Evidence levels are kept apart on purpose.

| # | client → server | client-side prerequisites | server-side prerequisites | trap / difference to expect | evidence level |
|---|---|---|---|---|---|
| **A** | Win10 → Win11 | Tailscale installed + signed in, MagicDNS resolves, no proxy hijack, first token open by a human | loopback-only DSH port, `serve --bg`, narrow ACL (443 only), `trustedHosts` row, power policy AC **and** DC | the only combination with a live end-to-end run; a Win11 **server** reaches the NIC-profile check through the enum source (pass, `confidence: high`), while a Win10 server falls back to localized text (`degraded`, `confidence: low`) | live (client + server), 2026-09-24 |
| **B** | Win11 → Win10 | the same client list; **no live Win11 client was available** | the same server list; the server side is a Windows 10 machine, so it can be re-measured any time | a Win10 server has no `pwsh` and no `node` on `PATH`, so the HTTPS verdict needs the Electron-as-Node probe; `Get-NetConnectionProfile` is denied non-elevated ⇒ NIC attribution is the low-confidence path | server live, client path not live |
| **C** | Win10 → Win10 | the same client list | the same server list | both ends share the Win10 limitations above; do not read the low-confidence NIC result as "no profile" | server live, client path not live |
| **D** | Win11 → Win11 | the same client list | the same server list | **not live-verified at all**; the Win11 server posture is covered by `tests/fixtures/win11-server.json`. "Win11 ⇒ modern standby ⇒ the link will drop" is **not** a supported conclusion — read `POWER_S0_CAPABILITY` and the raw `powercfg /a` line | fixture only |

Common prerequisites for every cell: both machines are in the same tailnet and signed in to the same
account; the DSH port stays **loopback-only**; `tailscale serve --bg` keeps the tailnet side on 443;
the ACL admits only client → server `tcp:443`; the server patch carries a bare `host[:port]`
`trustedHosts` entry; the client opens the token URL once (the 30-day absolute cookie, its renewal
and its lockout path are in the skill's `references/client-setup.md` §3); and neither end's browser
is proxying the tailnet.

## 17. Wake-up to-dos — the things only a human can do

Every line below is either **one paste-ready command** or **one UI click position**. The "why not
the machine" column is the reason the automation stops here; none of these is an oversight.

| # | what | how (one line) | why the machine cannot do it |
|---|---|---|---|
| **17.1** | sync the skill to the **user-level** copy — **already done** (11/11 files byte-identical, per-file SHA256 verified); re-run only after further skill edits | dry run: `powershell -NoProfile -ExecutionPolicy Bypass -File D:\DSH\.dsh\tools\sync-skill.ps1 -Check` then apply: `powershell -NoProfile -ExecutionPolicy Bypass -File D:\DSH\.dsh\tools\sync-skill.ps1` | the target `%USERPROFILE%\.dsh\skills\dsh-remote-tailnet` is **outside the agent's workspace sandbox** (the workspace is the repository root); writing there needs your authorisation |
| **17.2** | activate the plugin panel (approve once) | open the Run/approval card of the session titled **"AgentTeams automatic task assignment…"** and click the tick: **single tick = this package only, double tick = future versions of the same plugin** | an approval is a Web-UI user action, and the parked card belongs to **another session** — see the warning below |
| **17.3** | persistent install (optional) | run the read-only preflight (`powershell -NoProfile -ExecutionPolicy Bypass -File panel/plugin-preflight.ps1`), back up the profile patch (README §15.2, one block), then follow `docs/install/plugin-package.md` §5 (three steps) and roll back with §6 (four steps: `disabled: true` first, whole-file restore second) | it edits **your own** DSH profile file outside the workspace and needs explicit authorisation; the package ships with its row `disabled: true` and **has never been loaded on a real DSH** (§15) |
| **17.4** | publication decisions | the clone URL at the top of this file already carries the account (`KomeijiHonnouKai`) and the **repository name is settled** — that URL is the single source of truth; renaming stays a one-line edit per file | naming, ownership and identity are the maintainer's decisions; the **licence is already settled** (MIT, `Copyright (c) 2026 KomeijiHonnouKai`) |
| **17.5** | re-test the live link | `powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>` → expect `443 connected` / `135, 5357 timeout` / **EXIT 0**; then `… -Soak -Count 11 -IntervalSeconds 30` and state the verdict **with its window** | the 15-second check and the **11-round soak are both measured now** (see below: 3/3 in a 15-second window at 18:30, 11/11 over 305 s at 18:33–18:38) - but a link observation is per-machine and per-environment, so after a reset, a new client or a new tailnet this is the operator's run again |
| **17.6** | **uninstall / clean up (complete and clean)** | dry run first: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/uninstall.ps1 -Plan` - it prints the list and **writes nothing**; add `-Apply` only when you want the rollback actually performed (it backs everything up **before** the first change). Full procedure: **§21** below, plus the long-form write-up in **`docs/install/uninstall.md`** (ships in the release set). | three facts decide what it will **not** touch: (1) it reverts **only items the journal recorded *and* whose current value still equals what this tool's remediation would have produced** - anything somebody changed afterwards is reported and left alone; (2) the Tailscale installation itself, other DSH plugins and **any firewall rule you wrote yourself** are **kept by default**; (3) backups are **kept by default** and only an explicit `-PurgeBackup` clears them. A clean uninstall therefore never means "silently delete everything" |

### 17.1 Skill copy — and what is live right now

`D:\DSH\.dsh\tools\sync-skill.ps1` (already delivered; idempotent, per-file SHA256 compare, prints
`SAME`/`UPDATED` per file, never deletes, copies then re-verifies byte for byte, ASCII-only output;
exit `0` in sync, `1` source missing, `2` verify mismatch).

**Runtime effect, stated precisely** (skill-discovery ranking: `project-dsh` 100 beats `user-dsh`
400, first-seen wins):

- Sessions whose `cwd` is the repository root read the **workspace copy**, so the skill revisions
  are live there **today**.
- Sessions with **any other `cwd`** read the **user-level** copy, and that copy has been **synced**:
  the sync printed `updated=2` and then `verify OK: all files byte-identical`, so all **11 files are
  byte-identical** — including `references/verify.md` and `references/troubleshooting.md`, the two
  files this task touched. Both copies are therefore in effect **everywhere** today.
- The command is idempotent (per-file SHA256 compare, never deletes, copies then re-verifies byte for
  byte), so re-run it only after the skill is edited again.

### 17.2 ⚠️ The parked approval will fail where it is parked

The approval card for `panel-2` / `pkg-5` (a run that returned `awaiting-approval`) sits in a
**team-member session**, not in your own interactive session. Per §14.1 and its measured failure
text, activating a client-half package from a subagent-owned session ends in
`host-half-failed: session/agent-busy: session "<SUBAGENT_SESSION_ID>" is owned by subagent routing`
— and re-clicking only spends another approval for the same result.

- **If the card you are looking at is in that member session**: do not click it. Instead, in a
  normal interactive session, define a **new** plugin from `panel/host-half.js` +
  `panel/client-half.js` (new 3–6 letter idPrefix) and approve that one.
- **Measured positive path** (2026-09-24, default workspace session): defining a **new** package
  (`rtgpnl-3` / `pkg-6`) from `panel/host-half.js` + `panel/client-half.js` and calling
  `cordis_run(pluginId="rtgpnl-3", packageId="pkg-6", mode="run")` returned `awaiting-approval`;
  after the tick the run finished as **completed** (run 6) and the section showed up in the settings
  navigation. The same click performed on the parked member-session card ends in
  `host-half-failed: session/agent-busy` instead — that is the whole difference.
- **Success looks like** (either path): no `Failed to load plugins` banner, the settings navigation
  gains **`Remote access link (read-only posture)`**, and the four-state counts on the panel match
  `powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -AsJson`.
- **Failure rollback**: `cordis_stop("panel-2")` — or `cordis_stop("<the id you just created>")`,
  e.g. `cordis_stop("rtgpnl-3")` for the measured run above.

### 17.3 Persistent install (optional)

Use README §15.2 for the backup, §15.3 for the row and the switch, and `docs/install/rollback.md`
§2 for the file-level restore. Nothing here has been executed by this revision.

### 17.4 Before publishing to GitHub

The licence is settled (MIT, `Copyright (c) 2026 KomeijiHonnouKai` — reflected in `LICENSE`,
both READMEs, `CHANGELOG.md`). The **repository name is settled too**: it is the one in the clone URL
at the top of this file (renaming remains a one-line edit per file). The **account is filled in too**
(`KomeijiHonnouKai`, see the clone URL). What is still yours: creating that repository on GitHub and
the first `git push`. No binaries are attached by policy.

### 17.5 Link re-test — the peer dropped out and came back

Timeline, kept apart by evidence class:

| when | what | class |
|---|---|---|
| 17:36 | the skill's `verify.ps1` measured the peer `:443` as **connected (860 ms)** | cited (task t7) |
| from 17:44 | the peer `:443` was a sustained **timeout** | cited (task t9 brief) |
| 18:25 | my own `[Net.Sockets.TcpClient]` probe (5 s): peer `:443` = **timeout** | measured here (t9) |
| **18:30** | **peer answered again**: `verify.ps1` → `443 connected 189 ms`, `135 timeout`, `5357 timeout`, `VERDICT 全通`, **EXIT 0** | measured here (t9) |
| **18:30:36–18:30:47** | short soak, **3/3 connected** (194 / 203 / 194 ms) in that **15-second window** | measured here (t9) |

The local side was healthy throughout (tailnet address present, general outbound fine, DNS
resolving), so the 17:44–18:25 window was a peer-side or tailnet-side condition, not a local one.
The **11-round / 5-minute soak** (`-Soak -Count 11 -IntervalSeconds 30`) has been run and passed:
window **2026-09-24 18:33:16–18:38:18 (305 s)**, `SOAK total=11 connected=11 failed=0`, all eleven
rounds `connected` at 190 / 197 / 188 / 199 / 186 / 199 / 185 / 191 / 189 / 194 / 186 ms, verdict line
`VERDICT 全通:窗口内全部 connected`, **EXIT 0** (raw run in §18.1). Read it as a **window-limited
observation and not as "the link is stable"**: it says nothing about any second outside those 305 s,
and a link observation is per-machine and per-environment, so after a reset, a new client or a new
tailnet this is the operator's run again. If a re-run goes all-timeout, restart `tailscaled` on
**both** ends before touching any policy. The offline suites (§20) never depend on the peer.

Browser sanity check (one human action, once, on the client machine): open
`https://<HOST>.<TAILNET_DOMAIN>/?token=<token>` and paste the token yourself — this tool never
reads, prints or transmits it, and after that single visit the browser holds the long-lived cookie
(the skill's `references/client-setup.md` §3 covers its absolute expiry, the renewal path and the
lock-out case).

## 18. Evidence chain: measured here, cited from other tasks, still unverified

Three classes, never mixed. "Measured" means this task ran the command and saw the output; "cited"
means another task's result is reused verbatim and is only as strong as that task's evidence;
"unverified" means nobody has measured it yet.

### 18.1 Measured in this task (t9)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
# verdict: CLEAN (0 blocking finding(s))
# {"root":"…","files":85,"blockedHits":0,"credValueHits":0,"wordHits":194,"encodingFailures":0,
#  "lineEndingNotes":1,"binaryFailures":0,"forbiddenCode":0,"forbiddenDoc":2,"missingIgnores":0,
#  "missingMarkers":0,"unclassified":0,"blockingTotal":0,"verdict":"clean"}   exit 0

powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>
# 443 -> connected (189ms)   135 -> timeout (5006ms)   5357 -> timeout (5005ms)
# VERDICT 全通:443 connected,其余 2 个口均 timeout(ACL 隔离成立)      EXIT 0

powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP> -Soak -Count 3 -IntervalSeconds 5
# 18:30:36 #1 connected 194ms / #2 203ms / #3 194ms  ->  SOAK total=3 connected=3 failed=0
# VERDICT 全通:窗口内全部 connected                                   EXIT 0

powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP> -Soak -Count 11 -IntervalSeconds 30
# 11 rounds, window 2026-09-24 18:33:16–18:38:18 (305 s)
# connected 190 / 197 / 188 / 199 / 186 / 199 / 185 / 191 / 189 / 194 / 186 ms
# SOAK total=11 connected=11 failed=0
# VERDICT 全通:窗口内全部 connected                                   EXIT 0

powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-fixtures.ps1
# ALL PASS: 7 cases, 0 failed assertions                              EXIT 0
```

- Peer probe, 5 s timeout, `[Net.Sockets.TcpClient]`: **timeout at 18:25**, **connected at 18:30**
  (both runs quoted in §17.5).
- 11-round soak, measured after the short one: **11/11 connected, failed=0** over a **305-second**
  window (18:33:16–18:38:18), rounds at 190 / 197 / 188 / 199 / 186 / 199 / 185 / 191 / 189 / 194 /
  186 ms, `VERDICT 全通:窗口内全部 connected`, **EXIT 0**. Cited as a window-limited observation,
  exactly like the 15-second run above - neither says the link is "stable".
- Check inventory: `New-Check` occurrences = **25** in `src/collect.ps1` (24 items + one
  post-processing branch), and `panel/prereq-manifest.json` `items` = **13**.
- Release-set inventory: the gate's default roots cover the code directories (`src/`, `i18n/`, `tests/`,
  `panel/`, `tools/`) plus the published docs and root files; it prints the live file count, so this
  line does not freeze one. `plugin/package.json` is present (that is the persistent package, §15); the
  repository **root** carries no `package.json` (nothing in the test path needs one — see §19).
- Skill-file state used by §17.1 (both copies compared file by file with SHA256: 11 vs 11 files,
  9 identical, and the two files this task touched — `references/verify.md`,
  `references/troubleshooting.md` — differing ⇒ exactly the gap the sync command closes).
- Skill scripts re-parsed after the §17-era edits: `verify.ps1` and `server-setup.ps1` both report
  `errors=0` (`Parser::ParseFile`).

### 18.2 Cited (another task's command and result)

| claim | source task | command / raw result |
|---|---|---|
| client-side end-to-end verdict **pass** (peer `:443` connected 860 ms at 17:36) | t7 | `verify.ps1 -ServerIp <PEER_IP>` → `connected 860ms` |
| security review came back **needs_revision** (not a pass) | t8 | review verdict + findings list |
| the review findings were fixed, then re-reviewed | t16 (10/10), t19 (5/5), t17 re-review | per-finding disposition tables in those tasks |
| offline suite green | t23 | **52 cases / 52 passed / 0 failed / 0 xfail held / 0 xpass / ALL PASS**, exit 0 — the first run where xfail **and** xpass are both 0 |
| release-set hygiene | t12 (+ t24 for `panel/`, + t39 for `tools/`) | `verdict: CLEAN`, 0 blocking; t23's two scan scopes agreed as well — every raw hit outside the gate's own scope was an approved sanitized value or a documented fixture, and neither summary froze a file count |
| `SERVE_PRESENT` semantics refreshed (evidence only from a readable `serve status` proxy target; unreadable ⇒ unknown) | t23 | code + case expectations; `docs/collect.md` text refresh is **t25's** |
| `panel/` is part of the published release set; licence settled | t24 | README §8/§12, `.gitignore` unexcluded, gate default roots |

### 18.3 Unverified / not measurable here

- **A live Windows 11 client** — no such machine was available; combinations B and D therefore reuse
  the Win10 client code path without a live run (see §16).
- **Win11 → Win11 end-to-end** — fixture coverage only (`tests/fixtures/win11-server.json`).
- **An adapter attributed to the `Public` profile** — `[only derivable from the rules' `Profiles`
  field]`; the silent-failure consequence is **not** measured on a Public machine, so it must never
  be reported as "verified".
- **Server-side HTTPS/certificate judgement** — schannel is unusable in the restricted context, so
  the HTTPS verdict exists only where an OpenSSL-capable probe can run.
- ~~**A successful dynamic-package activation**~~ — **moved out of this list**: measured 2026-09-24 in
  an ordinary workspace-level session (`rtgpnl-3` / `pkg-6` → `awaiting-approval` → tick → run
  **completed**, panel visible in the settings navigation; §14.1 and §17.2 carry the positive path
  next to the measured member-session failure). Only the failure mode on *other* machines remains
  unverified.
- **The persistent plugin package** — shipped in `plugin/` with its mount row `disabled: true`, and
  never enabled on a real machine (§15; the unexecuted list is `docs/install/plugin-package.md` §9).

### 18.4 Connectivity: what the peer outage did and did not affect

Between 17:44 and ~18:30 the peer was unreachable, so the two-machine items could not be re-measured
in that window. **Nothing was failed because of it and nothing was papered over**: with the peer
absent, the offline layer (the 24-check collector on fixtures, the 13-item prerequisite checker, the
`run-fixtures` suite, the hygiene gate) was still fully measurable — that is the point of the
offline seam — and the two-machine items were recorded as `timeout` rather than as a verdict. At
18:30 the peer answered again and the tri-state plus a short soak were measured directly (§18.1).
Still open: the client-side MagicDNS/HTTPS items on a machine other than this one (§17.5, §18.3).
The 11-round soak is **not** on this list any more - it was measured (§18.1) - but a link observation
belongs to the machine and environment it was taken on, so a reset, a new client or a new tailnet
means the operator runs it again (§17.5).

## 19. Open items and deliberate decisions (please do not "fix" these)

### 19.1 Fixture and runtime decisions

- **The Ethernet interface's default gateway sits outside its `10.20.0.0/16` prefix.** That is
  **faithful to the original capture** (a VPN/point-to-point shape) and is deliberately not
  smoothed: do not "correct" it. The VPN adapter's own prefix, mask and gateway, by contrast, were
  converged into the RFC 5737 documentation range (`198.51.100.11` with a matching `/24` prefix and
  gateway) so nothing in the fixture looks like a real machine.
- **Product constants are kept on purpose**: `0.0.0.0`, `127.0.0.1`, `100.64.0.0/10`, the Tailscale
  IPv6 `/48` product prefix, the masks, and `192.0.2.20`.
- **Sanitization replacement values** (never replace them with "real-looking" values): `100.64.0.11` for
  the local side, `100.64.0.12` for the peer side, `10.20.x` / `10.21.x` / `10.22.x` for the
  private ranges, and host replacement values such as `<HOST_A>` / `<HOST_B>`.
- **Release set vs internal material**: the research notes, review reports and verification transcripts
  are **excluded by `.gitignore`** and are not published — section 1 of that file is the list of record,
  and the hygiene gate fails if the exclusion list is incomplete. (This file deliberately does not
  repeat the names: naming them here is what "deep-linking internal material" would look like.)
- **The approved panel package is not the current repository source.** `panel-2` / `pkg-5` was
  defined from the t6 revision and does **not** include the later fixture-path allow-list that was
  added to `panel/host-half.js`. The difference is confined to the optional `fixture` debug
  parameter — the normal path is identical. If you require "approved == repository source", define
  a new package with `cordis_define(kind=existing, pluginId="panel-2")` and run it (a fresh approval
  card appears).
- **Dynamic packages have no durable life**: `guard-1` and `panel-2` belong to the session that
  defined them, are not written to disk, and disappear with the process or session. The panel has a
  fallback for a missing `guard-1` (it runs the collector itself, `source=direct`), and
  `source=direct` is **not** a fault. To reuse the shared Service, define and run again
  (`docs/install/install.md` §1).
- **Known framework defect (do not redo work because of it)**: when a deliverable lives under
  `.dsh/`, the AgentTeams `changedPaths` validator hard-excludes it (`quality-gates.js:114-134`).
  That is why task t4 could only close as failed and t18 had to close as a work-kind task; the
  measured note (including the BOM-loss and peer-unreachability timelines) is at
  `.dsh/notes/agentteams-changedpaths-dsh-exclusion.md`.

### 19.2 Tracked but not yet closed (owned elsewhere — not claimed as done)

| item | owner | state |
|---|---|---|
| `docs/collect.md` `SERVE_PRESENT` prose refresh | t25 | the code/verdict semantics are already t23's (see §13.1 row 17); the document text is not yet refreshed |
| GitHub account in the clone URL — **closed** | maintainer | done: the clone URL at the top of this file carries the account (`KomeijiHonnouKai`); what remains is creating the GitHub repository and the first push (§17.4) |
| file-count口径 in the two hygiene summaries (this file's default roots vs t23's scan scopes) | t24/t39 | the difference is the default-root scope (`panel/`, then `tools/`, then `plugin/`); both report **0** non-allow-listed hits, and neither summary freezes a count |
| plugin-list card seat on the "Settings → Plugins" page (`settings.plugin.item`) | t46 | **seat implemented in the package, real loading still unverified**: the client half registers the card beside the settings section, keyed by `SETTINGS_NS` = `'remote-tailnet-guard'`, and the host half registers a settings namespace with that same name (empty schema) - that registration is the card's gate, because the seat owner renders one card per **served** namespace only. When it does not happen the card **does not appear** and the rest keeps working (`docs/install/plugin-package.md` §9 item 7). Nobody has loaded the package in a real DSH yet (see the GUI section and §15) |

**Closed since the first draft of this table:** the stale case counts that used to appear in §1/§5
here, in `CONTRIBUTING.md` and in `CHANGELOG.md` were refreshed (t24 for `CONTRIBUTING.md`, t28 for
the other three places). Nothing in the publish set quotes a frozen pass count any more - the suite
prints its own header and its case count is simply the number of directories under `tests/cases/`
(64 on 2026-09-24, 0 `xfail` held). Run the command in §20 and read the header rather than this line.

## 20. Delivery checklist and the three commands a stranger needs

| item | path | state |
|---|---|---|
| offline regression entry | `tests/run-tests.ps1` (64 cases) | present |
| offline fixture entry (deterministic, no probes) | `tests/run-fixtures.ps1` (7 cases) | present, `ALL PASS / 0 failed / exit 0` |
| offline smoke entry (one command, one exit code) | `tests/run-smoke.ps1` | present; exit `0` all green, `1` degraded (a SKIP but no FAIL), `2` broken |
| collector | `src/collect.ps1` (24 checks) | present |
| prerequisite checker + manifest | `panel/prereq.ps1`, `panel/prereq-manifest.json` (13 items) | present |
| plugin halves | `src/host-half.js`, `panel/host-half.js`, `panel/client-half.js` | present |
| persistent plugin package | `plugin/package.json`, `plugin/cordis.patch.yml`, `plugin/lib/index.js`, `plugin/lib/client.js`, `plugin/lib/client/index.js` | present, published; the mount row is `disabled: true`, so it is inert until enabled (§15) |
| persistent-package preflight (read-only, 0/1/2) | `panel/plugin-preflight.ps1` | present; measured `checks: 66  passed: 66  failed: 0  skipped: 3`, exit 0 (re-run for this revision) |
| persistent-package write-up (enable/verify/rollback) | `docs/install/plugin-package.md` | present, published |
| CI | `.github/workflows/ci.yml` + `.github/scripts/repo-hygiene.ps1` + `.github/scripts/check-workflows.py` | present |
| `LICENSE` / `README.md` / `README.en.md` / `SECURITY.md` / `CHANGELOG.md` / `CONTRIBUTING.md` | repository root | present |
| `.gitignore` / `.editorconfig` | repository root | present |
| uninstaller (the one optional write component) | `tools/uninstall.ps1` | present; dry-run by default, `-Apply` required, backup before the first change (§21) |
| root `package.json` | — | **absent on purpose** (nothing in the test path needs one; the persistent package carries its own `plugin/package.json`) |

Clone → self-proof, three commands:

```powershell
# 1) deterministic, offline, no machine probes at all - expect: ALL PASS: 7 cases, 0 failed assertions
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-fixtures.ps1

# 2) the full offline suite - expect: 64 cases, 64 passed, 0 failed, 0 xfail held, 0 xpass (exit 0)
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1

# 3) the release-set gate - expect: verdict: CLEAN (0 blocking finding(s)), unclassified=0 (exit 0)
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
```

Then, on a machine you want to inspect for real (read-only, no writes anywhere):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly
```

Read its exit code as a **fail-closed verdict**, not as a command failure: `0` all proven, `1` at
least one degraded/unknown, `2` at least one blocked (or the collector could not run at all).
Nothing in this repository needs a token, a cookie, or a credential of any kind to run.

---

## 21. Uninstall and residue — complete, clean, and never silent

`tools/uninstall.ps1` is the repository's **only optional write component**. It is off by default:
without `-Apply` it observes and prints, and it writes a backup **before** the first change rather
than after it. Long form: [`docs/install/uninstall.md`](docs/install/uninstall.md) — the same six
steps, with the observation to expect at each one.

### 21.1 The six steps (1, 3 and 4 write nothing)

| step | command | what it does |
|---|---|---|
| 1. RecordBefore | `tools/uninstall.ps1 -RecordBefore` | snapshots the link's surfaces (firewall rules, `tailscale serve`, power settings, DSH profile rows, plugin rows) into the journal |
| 2. remediation | *(your commands, from the collector's output)* | the actual fix is executed by **you**; the tool never runs a fix for you |
| 3. RecordAfter | `tools/uninstall.ps1 -RecordAfter` | re-reads the same surfaces so a later rollback can tell "changed by us" from "already like that" |
| 4. Plan | `tools/uninstall.ps1 -Plan` | classifies every recorded item (table below) and writes nothing |
| 5. Apply | `tools/uninstall.ps1 -Apply` | performs **only** the `revert` rows, after writing the backup; `-RemoveFiles` extends it to the files it wrote |
| 6. residue + backups | `tools/uninstall.ps1 -CheckOnly` | reports what is left behind and what the backup directory still holds; backups stay until `-PurgeBackup` |

### 21.2 The four classifications

| class | meaning | does `-Apply` touch it? |
|---|---|---|
| `noop` | the surface already looks the way this tool's remediation would have left it, and the journal recorded that change | nothing to do |
| `revert` | the journal recorded the change **and** the current value is still exactly what this tool's remediation produced | **yes** — reverted, with a backup written first |
| `left-alone` | the journal recorded a change, but the current value is **not** what this tool produced (somebody edited it afterwards) | **no** — reported only, never overwritten |
| `unknown` | no journal entry, or the surface cannot be read (denied, unavailable, exempt) | **no** — reported as `unknown`, and it is exactly what the exit code is there for |

### 21.3 Exit codes

| exit | meaning |
|---|---|
| `0` | clean: nothing left to revert and nothing unattributable |
| `1` | fail-closed: something is `left-alone`, `unknown` or unattributable — read the report and decide by hand (a machine with no journal answers `attribution=unavailable`, never a green light) |
| `2` | refused: an invalid argument, a path outside the verified directories, or `-PurgeBackup` without `-Apply` |

### 21.4 What stays untouched, and the promise boundary

- **Kept by default**: the Tailscale installation itself, other DSH plugins and their configuration, and
  every firewall rule you wrote yourself. `-KeepTailscale` only expresses that intent inside the plan;
  no value of it uninstalls Tailscale.
- **Backups are kept by default**, in the backup directory, until `-PurgeBackup` says otherwise.
- **The promise boundary**: the collector (`src/collect.ps1`) and the prerequisite checker
  (`panel/prereq.ps1`) still have **zero write paths** — they detect and report. `tools/uninstall.ps1`
  is this repository's single **optional write** component: dry-run by default, `-Apply` required, a
  backup before the first change, and every reverted item traceable to a journal record.
- Two recorded limits of that component (kept, not hidden): its system-level rollback commands and its
  two in-process file edits have been verified statically and by branch, **not** executed on a real
  machine — doing so would change this machine's firewall, power settings, `tailscale serve` state and
  the real files under the DSH home; and a rollback is only as good as its journal, so "no journal"
  means `unknown` plus exit `1`.
