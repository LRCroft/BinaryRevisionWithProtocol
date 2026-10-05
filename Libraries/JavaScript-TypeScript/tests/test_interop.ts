// Cross-language interoperability tests (TypeScript side).
//
// TypeScript writes every scenario, then reads the artifacts produced by the
// other implementations and verifies identical canonical interpretation:
// logical content, FileId, RevisionId, ObjectSerial, representation, recovery.
import * as fs from "fs";
import * as path from "path";
import { test, run, eq, skip } from "./harness.js";
import { SCENARIOS, buildScenario, describe, writeAll } from "./interop_common.js";

const DIR = process.env.VSN_INTEROP_DIR
  ?? path.resolve(process.env.TEMP ?? "/tmp", "vsn-interop");
const PEERS = ["python", "csharp"];

test("TypeScript writes all interop scenarios", () => {
  const names = writeAll(DIR, "typescript");
  eq(names.length, SCENARIOS.length, "scenario count");
});

test("TypeScript round-trips its own scenarios", () => {
  for (const s of SCENARIOS) {
    const expected = describe(buildScenario(s));
    const actual = describe(fs.readFileSync(path.join(DIR, "typescript", s + ".vsn")));
    eq(JSON.stringify(actual), JSON.stringify(expected), s);
  }
});

for (const peer of PEERS) {
  for (const s of SCENARIOS) {
    test(`TypeScript reads ${peer} ${s}`, () => {
      const file = path.join(DIR, peer, s + ".vsn");
      if (!fs.existsSync(file)) skip(`${peer} artifact absent`);
      const expected = describe(buildScenario(s));
      const actual = describe(fs.readFileSync(file));
      eq(JSON.stringify(actual), JSON.stringify(expected), `${peer}/${s}`);
      eq(actual.files.length, expected.files.length, "file count");
      for (let i = 0; i < expected.files.length; i++) {
        eq(actual.files[i].fileId, expected.files[i].fileId, "FileId");
        eq(actual.files[i].headRevision, expected.files[i].headRevision, "RevisionId");
        eq(actual.files[i].objectSerial, expected.files[i].objectSerial, "ObjectSerial");
        eq(actual.files[i].repIdentity, expected.files[i].repIdentity, "representation");
        eq(actual.files[i].contentBase64, expected.files[i].contentBase64, "logical content");
      }
      eq(actual.recoveryStatus, "RECOVERED", "recovery");
    });
  }
}

await run();
