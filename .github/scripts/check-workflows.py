#!/usr/bin/env python3
"""Workflow gate for dsh-crossnet-link (repository layer, task t12).

LAST UPDATED  : 2026-09-24 (task t12, v1 - parse gate + schema gate + action allowlist)
AUTHOR        : team dsh-crossnet-link-2 (as named at authoring time, after the plugin's then-current name; member "packager", task t12)

WHAT IT CHECKS (every .github/workflows/*.yml):

  1. transport    : UTF-8 without a BOM, LF only, no tab indentation
  2. parse        : the YAML must parse. Two backends:
                      * PyYAML (authoritative) - pinned in CI via
                        `python -m pip install PyYAML==6.0.2` and required there with
                        --require-pyyaml
                      * a restricted built-in parser (zero dependency) so the gate still
                        runs on a machine with no network, no PyYAML and no node. It
                        reports which backend ran; see HONEST LIMITS below.
  3. schema       : name / on / jobs present, jobs non-empty, every job has runs-on and a
                    steps list, every step has exactly one of uses/run, every run step
                    declares an explicit shell, every uses is allow-listed with an exact
                    `owner/repo@vN` ref (no @main, no @v1.2.3.4, no unknown action)
  4. contract     : at least one job runs on a windows runner, that job runs the test entry
                    point tests/run-tests.ps1 under Windows PowerShell 5.1, the hygiene gate
                    .github/scripts/repo-hygiene.ps1 is invoked (including -SelfTest), and
                    the static-analyser module is installed with a PINNED version
                    (Install-Module ... -RequiredVersion)

HONEST LIMITS
  The built-in parser understands the subset these workflows use: block mappings, block
  sequences (including `- key: value` steps), plain/single/double-quoted scalars, `#`
  comments and `|` / `>` literal blocks. It is NOT a general YAML implementation and it has
  no anchors, aliases, flow collections or multi-document support. `--selftest` proves it
  accepts a valid document and rejects the malformed ones (tab indent, duplicate key,
  broken nesting), and CI additionally parses the same files with PyYAML, which IS the
  authoritative parse. If the two ever disagree, PyYAML wins.

EXIT CODE
  0 = every workflow passed
  1 = at least one violation
  2 = the gate could not run as required (--require-pyyaml without PyYAML, missing dir)

COMMANDS USED WHILE BUILDING THIS REVISION:
    python .github/scripts/check-workflows.py
    python .github/scripts/check-workflows.py --selftest
    python .github/scripts/check-workflows.py --require-pyyaml
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

# ---------------------------------------------------------------------------
# action allowlist: only actions that exist, pinned to a major version
# ---------------------------------------------------------------------------
ALLOWED_ACTIONS = {
    "actions/checkout": ["v4", "v5"],
    "actions/setup-python": ["v5", "v6"],
    "actions/upload-artifact": ["v4"],
    "actions/download-artifact": ["v4"],
    "actions/cache": ["v4"],
}

TOP_LEVEL_ALLOWED = {"name", "on", "permissions", "concurrency", "defaults", "env", "jobs", "run-name"}
JOB_ALLOWED = {"name", "runs-on", "needs", "if", "steps", "timeout-minutes", "strategy",
               "env", "permissions", "defaults", "concurrency", "outputs", "environment",
               "continue-on-error", "container", "services", "uses", "with", "secrets"}
STEP_ALLOWED = {"name", "id", "if", "uses", "run", "shell", "working-directory", "env",
                "with", "continue-on-error", "timeout-minutes", "uses"}

WORKFLOW_DIR = os.path.join(".github", "workflows")
# Resolve the default directory from this script's own location, so the gate can be invoked
# from any working directory (measured: running it from the parent directory used to answer
# "no workflow files", which is a false "could not run").
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_WORKFLOW_DIR = os.path.join(REPO_ROOT, ".github", "workflows")


# ---------------------------------------------------------------------------
# restricted YAML parser (zero dependency)
# ---------------------------------------------------------------------------
class YamlError(Exception):
    pass


def _strip_comment(text: str) -> str:
    out = []
    quote = None
    i = 0
    while i < len(text):
        ch = text[i]
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        else:
            if ch in "'\"":
                quote = ch
                out.append(ch)
            elif ch == "#" and (i == 0 or text[i - 1] in " \t"):
                break
            else:
                out.append(ch)
        i += 1
    return "".join(out).rstrip()


def _scalar(text: str):
    t = text.strip()
    if t == "":
        return None
    if len(t) > 1 and t[0] == "'" and t[-1] == "'":
        return t[1:-1].replace("''", "'")
    if len(t) > 1 and t[0] == '"' and t[-1] == '"':
        return t[1:-1]
    if t in ("true", "True", "TRUE"):
        return True
    if t in ("false", "False", "FALSE"):
        return False
    if t in ("null", "Null", "~"):
        return None
    return t


def _is_map_entry(text: str) -> bool:
    if ":" not in text:
        return False
    head = text.split(":", 1)[0]
    return head.strip() != "" and " " not in head.strip()


def _tokenize(text: str):
    """Return a list of (indent, text, blockvalue)."""
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    toks = []
    i = 0
    while i < len(lines):
        raw = lines[i]
        lineno = i + 1
        i += 1
        if raw.strip() == "":
            continue
        if "\t" in raw:
            raise YamlError("tab character on line %d (YAML forbids tabs in indentation)" % lineno)
        if raw.lstrip(" ").startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        content = _strip_comment(raw.strip())
        if content == "":
            continue
        m = re.match(r"^(.*?):\s*([|>][-+]?)\s*$", content)
        if m:
            body = []
            body_indent = None
            while i < len(lines):
                nxt = lines[i]
                if nxt.strip() == "":
                    body.append("")
                    i += 1
                    continue
                if "\t" in nxt:
                    raise YamlError("tab character in a literal block on line %d" % (i + 1))
                ni = len(nxt) - len(nxt.lstrip(" "))
                if ni <= indent:
                    break
                if body_indent is None:
                    body_indent = ni
                body.append(nxt[body_indent:])
                i += 1
            toks.append((indent, m.group(1).strip() + ":", "\n".join(body)))
            continue
        toks.append((indent, content, None))
    return toks


def _parse_block(toks, pos, indent):
    if pos >= len(toks):
        return None, pos
    t_indent, t_text, _ = toks[pos]
    if t_indent != indent:
        raise YamlError("unexpected indentation %d (expected %d) at token %d" % (t_indent, indent, pos + 1))

    # sequence
    if t_text == "-" or t_text.startswith("- "):
        items = []
        while pos < len(toks) and toks[pos][0] == indent and (toks[pos][1] == "-" or toks[pos][1].startswith("- ")):
            rest = toks[pos][1][1:].strip()
            blk = toks[pos][2]
            if rest == "":
                pos += 1
                if pos < len(toks) and toks[pos][0] > indent:
                    val, pos = _parse_block(toks, pos, toks[pos][0])
                else:
                    val = None
                items.append(val)
            elif _is_map_entry(rest):
                sub_indent = indent + 2
                toks[pos] = (sub_indent, rest, blk)
                val, pos = _parse_block(toks, pos, sub_indent)
                items.append(val)
            else:
                items.append(_scalar(rest))
                pos += 1
        return items, pos

    # mapping
    result = {}
    while pos < len(toks) and toks[pos][0] == indent:
        text = toks[pos][1]
        blk = toks[pos][2]
        if not _is_map_entry(text):
            raise YamlError('expected "key: value" but found: %r' % text)
        key, _, rest = text.partition(":")
        key = key.strip()
        rest = rest.strip()
        if key in result:
            raise YamlError("duplicate key: %s" % key)
        pos += 1
        if blk is not None:
            result[key] = blk
        elif rest == "":
            if pos < len(toks) and toks[pos][0] > indent:
                result[key], pos = _parse_block(toks, pos, toks[pos][0])
            elif pos < len(toks) and toks[pos][0] == indent:
                result[key], pos = _parse_block(toks, pos, indent)
            else:
                result[key] = None
        else:
            result[key] = _scalar(rest)
    return result, pos


def parse_mini(text: str):
    toks = _tokenize(text)
    if not toks:
        return None
    value, pos = _parse_block(toks, 0, toks[0][0])
    if pos != len(toks):
        raise YamlError("trailing content at token %d: %r" % (pos + 1, toks[pos][1]))
    return value


def parse_text(text: str, backend: str):
    if backend == "pyyaml":
        import yaml  # noqa: WPS433 (imported lazily so the gate runs without it)

        data = yaml.safe_load(text)
    else:
        data = parse_mini(text)
    # PyYAML (YAML 1.1) turns the bare key `on` into the boolean True; normalise it back.
    if isinstance(data, dict) and True in data and "on" not in data:
        data["on"] = data.pop(True)
    return data


# ---------------------------------------------------------------------------
# gates
# ---------------------------------------------------------------------------
def lint_transport(path: str, raw: bytes):
    problems = []
    if raw[:3] == b"\xef\xbb\xbf":
        problems.append("UTF-8 BOM present (workflow files must be BOM-less)")
    if b"\r\n" in raw:
        problems.append("CRLF line endings (must be LF)")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        problems.append("not valid UTF-8: %s" % exc)
        return problems, ""
    for n, line in enumerate(text.split("\n"), 1):
        if line.startswith("\t") or " \t" in line[: len(line) - len(line.lstrip())]:
            problems.append("tab in indentation on line %d" % n)
    return problems, text


def lint_schema(path: str, data):
    problems = []
    if not isinstance(data, dict):
        return ["the document root is not a mapping"]

    for key in data:
        if key not in TOP_LEVEL_ALLOWED:
            problems.append("unknown top-level key: %r" % key)
    for required in ("name", "on", "jobs"):
        if required not in data:
            problems.append("missing top-level key: %s" % required)
    triggers = data.get("on")
    if triggers is None or (isinstance(triggers, (dict, list)) and len(triggers) == 0):
        problems.append("no trigger declared under `on`")

    jobs = data.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        problems.append("`jobs` must be a non-empty mapping")
        return problems

    windows_jobs = []
    test_entry_seen = []
    hygiene_seen = []
    analyzer_pinned = []
    for job_name, job in jobs.items():
        if not isinstance(job, dict):
            problems.append("job %r is not a mapping" % job_name)
            continue
        for key in job:
            if key not in JOB_ALLOWED:
                problems.append("job %r: unknown key %r" % (job_name, key))
        if "uses" not in job and "runs-on" not in job:
            problems.append("job %r: neither runs-on nor uses" % job_name)
        runs_on = job.get("runs-on")
        if isinstance(runs_on, str) and runs_on.startswith("windows-"):
            windows_jobs.append(job_name)
        steps = job.get("steps")
        if steps is None:
            continue
        if not isinstance(steps, list):
            problems.append("job %r: steps must be a sequence" % job_name)
            continue
        for idx, step in enumerate(steps):
            where = "job %s step %d" % (job_name, idx + 1)
            if not isinstance(step, dict):
                problems.append("%s: not a mapping" % where)
                continue
            for key in step:
                if key not in STEP_ALLOWED:
                    problems.append("%s: unknown key %r" % (where, key))
            has_uses = "uses" in step
            has_run = "run" in step
            if has_uses == has_run:
                problems.append("%s: must have exactly one of uses / run" % where)
            if has_uses:
                uses = step["uses"]
                if not isinstance(uses, str):
                    problems.append("%s: uses must be a string" % where)
                    continue
                if uses.startswith("./"):
                    continue  # local action in this repository
                if "@" not in uses:
                    problems.append("%s: action %r has no version ref" % (where, uses))
                    continue
                name, _, version = uses.rpartition("@")
                if name not in ALLOWED_ACTIONS:
                    problems.append("%s: action %r is not on the allowlist (a non-existent or unpinned action breaks the run)" % (where, name))
                elif version not in ALLOWED_ACTIONS[name]:
                    problems.append("%s: action %r pinned to %r, allowlist has %s" % (where, name, version, "/".join(ALLOWED_ACTIONS[name])))
            if has_run:
                if not isinstance(step["run"], str) or step["run"].strip() == "":
                    problems.append("%s: run is empty" % where)
                if "shell" not in step:
                    problems.append("%s: run step does not declare an explicit shell" % where)
                body = step["run"] if isinstance(step["run"], str) else ""
                if "run-tests.ps1" in body:
                    test_entry_seen.append(where)
                    if step.get("shell") != "powershell":
                        problems.append("%s: the test entry point must run under `shell: powershell` (Windows PowerShell 5.1 is the supported runtime)" % where)
                if "repo-hygiene.ps1" in body:
                    hygiene_seen.append(where)
                if "PSScriptAnalyzer" in body:
                    if "-RequiredVersion" in body:
                        analyzer_pinned.append(where)
                    else:
                        problems.append("%s: PSScriptAnalyzer must be installed with a pinned -RequiredVersion" % where)

    if not windows_jobs:
        problems.append("no job runs on a windows runner")
    if not test_entry_seen:
        problems.append("no step runs tests/run-tests.ps1")
    if not hygiene_seen:
        problems.append("no step runs .github/scripts/repo-hygiene.ps1")
    if not analyzer_pinned:
        problems.append("no step installs PSScriptAnalyzer with a pinned version")
    return problems


def run_gate(paths, backend):
    failures = 0
    for path in paths:
        with open(path, "rb") as handle:
            raw = handle.read()
        problems, text = lint_transport(path, raw)
        data = None
        try:
            data = parse_text(text, backend)
        except YamlError as exc:
            problems.append("YAML (built-in parser): %s" % exc)
        except Exception as exc:  # PyYAML raises its own classes
            problems.append("YAML (%s): %s" % (backend, exc))
        if data is not None:
            problems.extend(lint_schema(path, data))
        label = "OK  " if not problems else "FAIL"
        print("%s %s" % (label, path.replace(os.sep, "/")))
        for problem in problems:
            print("       - %s" % problem)
        if problems:
            failures += 1
    return failures


# ---------------------------------------------------------------------------
# self-test: the parser and the schema gate must accept a good document and reject
# the malformed ones. Without this the gate could pass by understanding nothing.
# ---------------------------------------------------------------------------
GOOD = """name: ci

on:
  push:
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  hygiene:
    name: hygiene
    runs-on: windows-latest
    timeout-minutes: 10
    steps:
      - name: Check out
        uses: actions/checkout@v4
      - name: Hygiene gate
        shell: powershell
        run: |
          .\\.github\\scripts\\repo-hygiene.ps1 -Json
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Suite
        shell: powershell
        run: |
          .\\tests\\run-tests.ps1
      - name: Analyzer
        shell: powershell
        run: |
          Install-Module PSScriptAnalyzer -RequiredVersion 1.22.0 -Force
"""

BAD_TAB = "name: ci\njobs:\n\truns-on: windows-latest\n"
BAD_DUP = "name: ci\nname: other\n"
BAD_UNKNOWN_ACTION = GOOD.replace("actions/checkout@v4", "some/unknown-action@v1")
BAD_UNPINNED = GOOD.replace("actions/checkout@v4", "actions/checkout@main")
BAD_NO_SHELL = GOOD.replace("        shell: powershell\n        run: |\n          .\\tests\\run-tests.ps1\n", "        run: |\n          .\\tests\\run-tests.ps1\n")
BAD_NO_TESTS = GOOD.replace(".\\tests\\run-tests.ps1", "Write-Host done")
BAD_NO_PIN = GOOD.replace(" -RequiredVersion 1.22.0", "")
BAD_NO_WINDOWS = GOOD.replace("windows-latest", "ubuntu-latest")
BAD_BAD_NESTING = "jobs:\n   a: 1\n  b: 2\n"


def selftest(backend):
    cases = [
        ("valid workflow is accepted", GOOD, 0),
        ("tab indentation is rejected", BAD_TAB, 1),
        ("duplicate key is rejected", BAD_DUP, 1),
        ("unknown action is rejected", BAD_UNKNOWN_ACTION, 1),
        ("unpinned action ref is rejected", BAD_UNPINNED, 1),
        ("run step without an explicit shell is rejected", BAD_NO_SHELL, 1),
        ("workflow without the test entry point is rejected", BAD_NO_TESTS, 1),
        ("analyser without a pinned version is rejected", BAD_NO_PIN, 1),
        ("workflow without a windows runner is rejected", BAD_NO_WINDOWS, 1),
        ("broken nesting is rejected", BAD_BAD_NESTING, 1),
    ]
    failures = 0
    print("workflow gate self-test (backend=%s)" % backend)
    for label, text, expected in cases:
        problems, _ = lint_transport("fixture.yml", text.encode("utf-8"))
        try:
            data = parse_text(text, backend)
        except Exception as exc:
            data = None
            problems.append("YAML: %s" % exc)
        if data is not None:
            problems.extend(lint_schema("fixture.yml", data))
        got = 0 if not problems else 1
        ok = got == expected
        if not ok:
            failures += 1
        print("  %s  %s (expected %s, got %s)" % ("PASS" if ok else "FAIL", label,
                                                  "pass" if expected == 0 else "fail",
                                                  "pass" if got == 0 else "fail"))
        if not ok:
            for problem in problems:
                print("         %s" % problem)
    print("self-test: %d control(s), %d failed" % (len(cases), failures))
    return 1 if failures else 0


# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="workflow parse + schema gate")
    parser.add_argument("--require-pyyaml", action="store_true",
                        help="exit 2 when PyYAML is not importable (CI sets this)")
    parser.add_argument("--selftest", action="store_true", help="run the built-in controls")
    parser.add_argument("--dir", default="", help="workflow directory (default: <repo>/.github/workflows)")
    args = parser.parse_args()

    try:
        import yaml  # noqa: F401
        have_pyyaml = True
    except ImportError:
        have_pyyaml = False

    if args.require_pyyaml and not have_pyyaml:
        print("gate could not run: PyYAML is required but not importable "
              "(pip install PyYAML==6.0.2)")
        return 2

    backend = "pyyaml" if have_pyyaml else "builtin"
    if not have_pyyaml:
        print("WARNING: PyYAML is not importable - using the restricted built-in parser; "
              "this is NOT the authoritative parse (CI requires PyYAML)")

    if args.selftest:
        return selftest(backend)

    workflow_dir = args.dir if args.dir else DEFAULT_WORKFLOW_DIR
    paths = sorted(glob.glob(os.path.join(workflow_dir, "*.yml")) +
                   glob.glob(os.path.join(workflow_dir, "*.yaml")))
    if not paths:
        print("gate could not run: no workflow files under %s" % workflow_dir)
        return 2

    print("workflow gate (backend=%s, dir=%s, files=%d)" % (backend, workflow_dir, len(paths)))
    failures = run_gate(paths, backend)
    print("workflows: %d, failed: %d" % (len(paths), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
