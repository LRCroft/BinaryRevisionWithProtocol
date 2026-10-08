import { parse } from "./container.js";
import { REC_COMMIT_MARKER, FID_COMMIT_GENERATION } from "./constants.js";
import { VsnError } from "./errors.js";
/**
 * Locate the effective CommitMarker and return the accepted generation.
 *
 * The effective marker is the highest-Generation structurally complete,
 * semantically valid CommitMarker. A truncated tail is reported TRUNCATED;
 * malformed data is reported MALFORMED. No index, cache, checkpoint, or
 * private database participates (SR-02, SR-03).
 */
export function recover(data) {
    let parsed;
    try {
        parsed = parse(data);
    }
    catch (e) {
        if (e instanceof VsnError && e.code === 0x0002) {
            return { acceptedGeneration: 0, recovered: false, tailPresent: true,
                status: "TRUNCATED", message: "physical end reached mid-unit" };
        }
        if (e instanceof VsnError) {
            return { acceptedGeneration: 0, recovered: false, tailPresent: false,
                status: "MALFORMED", message: e.message };
        }
        throw e;
    }
    const markers = [];
    for (const rec of parsed.records) {
        if (rec.rtype === REC_COMMIT_MARKER) {
            const g = rec.getField(FID_COMMIT_GENERATION);
            if (g)
                markers.push(Number(g.asUvarint()));
        }
    }
    if (markers.length === 0) {
        return { acceptedGeneration: 0, recovered: false, tailPresent: false,
            status: "NO_MARKER", message: "no CommitMarker present" };
    }
    const gen = Math.max(...markers);
    const tail = parsed.trailerGeneration !== BigInt(0)
        ? parsed.trailerGeneration !== BigInt(gen) : false;
    return { acceptedGeneration: gen, recovered: true, tailPresent: tail,
        status: "RECOVERED", message: `accepted generation ${gen}` };
}
//# sourceMappingURL=recovery.js.map