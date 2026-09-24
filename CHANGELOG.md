# Changelog

LAST UPDATED  : 2026-09-25 (readability round: both READMEs rewritten for a first-time reader; the
                evidence ledger and the decision log moved into `docs/evidence.md` and
                `docs/decisions.md`; `tests/readme-style-check.ps1` added as a layout gate; the hygiene
                gate's default roots extended to those two documents. Previously 2026-09-24 - task t4 -
                documentation calibration: the shipped docs now state the measured
                counts; task t39 recorded the uninstaller and `tools/` joining the published release set;
                t28 relativeised the last stale case count and t24 settled the MIT licence and the
                repository name)
COMMANDS USED : powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
                powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -SelfTest
                powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1
                powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-fixtures.ps1

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project intends to follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**License: MIT.** The repository ships the full MIT text in [`LICENSE`](LICENSE) with the
copyright line `Copyright (c) 2026 KomeijiHonnouKai`. The choice is settled, so nothing here
should be read as a provisional grant.

## [Unreleased]

### 2026-09-25 - documentation readability round

- **`README.md` was rewritten for a first-time reader.** It shrank from 970 lines to 220 (the
  project target was 220 or fewer) and now passes `tests/readme-style-check.ps1` with exit code 0:
  numbered section headings, full-width punctuation in the Chinese prose, one idea per paragraph,
  no internal task numbers and no frozen gate counts.
- **`README.en.md` was rewritten as a structural mirror of the Chinese file.** The two files now
  carry the same ten numbered `##` sections in the same order and differ only in language; the
  English file is not subject to the full-width punctuation rule.
- **`docs/evidence.md` and `docs/decisions.md` are new published documents.** The evidence ledger
  (measured / quoted / unverified, the three never mixed) and the decision and open-item log moved
  out of the README, because a ledger written for maintainers is not first-run documentation.
- **`tests/readme-style-check.ps1` is a new layout gate for the README.** It measures line count,
  display width, parenthesis density, bold density, the table budget, section references, task tags
  and heading numbering, and follows the project's exit-code convention: 0 clean, 1 advisory only,
  2 blocking. The README points at it, so a contributor can run the same gate before a change.
- **The hygiene gate's default roots grew by those two documents.**
  `.github/scripts/repo-hygiene.ps1` lists `docs\evidence.md` and `docs\decisions.md` in
  `$PublishRoots`, so a clone contains them and the release-set scan covers them instead of sitting
  beside them.

### Added

- **Read-only collector / judge** - `src/collect.ps1`. 24 checks, four verdicts
  (pass / degraded / blocked / unknown), fail-closed exit codes 0 / 1 / 2, pure ASCII so it
  runs under any system code page, fixture injection (`-FixturePath`, `-NoNative`) so it can
  be tested without Tailscale, without elevation and without a peer.
- **Prerequisite checker** - `panel/prereq.ps1` plus the machine-readable manifest
  `panel/prereq-manifest.json`: 13 items with role (server / client / both), OS, detection
  method, bilingual missing-item text, the install command to *show* (never to run), the
  hash and signature verification commands and the rollback command.
- **DSH plugin (dynamic Cordis package)** - host half `src/host-half.js` and the panel
  `panel/client-half.js` + `panel/host-half.js`. The panel registers in the real
  `settings.section` slot, is display-only, and renders the four-state posture plus the
  human steps. Every registration hangs off `ctx.effect` so `cordis_stop` removes it.
- **i18n layer** - `i18n/labels.en.json`, `i18n/labels.zh.json`. All human-readable text
  lives here and is read through an explicit UTF-8 decoder; the scripts stay ASCII.
- **Offline test suite** - `tests/run-tests.ps1`, one case per directory under `tests/cases/`
  (52 today; the suite header prints the live count). Fault injection, locale traps, isolation,
  portability and static scans. No Pester, no module, no network; the suite creates temp
  directories under `%TEMP%` only.
- **Documentation** - `docs/collect.md` (implementation notes, 24 checks, exit codes),
  `docs/threat-model.md` (who can see and do what), and `docs/install/` with
  `prerequisites.md`, `install.md` (dynamic package first, persistent profile clearly marked
  as needing explicit approval) and `rollback.md` (per-line rollback plus the evidence log).
- **Uninstaller (the repository's only optional write component)** - `tools/uninstall.ps1`, shipped in
  the published release set. Dry-run by default: `-Plan` prints what it would do and writes nothing,
  `-Apply` performs the rollback and writes a backup **before** the first change, `-PurgeBackup` is the
  only way the backup directory is cleared. It reverts **only** items the journal recorded whose current
  value still equals what its own remediation would have produced — anything changed afterwards is
  reported and left alone — and it keeps the Tailscale installation, other DSH plugins and firewall
  rules the operator wrote. Four classifications (`noop` / `revert` / `left-alone` / `unknown`) and exit
  codes `0` / `1` / `2` are documented in README §21.
- **Repository layer** - this changelog, `README.md`, `CONTRIBUTING.md`, the `LICENSE` file,
  `.gitignore`, `.editorconfig`, the two CI gates under `.github/scripts/`
  and the workflow `.github/workflows/ci.yml` (windows runner, the test suite, a pinned
  PSScriptAnalyzer and both hygiene gates).

### Changed

- **Documentation calibration** - `docs/collect.md` and `docs/install/install.md` now state the measured
  counts. The collector reports **26 checks** (the 24 already documented plus two server-side checks,
  `SERVER_PROXY_STATE` - WinINET system-proxy state, reported `degraded/proxy_active_route_intact` when
  enabled because a WinINET proxy never changes the inbound path - and `TAILNET_ROUTE_PRESENT` - a
  destination inside `100.64.0.0/10` in `route print -4`, reported `blocked/route_tailnet_missing` when
  absent). The offline suite runs **70 cases** (was 64) and the release set is **116 files** (was 110).
  No verdict logic, history or fixtures were changed.
- **`tools/` joined the published release set**: the hygiene gate's `$PublishRoots`, README §8, the CI
  workflow's scope note and section 1 of `.gitignore` now list it, so a clone contains the uninstaller
  and the gate scans it. Without this, "complete, clean uninstall" could not be true for anybody who
  cloned the repository rather than receiving it with the tool.
- **The read-only promise got an explicit boundary**: the collector (`src/collect.ps1`) and the
  prerequisite checker (`panel/prereq.ps1`) still have zero write paths, and `tools/uninstall.ps1` is
  named as the single _optional write_ component - dry-run by default, `-Apply` required, backup before
  the first change (README §3, §21).
- `panel/` is now part of the published release set and of the hygiene gate's **default scan
  roots**, so the prerequisite checker, its manifest and both panel halves are covered by the
  gate instead of sitting beside it (they previously needed an `-ExtraRoots panel` argument).
- The hygiene gate **fails on an unclassified token**: its header already promised "no silent
  pass", but the blocking count ignored unclassified tokens. The gate now counts them, marks
  `[4/8]` accordingly, reports them in `-Json`, and its self-test proves that one unapproved
  token alone flips the verdict to FAIL.
- License wording is final: `README.md` and this changelog state MIT with the copyright line
  above rather than a provisional status.
- The repository is named **for the function** it implements - a cross-network DSH link - and not
  for a security property: the security posture belongs in `SECURITY.md` and the design notes, not
  in the name.
- `README.md` states the stance in one place: the plugin is **read-only and report-only** - it does
  not modify the firewall, does not require a change to an existing DSH profile or to another
  plugin's configuration, and does not restart DSH. Every suggested fix is run by the operator, with
  its rollback and affected surface documented.
- The last frozen case counts are gone: `README.md` and this changelog now describe the suite as
  "one case per directory under `tests/cases/`" (52 today; the suite header prints the live count),
  and the tracked-items table in README §19.2 records the closure instead of listing the stale rows.
- `README.md` §14.1 and §17.2 now record the **measured positive** panel-activation path - a package
  defined in an ordinary workspace-level session reaches `completed` and the panel appears in the
  settings navigation - next to the measured failure of clicking the approval card that is parked in
  a team-member session (`host-half-failed: session/agent-busy`), with `cordis_stop("<pluginId>")`
  as the rollback for either.

### Security

- **Eight verifiable promises** in [`SECURITY.md`](SECURITY.md), each with the command that
  checks it and the value measured on the reference machine: no new listener (P1), read-only
  by default (P2), no automated write or elevation (P3), no credential access (P4), no
  telemetry (P5), no restart logic (P6), reversible side effects (P7), display-only panel
  (P8).
- **Hash policy**: this repository does **not** bake in vendor installer hashes. A pinned
  hash goes stale with the next upstream release and can either block a legitimate install
  or hide a tampered one; the checker therefore verifies the Authenticode signature and
  offers an optional pin (`pinnedSha256`) that the operator sets from their own download.
  Until a hash is pinned the gate reports `blocked (hash_not_pinned)` - it never guesses.
- **Internal material is not published**: the research notes, review reports and verification
  transcripts stay out of the repository and are listed in section 1 of `.gitignore`; the hygiene gate
  fails if that list is incomplete. (This changelog deliberately does not repeat their names.)

### Residual identifiers

None. The hygiene gate (`.github/scripts/repo-hygiene.ps1`) reports `verdict: CLEAN` - 0 blocking
findings - over the release set (`panel/` and `tools/` included; the gate prints the live file count):
0 blocked identifiers, 0 private /24 prefixes or ULA node suffixes
outside the documented prefix, 0 credential value shapes, 0 unclassified tokens, 0 encoding or binary
violations, 0 *code* references to the removed client-runtime package, 0 missing internal-material
exclusions and 0 missing document markers.

Two documentation lines used to carry a residual absolute application path from the development
machine (`docs/collect.md`, `docs/install/install.md`); a follow-up documentation task (t20,
2026-09-24) replaced them with the `<DSH_APP>` / `<APP_DIR>` placeholders, and the gate run is the
evidence. Everything the gate reports as non-blocking is classified by token (product constants,
RFC 5737 / RFC 3849 documentation ranges, sanitized placeholders) or by kind (credential words
used as field names and "never read" declarations, the removed package named in a ban note) - the
table is in `README.md` section 10.

## [0.1.0] - planned

First public cut of the repository `dsh-crossnet-link` (annotated tag `v0.1.0`). Scope:
everything listed under `[Unreleased]`; the remaining pre-tag checks are the release steps below.

## Version policy, tags and release steps

- **Semantic versioning**: `MAJOR.MINOR.PATCH`. `MAJOR` changes when a verdict meaning, an
  exit code or a JSON field changes incompatibly; `MINOR` adds checks, cases or
  documentation; `PATCH` fixes text, detection logic or docs without changing a contract.
- **Tags**: annotated tags named `vMAJOR.MINOR.PATCH` (for example `v0.1.0`), release
  candidates as `vMAJOR.MINOR.PATCH-rc.N`. Tags are created only by a maintainer.
- **Release steps** (see README.md for the same list with the exact commands):
  1. `LICENSE` is the final MIT text with the maintainer's copyright line (settled - task t24).
  2. `tests/run-tests.ps1` is green on a Windows machine.
  3. `.github/scripts/repo-hygiene.ps1` reports `verdict: CLEAN`.
  4. `python .github/scripts/check-workflows.py --require-pyyaml` is green.
  5. Move the `[Unreleased]` entries under the new version heading with the release date.
  6. Commit, create the annotated tag, push the tag.
  7. Attach no binaries - this repository is text-only by policy.
