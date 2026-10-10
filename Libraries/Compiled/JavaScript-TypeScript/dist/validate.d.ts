export type ValidationLevel = "Structural" | "Semantic" | "Recovery" | "Content" | "Full";
/** Structural: magic, versions, framing, lengths, ordering. */
export declare function validateStructural(data: Buffer): void;
/** Semantic: identity uniqueness, reference resolution, mode constraints. */
export declare function validateSemantic(data: Buffer): void;
/**
 * Content: dependency validation plus dependency cycle detection.
 * Every object must materialize; a cycle is an invalid canonical state.
 *
 * DR-6 additionally requires that when 0x0511 is PRESENT, the materialized
 * output length MUST equal it; a mismatch is invalid canonical state (0x000C,
 * matching frozen vector EXT-12). Absence of 0x0511 stays fully valid (SR-27).
 * Reuses the existing INVALID_CANONICAL_STATE identifier; no new identifier is
 * introduced, and no derived storage is consulted.
 */
export declare function validateContent(data: Buffer): void;
/** Run validation at a requested depth. */
export declare function validate(data: Buffer, level?: ValidationLevel): void;
