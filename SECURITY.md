# Security policy and verifiable promises

- **Last updated**: 2026-09-25(v1.5; **P9 re-scoped after the smoke audit** — the route of the packaged
  plugin (`plugin/lib/index.js`, `POST /dsh-crossnet-link/api/posture`) **does not go through DSH's web
  authentication**, is reachable **only over loopback while DSH listens on loopback**, and becomes
  **reachable from the tailnet as soon as the DSH port is published with `tailscale serve`**; it returns
  **read-only posture results only**. v1.4 added P9 with a flat "loopback-only" claim, which is wrong
  under a served deployment — the wording changed (here and in the README §8 wording it mirrors), the
  measured facts did not. No P1–P8 promise was touched. v1.3: t27 re-checked every internal-document reference in this file —
  **0 hits** — and added the Link scope bullet below; no promise was touched. v1.2: t23 made **P2 relative** — the absolute file count is a moving
  target in a tree other tasks also write to — and left every other promise untouched). v1.1 was the
  t20 refresh of the measured values and source line numbers. Original draft: t16 repair-round-2,
  written to satisfy review finding F8. **Ownership**: this file is the delivered draft — t12 owns the
  proofread and the README link only; it will **not** be rewritten. Every promise below therefore ships
  with the exact command that checks it and the value measured on the reference machine, so a reviewer
  can re-run the whole list instead of trusting this text.
- **t20 re-check (2026-09-24)**: every P1–P8 command below was re-run on the current tree. What moved:
  P3 line refs `panel/prereq.ps1:22/:395` → **:23/:487**, P4 declaration line `src/collect.ps1:1885` →
  **:1907**, P5 text hit `src/collect.ps1:1860` → **:1882**; P2 became a **relative** promise in t23 (see
  P2). Every other expected value (0 hits / exactly 2 reviewed exceptions / 1 text-only hit) reproduced
  unchanged.
- **Promise index**: P1 no new listener / P2 read-only by default / P3 no automated write or elevation /
  P4 no credential access / P5 no telemetry or callback / P6 no restart logic / P7 reversible
  (`ctx.effect`) / P8 panel is display-only / P9 plugin route bypasses DSH web auth (loopback by
  default, tailnet-reachable once the DSH port is served, read-only).
- **Commands used (all read-only)**: see §2 — each promise lists its own command; the results in the
  "measured" column come from running them in this repository on 2026-09-24.
- **Link scope (t27, 2026-09-24)**: this file links **no internal analysis material**. Its only
  document link is [`docs/threat-model.md`](docs/threat-model.md), which is a **release-set member**
  (the release roots are `.github/scripts/repo-hygiene.ps1` §0 and the excluded set is `.gitignore`
  §1). Where an internal conclusion matters it is restated here instead of linked, or pointed at a
  published file — e.g. the write gates live in `CONTRIBUTING.md` §1. **How to re-check**: scan this
  file for any name listed in `.gitignore` §1 (the single source of truth for internal material);
  expected **0 hits** — measured 0 on 2026-09-24 (t27). The only names that may appear here are
  release-set members such as `docs/threat-model.md` and `docs/install/install.md`.

Scope: everything under `dsh-crossnet-link/` — the read-only collector (`src/collect.ps1`), the
host/client halves (`src/host-half.js`, `panel/*.js`), the prerequisite checker
(`panel/prereq.ps1`) and the docs. It does **not** cover the DSH product itself or the
`dsh-remote-tailnet` skill (separate artefacts, separate reviews).

---

## 1. Threat model and known trust assumptions (know these before deploying)

The full model lives in [`docs/threat-model.md`](docs/threat-model.md). The three assumptions that
matter most:

1. **Being able to open the UI equals being able to operate that machine.** The DSH UI carries
   session, file and tool-execution capability. Anyone with interface access (a leaked token URL, a
   valid 30-day cookie, any local process on the server, any tailnet node the ACL admits) has that
   capability.
2. **Loopback is trusted by design.** A local process can open `http://127.0.0.1:43120` without a
   token or cookie. This plugin does not change that; it also never widens it (no new listener, no
   proxy) — but reachability belongs to the web server, not to the plugin: publishing that server
   with `tailscale serve` publishes this plugin's route with it (P9).
3. **DERP relays see connection metadata, not content.** Relayed traffic is WireGuard-encrypted;
   a relay can observe which nodes talk, when, and how much — not HTTP bodies, tokens or cookies.

---

## 2. Promises, each with its verification command

Every row is a promise plus a command you can run yourself. "Measured" is the result on the
reference machine (Windows 10 Pro 19045.6036, Windows PowerShell 5.1.19041.6033). `$P` below means
the repository path of this plugin.

### P1 — No new listening socket, route or firewall rule

```powershell
Select-String -Path "$P/src/collect.ps1","$P/src/host-half.js","$P/panel/host-half.js","$P/panel/client-half.js" `
  -Pattern 'TcpListener|HttpListener|webServer\.register|New-NetFirewallRule|Set-NetFirewallRule|serve --bg|\.listen\('
```

- Expected: **0 hits**. Measured: **0 hits**.
- Runtime companion (the report proves its own read-only property):
  `powershell -NoProfile -ExecutionPolicy Bypass -File "$P/src/collect.ps1" -CheckOnly -AsJson` →
  `NO_NEW_WILDCARD_LISTENER = pass`, and `(netstat -ano | Select-String '(0\.0\.0\.0|\[::\]):43120').Count` → `0`.

### P2 — Read-only by default

```powershell
# reproducible relative check: the two counts must be equal
$before = (Get-ChildItem dsh-crossnet-link -Recurse -File).Count
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -AsJson | Out-Null
$after  = (Get-ChildItem dsh-crossnet-link -Recurse -File).Count
"before=$before after=$after   # equal unless somebody else wrote into the tree during the window"
```

- **The promise is relative**: one default run adds and removes **nothing**. The absolute file count is
  deliberately *not* the promise — other tasks write into this tree concurrently, so any fixed number
  goes stale within minutes (t20 recorded `85`, the t21 review saw `88`, t23 measured `93`).
- Measured (t23, 2026-09-24): run1 `before=93 after=93`, run2 `before=93 after=93` — delta 0.
- Attribution of a non-zero delta, measured independently in the t21 review: run1 `before=87 after=88`,
  and the single added file was `.github/workflows/ci.yml`, written by the release task (t12) during the
  window — **not** by the collector; its run2 was `before=88 after=88`. That is what "a difference is
  attributable to a concurrent unrelated write, and has to be shown as such" means in practice.
- The collector's only write paths are the explicit opt-ins `-OutFile <path>` and
  `-DumpFixture <path>`; without them it writes **zero bytes**. `panel/prereq.ps1` has no output-file
  switch at all.

### P3 — No automated write anywhere; `-Apply` is refused

```powershell
Select-String -Path "$P/src/collect.ps1","$P/panel/prereq.ps1","$P/panel/host-half.js","$P/src/host-half.js" `
  -Pattern 'Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|New-Item -|Remove-Item |Start-Process|runas|msiexec|Register-ScheduledTask|Set-ExecutionPolicy'
```

- Expected: **only reviewed exceptions**, none of which executes anything:
  - `panel/prereq.ps1:23` — a header comment listing what the script never does ("no elevation, no
    runas, no scheduled task…").
  - `panel/prereq.ps1:487` — `if ($installCmd -match 'msiexec') { … }`, a **string test** that decides
    whether to display the hash gate; the matched text is printed, never run.
- Measured: exactly those 2 hits, both classified above; behaviour check
  `powershell -NoProfile -ExecutionPolicy Bypass -File "$P/panel/prereq.ps1" -CheckOnly -AsJson` →
  `ranAnyInstall=false`, `readOnly=true`.
- `src/collect.ps1 -Apply` refuses with exit code **2** and prints what a human must run instead.
- Deliberate scope note: there is no `-AllowWrite`/`-Yes` switch because this version has **no write
  path to gate**. If one is ever added, the four gates in `CONTRIBUTING.md` §1 (Hard rules) apply.

### P4 — No credential is read, printed, stored or transmitted

```powershell
# real access shapes (path reads): must be 0
Select-String -Path "$P/src/collect.ps1","$P/panel/prereq.ps1","$P/panel/host-half.js","$P/panel/client-half.js","$P/src/host-half.js" `
  -Pattern 'Get-Content .*credentials|\.credentials\.yaml"|ext-bridge-token"|Network\\Cookies'
```

- Expected: **0 hits**. Measured: **0 hits**.
- A broader scan does hit one line — `src/collect.ps1:1907`,
  `$c.raw.declaredNotRead = @('.dsh\.credentials.yaml','ext-bridge-token','browser cookie databases',…)`
  — which is the **declaration of what is deliberately not read**, not an access.
- Runtime companion: `CREDENTIAL_DISCIPLINE = pass` in the report (re-measured in t20); it re-audits
  every probe command string it executed and fails closed if a secret-store hint ever appears.
  Independent check re-run in t20 on the current **312,870-byte** `-CheckOnly -AsJson` report: the four
  access-shaped patterns (`tskey-…`, `eyJ…`, `?token=…`, `Network\Cookies`) → **0 hits**. The literal
  names `.credentials.yaml` and `ext-bridge-token` do appear once each — that is the `declaredNotRead`
  declaration quoted above, i.e. the line stating they are deliberately never read.
- The bridge never forwards `raw` blocks, so no file content crosses to the panel
  (`src/host-half.js` → `toBoundedChecks`, `panel/host-half.js` → `boundedCheck`).

### P5 — No telemetry and no callback

```powershell
Select-String -Path "$P/src/collect.ps1","$P/panel/prereq.ps1","$P/panel/host-half.js","$P/src/host-half.js" `
  -Pattern 'Invoke-WebRequest|Invoke-RestMethod|System\.Net\.WebClient|DownloadString|\bcurl\.exe\s|\bfetch\s*\('
```

- Expected: **no call sites**. Measured (t20): 1 hit — `src/collect.ps1:1882`, a *reason string* that says
  "curl.exe under schannel returns 000 even when the server is healthy". Text only.
- The collector's entire network surface is .NET `TcpClient` / `Dns` against a peer the **operator**
  supplies (`-Peer`/`-PeerName`), each with an explicit timeout (≤5 s / ≤4 s), and the client-side
  probes do not run at all when no peer is given. Verified by
  `Select-String -Path "$P/src/collect.ps1" -Pattern 'TcpClient|BeginGetHostAddresses'`.
- `panel/prereq.ps1` performs **no network probe**.

### P6 — No restart plugin logic, and nothing that could strand the DSH host

```powershell
Select-String -Path "$P/src/host-half.js","$P/panel/host-half.js","$P/panel/client-half.js" -Pattern 'relaunch|taskkill|Stop-Process|process\.kill|detached'
```

- Expected: **0 hits**. The DSH host is an Electron `utilityProcess` child that throws without its
  supervisor (`app\lib\host-process-entry.js:202-203`), so any "kill the host and relaunch it"
  design fails structurally. This plugin contains none.
- Measured: **0 hits** across `src/host-half.js`, `panel/host-half.js`, `panel/client-half.js`.

### P7 — Reversible: all side effects hang off `ctx.effect`

```powershell
Select-String -Path "$P/src/host-half.js","$P/panel/host-half.js" -Pattern 'ctx\.effect|ctx\.provide|harness\.handle|harness\.registerTool|terminate\(\)'
```

- Expected: each registration is inside one `ctx.effect(...)` callback whose disposer removes it, and
  a running collector child is terminated there too. `cordis_stop("<pluginId>")` therefore removes the
  Service, the private method and the tool in one step.
- Measured: in `src/host-half.js` all three registrations (`ctx.provide`, `harness.handle`,
  `harness.registerTool`) sit **inside** the single `ctx.effect(...)` callback, and that callback's
  disposer also calls `activeHandle.terminate()`; in `panel/host-half.js` the single
  `ctx.effect(...)` owns its `harness.handle`. Both files are balanced (`braces`/`parens` net 0) and
  end with `return { … };`.
- Snapshot honesty: dynamic packages live in process memory and vanish on restart —
  `cordis_inspect_self()` returned `{"mode":"plugins","plugins":[]}` during the t16 round, i.e. the
  packages had already gone. Re-define + re-run per `docs/install/install.md` §1 to re-observe.

### P8 — The panel is display-only

```powershell
Select-String -Path "$P/panel/client-half.js" -Pattern 'document\.|window\.|navigator\.|localStorage|fetch\(|XMLHttpRequest'
```

- Expected: **0 hits** (the client sandbox exposes only `React` and `host.call`). The panel renders the
  host's bounded verdict fields plus the credential-discipline notice; it cannot read a cookie, a token
  or page storage because it never touches those APIs.
- Measured: **0 hits**; the only `host.call` in the file is the single posture call
  (`host.call(METHOD, { role: role })`, line 109).

### P9 — The plugin route does not go through DSH's web authentication

```powershell
# the route's own answer proves it reached the handler (the plugin answers 405 to GET, "POST only")
# and DSH's own page on the same origin answers 401 (it does require the web session):
Invoke-WebRequest -Uri 'http://127.0.0.1:43120/dsh-crossnet-link/api/posture' -Method GET -SkipHttpErrorCheck |
  Select-Object StatusCode, Content
Invoke-WebRequest -Uri 'http://127.0.0.1:43120/' -Method GET -SkipHttpErrorCheck | Select-Object StatusCode
```

- **The statement (identical wording to README §8, one fact, one phrasing)**:
  > Routes registered on the existing web server skip DSH web auth. DSH listens on
  > loopback by default, so the route is reachable from this machine only; publish the DSH
  > port with `tailscale serve` and the same route becomes reachable from the tailnet (the
  > same-origin check is void without an `Origin` header). It is read-only, returns posture
  > results only, reads no credentials and is not RCE; the risk is a resource-consumption
  > surface -- a peer can trigger the collector repeatedly.
- **Why "loopback-only" needs that qualifier (v1.5)**: the plugin binds nothing of its own — it registers
  a prefix on DSH's existing web server (`ctx.get("webServer")`), so it inherits whatever reachability
  that server has (P1). Under DSH's default loopback listener that is this machine only; under
  `tailscale serve --bg` the same server is published on the tailnet, and this route with it. Nothing
  about the plugin differs between the two deployments — the exposure is a deployment choice, and the
  promise has to say so.
- Measured on the peer machine (2026-09-25, read-only): `GET /` → **401** (DSH's own page does require the
  web session) while `GET /dsh-crossnet-link/api/posture` → **405** with
  `{"code":"method-not-allowed","message":"POST only"}` — i.e. the request **reached the plugin's own
  handler** instead of being stopped by web auth.
- **Boundary of the same-origin check, stated honestly**: `guardOrigin` in `plugin/lib/index.js` **lets a
  request through when the `Origin` header is absent**. So "same-origin validation" only constrains
  browser cross-origin pages — it does **not** constrain an arbitrary local process, nor a tailnet peer
  that speaks HTTP without an `Origin` header. That is consistent with §1's trust assumption ("loopback
  is trusted by design"), and it is **not a defect**: the route is read-only and returns no credentials.
  The honest caveat is about who can reach it, not about what it can do.
- **Cost, so it is not a surprise**: every request spawns one PowerShell collector child
  (`graceMs` 120 s, stdout ≤ 8 MiB), which any process that can reach the route can trigger repeatedly
  (local by default, a tailnet peer under `tailscale serve`). Low-severity resource surface, not a
  privilege boundary — do not treat this route as an authenticated API.
- Scope note: this applies to the **packaged plugin** route. The dynamic-package path uses a private
  `harness.handle` method that is not exposed over HTTP at all (P1).

---

## 3. Reporting a problem

Open an issue with: the exact command, its raw output, the collector's `-AsJson` report
(`summary` + the affected `checks[]`), and the OS/PowerShell/Tailscale versions. Please **redact**
any token, cookie, tailnet name, hostname or address before pasting — this project's own docs and
fixtures use placeholders (`<TOKEN>`, `<HOST>`, `<DSH_HOME>`, `<MSI_PATH>`) for exactly that reason.

Security-relevant behaviour that is *by design* and therefore not a vulnerability report:

- `unknown` verdicts on a machine where the named pipe, elevation or the peer is unavailable.
- Non-zero exit codes on a client-only machine when `-Role both` (the default) is used.
- A local process being able to open `http://127.0.0.1:43120` (DSH's loopback trust model — see §1).
