"""Cross-language interoperability driver for the VSN Library.

Executes all three writers (Python, C#, TypeScript), verifies that every shared
scenario is written as BYTE-IDENTICAL canonical bytes by each implementation,
then runs every reader against every peer's artifacts and aggregates whether
each implementation recovers an identical canonical interpretation.

This is real byte-level interoperability: independently passing the frozen
vectors is NOT treated as evidence of interoperability.

Usage:
    python run_interop.py            # report; exits 1 on failure
    python run_interop.py --json     # machine-readable report

Artifacts are written to a temporary directory which is always removed.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.dirname(HERE)                       # Libraries/
PYDIR = os.path.join(LIB, "Python")
TS_DIR = os.path.join(LIB, "JavaScript-TypeScript")
CS_INTEROP = os.path.join(LIB, "CSharp", "Interop")
C_DIR = os.path.join(LIB, "C")
C_INTEROP_EXE = os.path.join(C_DIR, "vsn_interop.exe")

SCENARIOS = ["basic", "extents", "enterprise", "multifile"]
PEERS = ["python", "csharp", "typescript", "c"]


def _env() -> dict:
    env = dict(os.environ)
    env["PYTHONPATH"] = PYDIR + os.pathsep + env.get("PYTHONPATH", "")
    return env


def _cwd(lang: str) -> str:
    if lang == "typescript":
        return TS_DIR
    if lang == "c":
        return C_DIR
    return HERE


def _ensure_c_interop() -> None:
    """Build the C interop executable once, if it is not present."""
    if os.path.exists(C_INTEROP_EXE):
        return
    build = os.path.join(C_DIR, "build_debug.bat")
    try:
        subprocess.run(["cmd", "/c", build, "interop"], cwd=C_DIR,
                       capture_output=True, timeout=300)
    except Exception:  # noqa: BLE001 - a missing compiler just fails the writer
        pass


def _ts_cmd(action: str, root: str) -> list[str]:
    """Invoke tsx via node + its local CLI (no npx/.cmd resolution issues)."""
    cli = os.path.join(TS_DIR, "node_modules", "tsx", "dist", "cli.mjs")
    script = os.path.join(TS_DIR, "tests", "interop_cli.ts")
    return ["node", cli, script, action, root]


def _write_cmd(lang: str, root: str) -> list[str]:
    if lang == "python":
        return [sys.executable, "interop_common.py", "write", root]
    if lang == "csharp":
        return ["dotnet", "run", "--project", CS_INTEROP, "--", "write", root]
    if lang == "c":
        return [C_INTEROP_EXE, "write", root]
    return _ts_cmd("write", root)


def _read_cmd(lang: str, root: str) -> list[str]:
    if lang == "python":
        return [sys.executable, "interop_common.py", "read", root]
    if lang == "csharp":
        return ["dotnet", "run", "--project", CS_INTEROP, "--", "read", root]
    if lang == "c":
        return [C_INTEROP_EXE, "read", root]
    return _ts_cmd("read", root)


def _run(args: list[str], cwd: str) -> tuple[int, str]:
    """Run a command; returns (returncode, combined output)."""
    try:
        proc = subprocess.run(
            args, cwd=cwd, capture_output=True, text=True, env=_env(),
            encoding="utf-8", errors="replace", timeout=600,
        )
    except Exception as exc:  # noqa: BLE001 - surface spawn failures as failures
        return 1, f"{type(exc).__name__}: {exc}"
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")

def _json_line(output: str) -> dict | None:
    """Extract the last JSON object emitted on stdout."""
    for line in reversed(output.splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            return json.loads(line)
        except json.JSONDecodeError:
            continue
    return None


def main(argv: list[str]) -> int:
    # A caller-supplied VSN_INTEROP_DIR is honoured so that language test
    # suites can run against the same artifacts; otherwise a fresh temp
    # directory is created and always removed.
    external = os.environ.get("VSN_INTEROP_DIR")
    root = external or tempfile.mkdtemp(prefix="vsn-interop-")
    os.makedirs(root, exist_ok=True)
    failures: list[str] = []
    checks: list[dict] = []
    as_json = "--json" in argv
    try:
        _ensure_c_interop()
        # 1. Writers: every implementation writes every shared scenario.
        for lang in PEERS:
            rc, out = _run(_write_cmd(lang, root), _cwd(lang))
            ok = rc == 0
            checks.append({"kind": "write", "lang": lang, "ok": ok})
            if not ok:
                failures.append(f"{lang} writer failed (rc={rc}): {out[-800:].strip()}")

        # 2. Byte identity: all writers must emit identical canonical bytes.
        for scenario in SCENARIOS:
            blobs: dict[str, bytes] = {}
            for lang in PEERS:
                path = os.path.join(root, lang, scenario + ".vsn")
                if os.path.exists(path):
                    with open(path, "rb") as fh:
                        blobs[lang] = fh.read()
            missing = sorted(set(PEERS) - set(blobs))
            if missing:
                failures.append(f"{scenario}: artifacts missing for {missing}")
                checks.append({"kind": "bytes", "scenario": scenario, "ok": False,
                               "present": sorted(blobs), "byteLength": None})
                continue
            ok = len(set(blobs.values())) == 1
            checks.append({"kind": "bytes", "scenario": scenario, "ok": ok,
                           "present": sorted(blobs),
                           "byteLength": len(next(iter(blobs.values())))})
            if not ok:
                for lang in PEERS:
                    others = [l for l in PEERS if l != lang]
                    diff = [l for l in others if blobs[l] != blobs[lang]]
                    if diff:
                        failures.append(f"{scenario}: {lang} bytes differ from {diff}")


        # 3. Readers: every implementation interprets every peer's artifacts.
        for lang in PEERS:
            rc, out = _run(_read_cmd(lang, root), _cwd(lang))
            report = _json_line(out)
            if rc != 0 or report is None:
                failures.append(f"{lang} reader failed (rc={rc}): {out[-800:].strip()}")
                checks.append({"kind": "read", "lang": lang, "ok": False, "pairs": 0, "failures": {}})
                continue
            results = report.get("results", {})
            bad = {k: v for k, v in results.items() if not v.get("ok")}
            checks.append({"kind": "read", "lang": lang, "ok": not bad,
                           "pairs": len(results), "failures": bad})
            if not results:
                failures.append(f"{lang} reader produced no results")
            for key, val in bad.items():
                failures.append(f"{lang} misinterpreted {key}: {val}")

        doc = {
            "scenarios": SCENARIOS,
            "languages": PEERS,
            "byteIdenticalAllScenarios": all(
                c["ok"] for c in checks if c["kind"] == "bytes") and
                all(c["ok"] for c in checks if c["kind"] == "write"),
            "checks": checks,
            "failures": failures,
            "passed": not failures,
        }
        if as_json:
            print(json.dumps(doc, indent=2))
        else:
            _print_human(doc)
        return 0 if not failures else 1
    finally:
        if not external:
            shutil.rmtree(root, ignore_errors=True)


def _print_human(doc: dict) -> None:
    print("=" * 72)
    print("VSN cross-language interoperability")
    print("=" * 72)
    for c in doc["checks"]:
        if c["kind"] == "write":
            print(f"  [{'OK' if c['ok'] else 'FAIL'}] {c['lang']:12s} wrote all scenarios")
        elif c["kind"] == "bytes":
            mark = "OK  " if c["ok"] else "FAIL"
            print(f"  [{mark}] {c['scenario']:12s} byte-identical across writers "
                  f"(present={','.join(c['present'])}, bytes={c['byteLength']})")
        else:
            mark = "OK  " if c["ok"] else "FAIL"
            print(f"  [{mark}] {c['lang']:12s} read {c.get('pairs', 0)} artifact(s) "
                  f"with identical canonical interpretation")
    print("-" * 72)
    if doc["failures"]:
        print("Failures:")
        for f in doc["failures"]:
            print(f"  - {f}")
        print("RESULT: FAIL")
    else:
        print("RESULT: PASS - all 6 directions verified at byte level")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

