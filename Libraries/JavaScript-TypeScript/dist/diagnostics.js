import { VsnError } from "./errors.js";
import { validateStructural, validateSemantic, validateContent } from "./validate.js";
import { recover } from "./recovery.js";
/** Diagnostic severity (library vocabulary, not a protocol identifier). */
export const Severity = {
    ERROR: "error", WARNING: "warning", INFO: "info",
};
/** Diagnostic category: frozen protocol error vs library-only vs derived data. */
export const Category = {
    PROTOCOL: "protocol", LIBRARY: "library", DERIVED: "derived",
};
/** Build a PROTOCOL-category diagnostic from a frozen VSN error. */
export function fromVsnError(e, operation) {
    return {
        code: e.code, name: e.name, severity: Severity.ERROR,
        category: Category.PROTOCOL, message: e.message,
        byteOffset: e.byteOffset, operation, cause: e,
    };
}
/** Validation levels implied by a requested level, matching Python. */
export function validationLevels(level) {
    if (level === "Structural")
        return ["Structural"];
    if (level === "Semantic")
        return ["Structural", "Semantic"];
    if (level === "Recovery")
        return ["Structural", "Semantic", "Recovery"];
    if (level === "Content")
        return ["Structural", "Semantic", "Content"];
    if (level === "Full")
        return ["Structural", "Semantic", "Recovery", "Content"];
    throw new Error(`unknown validation level ${level}`);
}
/** Run validation and return diagnostics instead of throwing. */
export function validateWithDiagnostics(data, level = "Full") {
    const diags = [];
    for (const lvl of validationLevels(level)) {
        try {
            if (lvl === "Structural")
                validateStructural(data);
            else if (lvl === "Semantic")
                validateSemantic(data);
            else if (lvl === "Recovery")
                recover(data);
            else if (lvl === "Content")
                validateContent(data);
        }
        catch (e) {
            if (e instanceof VsnError)
                diags.push(fromVsnError(e, lvl));
            else
                diags.push({
                    code: -1, name: "LIBRARY_ERROR", severity: Severity.ERROR,
                    category: Category.LIBRARY, message: String(e), operation: lvl, cause: e,
                });
            break;
        }
    }
    return diags;
}
//# sourceMappingURL=diagnostics.js.map