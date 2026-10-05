// Interop CLI used by the cross-language driver.
//
//   npx tsx tests/interop_cli.ts write <dir>
//   npx tsx tests/interop_cli.ts read  <dir>
//
// `read` prints a JSON report describing every peer artifact it can interpret.
import * as fs from "fs";
import * as path from "path";
import { SCENARIOS, buildScenario, describe, writeAll } from "./interop_common.js";

const [cmd, dir] = process.argv.slice(2);
if (!cmd || !dir) {
  console.error("usage: interop_cli.ts <write|read> <dir>");
  process.exit(2);
}

if (cmd === "write") {
  const names = writeAll(dir, "typescript");
  console.log(JSON.stringify({ lang: "typescript", wrote: names }));
} else {
  const report: Record<string, unknown> = {};
  for (const peer of ["python", "csharp", "typescript"]) {
    for (const s of SCENARIOS) {
      const file = path.join(dir, peer, s + ".vsn");
      if (!fs.existsSync(file)) continue;
      try {
        const expected = describe(buildScenario(s));
        const actual = describe(fs.readFileSync(file));
        const ok = JSON.stringify(actual) === JSON.stringify(expected);
        report[`${peer}/${s}`] = { ok, status: actual.recoveryStatus };
      } catch (e) {
        report[`${peer}/${s}`] = { ok: false, error: e instanceof Error ? e.message : String(e) };
      }
    }
  }
  console.log(JSON.stringify({ lang: "typescript", results: report }));
}
