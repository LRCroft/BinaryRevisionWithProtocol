#!/bin/sh
# Shared conformance corpus runner.
#
# Every VSN Library target executes THIS script, so conformance is decided by
# identical inputs and identical pass/fail criteria rather than by each
# language's own idea of what to test. A language supplies only a `probe`
# command: a program that performs the checks named below.
#
# Usage: run_corpus.sh <corpus_dir> <probe_command...>
#
# The probe is invoked as a subcommand, exiting 0 on success:
#
#   <probe> vectors   <file> <expected_bytes> <expected_sha256>
#   <probe> scenario  <file> <interpretation.json>
#   <probe> limit     <contract.json>
#   <probe> malformed <frozen_vector_file>
#   <probe> interop   <corpus_dir>
#
# Exit status: 0 only if EVERY check passed.

set -u

CORPUS="${1:?usage: run_corpus.sh <corpus_dir> <probe_command...>}"
shift
if [ "$#" -eq 0 ]; then
    echo "no probe command supplied" >&2
    exit 2
fi
PROBE="$*"

if [ ! -f "$CORPUS/manifest.json" ]; then
    echo "missing $CORPUS/manifest.json" >&2
    exit 2
fi

# The corpus index is a pre-rendered TSV, so the runner needs no JSON parser and
# no interpreter of its own. Language images do not all ship Python.
INDEX="$CORPUS/index.tsv"
if [ ! -f "$INDEX" ]; then
    echo "missing $INDEX (run build_corpus.py)" >&2
    exit 2
fi

# Results are tallied through a file because a pipeline would otherwise run the
# loop in a subshell and lose its counters.
COUNTS="${TMPDIR:-/tmp}/vsn_counts.$$"
: > "$COUNTS"
TAB=$(printf '\t')

report() {
    # report <ok|fail> <label> <detail>
    if [ "$1" = "ok" ]; then
        printf 'CORPUS PASS %s\n' "$2"
        echo "+1" >> "$COUNTS"
    else
        printf 'CORPUS FAIL %s: %s\n' "$2" "$3"
        echo "-1" >> "$COUNTS"
    fi
}

run() {
    # run <label> <subcommand> <args...>
    label="$1"
    shift
    if detail=$($PROBE "$@" 2>&1); then
        report ok "$label"
    else
        report fail "$label" "$detail"
    fi
}

# 1. Frozen protocol vectors: byte length, sha256, parse, materialize.
#    The index holds vectors first, then a comment line, then scenarios; the
#    vector loop stops at that second comment so scenario rows are not run twice.
while IFS="$TAB" read -r name file bytes sha; do
    case "$name" in
        '# scenarios'*) break ;;
        '#'*|'') continue ;;
    esac
    [ -n "$file" ] || continue
    # Vector files live in the frozen TestVectors directory, a sibling of the
    # corpus directory. The index stores them relative to the corpus parent so
    # the same string resolves whether the runner is invoked with a relative or
    # absolute corpus path.
    vpath="$CORPUS/$file"
    if [ ! -f "$vpath" ]; then
        vpath=$(dirname "$CORPUS")/$file
    fi
    run "vector/$name" vectors "$vpath" "$bytes" "$sha"
done < "$INDEX"

# 2. Canonical scenarios: the probe must independently derive the
# interpretation from the bytes and match the recorded JSON.
for vfile in "$CORPUS"/scenarios/*.vsn; do
    [ -f "$vfile" ] || continue
    sname=$(basename "$vfile" .vsn)
    run "scenario/$sname" scenario "$vfile" "$CORPUS/scenarios/$sname.json"
done

# 3. LimitCleanUp contract.
run limitcleanup limit "$CORPUS/limitcleanup.json"

# 4. Malformed and truncated input, driven from a real frozen vector.
VEC="$CORPUS/../TestVectors/DIRECT-01.vsn"
if [ -f "$VEC" ]; then
    run malformed malformed "$VEC"
fi

# 5. Interoperability against reference-written bytes.
run interop interop "$CORPUS"

pass=$(grep -c '^+1$' "$COUNTS" 2>/dev/null || true)
fail=$(grep -c '^-1$' "$COUNTS" 2>/dev/null || true)
echo "CORPUS SUMMARY pass=$pass fail=$fail"
rm -f "$COUNTS"
[ "$fail" -eq 0 ]
