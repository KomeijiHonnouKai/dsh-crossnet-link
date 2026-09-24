# Contributing

LAST UPDATED  : 2026-09-24 (task t24 - repository name stated once, so it can be replaced in a
                single edit; t12 wrote the first version)
COMMANDS USED : powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
                powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -SelfTest
                python .github/scripts/check-workflows.py --selftest

Thanks for helping with `dsh-crossnet-link`. This project is a **read-only posture
detector** for a cross-network remote-access link (Tailscale + `tailscale serve` in front of a
loopback-only DSH port). The rules below are part of the design, not style preferences: a change
that breaks one gets asked to change before it is merged.

## 1. Hard rules

1. **Read-only by default.** A new probe must not change system state. The only writes a
   script may perform are opt-in report files the caller names explicitly
   (`-OutFile`, `-DumpFixture`); without them the run writes zero bytes.
2. **No new listener, route, firewall rule or `tailscale serve` publish.** The plugin reports
   posture; it never widens it. `-Apply` stays refused.
3. **No credential access.** Never read, print, store or transmit the DSH credential store,
   the bridge token file, a browser cookie database or a session log. A probe command string
   that merely mentions such a store fails the collector's own `CREDENTIAL_DISCIPLINE` check.
4. **No elevation and no install execution.** Missing prerequisites produce a command a human
   prints and runs; there is no `runas`, `Start-Process`, `msiexec`, scheduled task or
   execution-policy change anywhere in the code.
5. **Fail closed.** `unknown` never counts as a pass; if a probe cannot be read the verdict is
   `unknown` with the raw output attached. Never guess from localized text when a structured
   source exists, and never turn "no rows parsed" into "nothing to report".
6. **Reversible side effects only.** Plugin registrations live inside a single `ctx.effect`
   whose disposer removes them (and terminates any child process).
7. **Zero hardcoding.** No user name, host name, drive letter, tailnet name, peer address,
   port or DSH path baked into code. Resolve as `param > environment > auto-discovery >
   documented built-in default` and report which source supplied each value.
8. **Windows PowerShell 5.1 is the target.** No PowerShell 7 requirement, no third-party
   module, no node, no network access in code paths that judge posture. Scripts are pure
   ASCII (`i18n/*.json` holds every non-ASCII string).
9. **No *code* reference to the removed client-runtime package** (the `dsh-client-runtime`
   name under the `@deepseek-ai/` scope). It is gone from the 0.1.5 line and a client entry
   that requires it breaks the whole GUI, so it must not appear in `src/`, `panel/`, `i18n/`,
   `.github/` or the test sources. A prose mention that explains the ban and shows the check
   command is legitimate and expected - the gate therefore fails on code references only and
   reports documentation mentions as `DOCUMENTED`.
10. **Text only.** No binaries, no archives, no build output in the repository.

## 2. Run these before you open a pull request

```powershell
# the offline suite (one case per directory under tests/cases/; 52 today, the suite header
# prints the live count; no Pester, no module, no network)
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1

# the release-set hygiene gate (identifiers, credentials, encodings, binaries, markers)
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1

# prove the gate itself still catches things (positive and negative controls)
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -SelfTest

# workflow parse + schema gate (PyYAML is the authoritative parser; CI installs it)
python .github/scripts/check-workflows.py --selftest
python .github/scripts/check-workflows.py
```

Static analysis runs in CI with a pinned PSScriptAnalyzer. To run the same check locally:

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.22.0 -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error      # must be empty
```

## 3. Encoding rules (enforced by `.editorconfig` and the hygiene gate)

| File kind | Encoding | BOM | Line endings |
|---|---|---|---|
| `*.md` (docs) | UTF-8 | **no** | LF |
| `*.ps1` that is ASCII-only (all scripts today) | UTF-8 / ASCII | **no** | LF |
| `*.ps1` that must contain non-ASCII text (Chinese comments or messages) | UTF-8 | **yes** | LF |
| `*.json`, `*.js`, `*.yml`, `.gitignore`, `.editorconfig`, `LICENSE` | UTF-8 | no | LF |
| `tests/fixtures/*.json` (captured console output) | UTF-8 | no | CRLF, as emitted by the tool - the only documented exception |

Why the two-branch PowerShell rule: Windows PowerShell 5.1 decodes a BOM-less script using
the system ANSI code page, where a UTF-8 sequence can swallow the following quote byte and
produce a wall of fake syntax errors. The current scripts avoid the question entirely by
being pure ASCII - keep them that way unless a localized string is unavoidable.

## 4. Sanitization rules for code, docs, fixtures, issues and pull requests

This repository is published, and it was developed on real machines. Before you commit:

- Replace every real value with a placeholder: `<PEER_IP>`, `<HOST>`, `<TAILNET_DOMAIN>`,
  `<DSH_HOME>`, `<DSH_APP>`, `<TOKEN>`, `<MSI_PATH>`, `<USER>`.
- Allowed and expected in published files: **product constants** (loopback and unspecified
  addresses, the CGNAT range, the documented ULA prefix and its `/48` form, netmasks), the
  **RFC 5737 documentation ranges**, the **RFC 3849 prefix**, and the **sanitized placeholder
  addresses and private ranges this project already uses**. There is exactly one shared allow
  list - with the value and the reason for each entry - at the top of
  `.github/scripts/repo-hygiene.ps1` (section "Allow list"); that table is the source of
  truth, the gate prints every token it classifies as `ALLOWED`, and a token that matches no
  entry is reported as `UNCLASSIFIED` and fails. Add a new placeholder to that table instead
  of inventing one ad hoc.
- The five credential words (`token`, `secret`, `password`, `cookie`, `apikey`) may appear
  as a field name, as part of the declaration of what is deliberately *not* read, or as test
  fixture vocabulary. They must never appear as an assigned value. The gate fails on value
  shapes (`tskey-…`, a JWT, or `key = <12+ characters>`), not on the bare word.
- The blocked-identifier list lives in `.github/scripts/repo-hygiene.ps1` section 0, and it
  is assembled from fragments on purpose: if the gate quoted an identifier literally, the
  gate itself would be the only hit in the release set. Refer to that section instead of
  copying the list into other files.

## 5. Adding a check or a test case

- A new posture check belongs in `src/collect.ps1` and needs: a stable reason key, an
  `evidence{command,exitCode,source,confidence}`, a verdict rule that fails closed, and a
  line in `docs/collect.md`.
- A new test case is one directory under `tests/cases/<case-id>/case.json`; see
  `tests/cases/README.md` for the schema, the six graders and the xfail convention. Cases
  are ordered by id and use `base` + `layer` + `unset` so they only record differences.
- New fixtures must follow section 4.

## 6. Commits, pull requests and review

- One logical change per commit; message style: `area: imperative summary` (for example
  `collector: fail closed when the netstat state word is localized`).
- The pull request description states what changed, how it was verified, and pastes the raw
  output of the commands from section 2. If CI cannot run (for example a fork without
  Actions), say which command you ran locally and on which OS/PowerShell version.
- Reviews look for the hard rules of section 1 first, then for evidence: a claim without a
  command and its output is treated as unverified.
- Never force-push a shared branch; never move or delete a release tag.

## 7. Reporting a security problem

Do not open a public issue for a vulnerability. See [`SECURITY.md`](SECURITY.md) for the
disclosure channel and for the behaviour that is *by design* and therefore not a
vulnerability (for example `unknown` verdicts on a machine without the peer, or non-zero exit
codes on a client-only machine when `-Role both` is used).
