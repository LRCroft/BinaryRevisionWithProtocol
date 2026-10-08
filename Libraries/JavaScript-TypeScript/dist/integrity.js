import { createHash } from "crypto";
import { validate } from "./validate.js";
/** Hash the canonical bytes (verification only, never identity). */
export function canonicalHash(data) {
    return createHash("sha256").update(data).digest("hex");
}
/**
 * Verify a store: structural/semantic/recovery/content validation plus a
 * consistency check that every accepted file materializes without error.
 */
export function verifyIntegrity(store) {
    const errors = [];
    // Verify the committed canonical state when one exists.
    const canonical = store.canonicalData;
    const data = canonical.length > 0 ? canonical : store.toBytes();
    try {
        validate(data, "Full");
    }
    catch (e) {
        errors.push(e instanceof Error ? e.message : String(e));
    }
    for (const info of store.listFiles()) {
        if (!store.fileExists(info.fileId))
            continue;
        try {
            store.readFile(info.fileId);
        }
        catch (e) {
            errors.push(`${info.path}: ${e instanceof Error ? e.message : String(e)}`);
        }
    }
    const meta = store.inspect();
    return {
        valid: errors.length === 0, mode: meta.mode, generation: meta.generation,
        fileCount: meta.fileCount, objectCount: meta.objectCount,
        revisionCount: meta.revisionCount, contentHash: canonicalHash(data), errors,
    };
}
//# sourceMappingURL=integrity.js.map