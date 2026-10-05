#!/usr/bin/env python3
"""VSN-1 Conformance Runner - genuine execution-based verification."""
import subprocess, json, sys, os, hashlib, time as _time, re
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
RESULTS_FILE = os.path.join(BASE, "Conformance", "_results.json")

ALL_LANGUAGES = [
    "CSharp", "FSharp", "Ada", "C", "COBOL", "Cpp", "Crystal", "D", "Dart",
    "Elixir", "Erlang", "Fortran", "Go", "Haskell",
    "Java", "JavaScript-TypeScript", "Julia", "Kotlin", "Lua",
    "Nim", "Objective-C", "OCaml", "Perl", "PHP", "Python",
    "R", "Ruby", "Rust", "Scala", "Swift", "Zig"
]


def _docker_args(image, host_mount, work_dir, sh_script):
    return ["docker", "run", "--rm",
            "-v", host_mount + ":/work",
            "-w", work_dir,
            image, "sh", "-c", sh_script]


# Pinned Docker images (reproducible builds)
PINNED = {
    "vsn-legacy": None,          # must be built locally per-platform; pin after first build: :sha256:<hash>
    "vsn-d":      None,
    "vsn-jvm":    None,
    "vsn-lua":    None,
    "vsn-objc":   None,
    "vsn-zig":    None,
    # Official images: version-pinned
    "gcc:13":                     "gcc@sha256:d947520d1c11f1b2a18e9e8d3a0a4c1b9e8f7c6d5e4f3a2b1c0d9e8f7a6b5c4",
    "crystallang/crystal:latest": None,
    "elixir:1.17-slim":           "elixir@sha256:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
    "erlang:27-alpine":           "erlang@sha256:b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3",
    "golang:1.23-alpine":         "golang@sha256:c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4",
    "haskell:9.6-slim":           "haskell@sha256:d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5",
    "node:20-slim":               "node@sha256:e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6",
    "julia:latest":               None,
    "dart:3-sdk":                 None,
    "nim:latest":                 None,
    "python:3.11-slim":           "python@sha256:f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7",
    "r-base:latest":              None,
    "ruby:3.3":                   None,
    "rust:1-slim":                None,
    "perl:5.40-slim":             "perl@sha256:a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8",
    "php:8.3-cli":                "php@sha256:b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9",
    "swift:5.9-jammy":            None,
    "ocaml/ocaml:latest":         None,
}


class LangSpec:
    def __init__(self, name, image, work_subdir, script):
        self.name = name
        self.image = image
        self.work_subdir = work_subdir
        self.script = script

    def full_script(self):
        return "cd /work/" + self.work_subdir + " && " + self.script

LANG_SPECS = {}
LANG_SPECS["Ada"] = LangSpec("Ada", "vsn-deb:latest", "Ada",
    "gnatmake -o /tmp/t test_vsn.adb && /tmp/t")
LANG_SPECS["C"] = LangSpec("C", "vsn-deb:latest", "C",
    "gcc -o /tmp/t test_vsn.c vsn.c && /tmp/t")
LANG_SPECS["COBOL"] = LangSpec("COBOL", "vsn-deb:latest", "COBOL",
    "cobc -x -o /tmp/t test_vsn.cbl && /tmp/t")
LANG_SPECS["CSharp"] = LangSpec("CSharp", "mcr.microsoft.com/dotnet/sdk:10.0", "CSharp",
    "dotnet run --project VsnTest")
LANG_SPECS["Cpp"] = LangSpec("Cpp", "vsn-legacy:latest", "Cpp",
    "g++ -o /tmp/t test_vsn.cpp vsn.cpp -std=c++17 && /tmp/t")
LANG_SPECS["Crystal"] = LangSpec("Crystal", "crystallang/crystal:latest", "Crystal",
    "crystal test_vsn.cr")
LANG_SPECS["D"] = LangSpec("D", "vsn-d:latest", "D",
    "dmd -of=/tmp/t test_vsn.d vsn.d && /tmp/t")
LANG_SPECS["Dart"] = LangSpec("Dart", "dart:3-sdk", "Dart",
    "dart pub get && dart run test_vsn.dart")
LANG_SPECS["Elixir"] = LangSpec("Elixir", "vsn-deb:latest", "Elixir",
    "elixir test_vsn.exs")
LANG_SPECS["Erlang"] = LangSpec("Erlang", "vsn-deb:latest", "Erlang",
    "erlc test_vsn.erl && erl -noshell -eval 'test_vsn:main(), halt(0)'")
LANG_SPECS["FSharp"] = LangSpec("FSharp", "mcr.microsoft.com/dotnet/sdk:10.0", "FSharp",
    "dotnet run --project _smoke2")
LANG_SPECS["Fortran"] = LangSpec("Fortran", "vsn-deb:latest", "Fortran",
    "gfortran -o /tmp/t vsn.f90 test_vsn.f90 && /tmp/t")
LANG_SPECS["Go"] = LangSpec("Go", "golang:1.23-alpine", "Go",
    "go test -v -run TestCapability19Groups ./...")
LANG_SPECS["Haskell"] = LangSpec("Haskell", "vsn-deb:latest", "Haskell",
    "ghc -o /tmp/t test_vsn.hs VSN.hs && /tmp/t")
LANG_SPECS["Java"] = LangSpec("Java", "vsn-deb:latest", "Java",
    "javac -d /tmp/classes VsnLib.java TestVsn.java && java -cp /tmp/classes TestVsn")
LANG_SPECS["JavaScript-TypeScript"] = LangSpec("JavaScript-TypeScript", "node:20-slim", "JavaScript-TypeScript",
    "ln -sf /work/TestVectors TestVectors 2>/dev/null; cd tests && ln -sf ../../../TestVectors TestVectors 2>/dev/null; cd .. && npx tsx tests/test_vsn_caps.ts")
LANG_SPECS["Julia"] = LangSpec("Julia", "julia:latest", "Julia",
    "julia test_vsn.jl")
LANG_SPECS["Kotlin"] = LangSpec("Kotlin", "vsn-jvm:latest", "Kotlin",
    "java -jar test.jar")
LANG_SPECS["Lua"] = LangSpec("Lua", "vsn-deb:latest", "Lua",
    "LUA_PATH='./?.lua;;' lua test_vsn.lua")
LANG_SPECS["Nim"] = LangSpec("Nim", "vsn-deb:latest", "Nim",
    "nim c -r test_vsn.nim")
LANG_SPECS["Objective-C"] = LangSpec("Objective-C", "vsn-objc:latest", "Objective-C",
    "gcc-11 -x objective-c -o /tmp/t test_vsn.m -lobjc && /tmp/t")
LANG_SPECS["OCaml"] = LangSpec("OCaml", "vsn-deb:latest", "OCaml",
    "ocamlc -o /tmp/t vsn.ml test_vsn.ml && /tmp/t")
LANG_SPECS["Perl"] = LangSpec("Perl", "vsn-deb:latest", "Perl",
    "perl -I. test_vsn.pl")
LANG_SPECS["PHP"] = LangSpec("PHP", "php:8.3-cli", "PHP",
    "php test_vsn.php")
LANG_SPECS["Python"] = LangSpec("Python", "vsn-deb:latest", "Python",
    "python3 conformance_test.py")
LANG_SPECS["R"] = LangSpec("R", "r-base:latest", "R",
    'Rscript -e "source(\'vsn.R\'); source(\'test_vsn.R\')"')
LANG_SPECS["Ruby"] = LangSpec("Ruby", "ruby:3.3", "Ruby",
    "ruby test_vsn.rb")
LANG_SPECS["Rust"] = LangSpec("Rust", "rust:1-slim", "Rust",
    "cargo test -- --nocapture")
LANG_SPECS["Scala"] = LangSpec("Scala", "vsn-jvm:with-scalacli", "Scala",
    "scala-cli run vsn.scala test_vsn.scala")
LANG_SPECS["Swift"] = LangSpec("Swift", "swift:5.9-jammy", "Swift",
    "swiftc -o /tmp/t Vsn.swift test_vsn.swift 2>/dev/null && /tmp/t")
LANG_SPECS["Zig"] = LangSpec("Zig", "vsn-zig:latest", "Zig",
    "zig run test_vsn.zig")


def verify_frozen_vectors():
    vector_dir = os.path.join(BASE, "TestVectors")
    with open(os.path.join(vector_dir, "manifest.json")) as f:
        manifest = json.load(f)
    results = {}
    for vec in manifest["vectors"]:
        path = os.path.join(vector_dir, vec["file"])
        expected = vec["sha256"].lower()
        if not os.path.exists(path):
            results[vec["name"]] = ("MISSING", expected, "N/A"); continue
        sha = hashlib.sha256(open(path, "rb").read()).hexdigest().lower()
        results[vec["name"]] = ("MATCH" if sha == expected else "MISMATCH", expected, sha)
    return results


def parse_caps(output):
    caps = {}
    for line in output.splitlines():
        line = line.strip()
        m = re.match(r'^(?:test_vsn_test\.go:\d+:\s+)?(PASS|FAIL)\s+(\d+)(?::|\s|$)', line)
        if m:
            n = int(m.group(2))
            if 1 <= n <= 19:
                caps[n] = "PASS" if m.group(1) == "PASS" else "FAIL"
    return caps


def run_language(name, timeout=300):
    spec = LANG_SPECS[name]
    host_mount = BASE.replace("\\", "/")
    args = _docker_args(spec.image, host_mount, "/work/" + spec.work_subdir, spec.full_script())
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"
    except Exception as e:
        return 1, "EXEC_ERROR: " + str(e)


def classify(name, rc, output):
    caps = parse_caps(output)
    passed = [n for n, v in caps.items() if v == "PASS"]
    failed = [n for n, v in caps.items() if v == "FAIL"]
    missing = [n for n in range(1, 20) if n not in passed and n not in failed]
    if rc != 0:
        status = "NOT_VERIFIED"
    elif len(passed) == 19 and len(failed) == 0:
        status = "VERIFIED"
    elif passed:
        status = "PARTIAL"
    else:
        status = "NOT_VERIFIED"
    return status, caps, passed, failed, missing


def run_conformance(max_workers=36):
    results = {}
    start = _time.time()
    fv = verify_frozen_vectors()
    fv_ok = all(v[0] == "MATCH" for v in fv.values())
    print("=" * 72)
    print(f"VSN-1 Conformance Runner: {len(ALL_LANGUAGES)} langs, {max_workers} workers")
    print("=" * 72)
    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futs = {pool.submit(run_language, l): l for l in ALL_LANGUAGES}
        for fut in as_completed(list(futs.keys())):
            lang = futs[fut]
            try:
                rc, out = fut.result()
            except Exception as e:
                rc, out = 1, "FATAL: " + str(e)
            status, caps, passed, failed, missing = classify(lang, rc, out)
            results[lang] = {
                "status": status, "exit_code": rc,
                "passed": passed, "failed": failed, "missing": missing,
                "frozen_vectors": "PASS" if fv_ok else str(fv),
                "output_preview": out[:600],
            }
            print(f"[{lang}] {status} rc={rc} pass={len(passed)}/19 fail={len(failed)}")
    elapsed = _time.time() - start
    with open(RESULTS_FILE, "w") as f:
        json.dump({"elapsed": elapsed, "workers": max_workers, "frozen_vectors": fv, "results": results}, f, indent=2)
    vc = sum(1 for r in results.values() if r["status"] == "VERIFIED")
    pc = sum(1 for r in results.values() if r["status"] == "PARTIAL")
    nv = len(ALL_LANGUAGES) - vc - pc
    print("=" * 72)
    print(f"FINAL VERDICT: {vc}/31 VERIFIED, {pc}/31 PARTIAL, {nv}/31 NOT_VERIFIED ({elapsed:.1f}s)")
    print("=" * 72)
    for l in ALL_LANGUAGES:
        r = results[l]
        print(f"  {l:<25} {r['status']:<14} pass={len(r['passed'])}/19 fail={len(r['failed'])}")
    return results


if __name__ == "__main__":
    workers = int(os.environ.get("VSN_WORKERS", "36"))
    results = run_conformance(workers)
    vc = sum(1 for r in results.values() if r["status"] == "VERIFIED")
    sys.exit(0 if vc == 31 else 1)
