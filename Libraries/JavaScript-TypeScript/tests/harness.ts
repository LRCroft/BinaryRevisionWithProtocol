// Minimal sequential test harness shared by the TypeScript test suites.

type Case = { name: string; fn: () => void | Promise<void> };

const cases: Case[] = [];

/** Marker error used to report a skipped case. */
export class Skip extends Error {}

/** Skip the current case with a reason (counted separately, not as a pass). */
export function skip(reason: string): never { throw new Skip(reason); }

/** Register a test case. */
export function test(name: string, fn: () => void | Promise<void>): void {
  cases.push({ name, fn });
}

/** Run all registered cases in order; exit non-zero if any fail. */
export async function run(): Promise<void> {
  let passed = 0;
  let skipped = 0;
  const failed: string[] = [];
  for (const c of cases) {
    try {
      await c.fn();
      passed++;
      console.log(`✓ ${c.name}`);
    } catch (e) {
      if (e instanceof Skip) {
        skipped++;
        console.log(`- ${c.name} (skipped: ${e.message})`);
        continue;
      }
      failed.push(c.name);
      console.log(`✗ ${c.name}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  console.log(`\n${passed} passed, ${failed.length} failed, ${skipped} skipped`);
  if (failed.length > 0) process.exit(1);
}

/** Assert that `fn` throws. Returns the thrown value. */
export function expectThrow(fn: () => unknown, what = "expected throw"): unknown {
  try {
    fn();
  } catch (e) {
    return e;
  }
  throw new Error(what);
}

/** Assert equality (strict, with a message). */
export function eq<T>(actual: T, expected: T, what = "value"): void {
  if (actual !== expected) throw new Error(`${what}: expected ${expected}, got ${actual}`);
}

/** Assert a Buffer equals expected bytes. */
export function eqBytes(actual: Buffer, expected: Buffer, what = "bytes"): void {
  if (!Buffer.from(actual).equals(Buffer.from(expected)))
    throw new Error(`${what}: byte mismatch (got ${actual.toString("hex")})`);
}
