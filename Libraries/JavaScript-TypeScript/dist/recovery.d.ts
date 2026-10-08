/** Outcome of marker-based recovery (RC-01..RC-45). */
export interface RecoveryResult {
    acceptedGeneration: number;
    recovered: boolean;
    tailPresent: boolean;
    status: string;
    message: string;
}
/**
 * Locate the effective CommitMarker and return the accepted generation.
 *
 * The effective marker is the highest-Generation structurally complete,
 * semantically valid CommitMarker. A truncated tail is reported TRUNCATED;
 * malformed data is reported MALFORMED. No index, cache, checkpoint, or
 * private database participates (SR-02, SR-03).
 */
export declare function recover(data: Buffer): RecoveryResult;
