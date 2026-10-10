"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Category = exports.Severity = void 0;
exports.fromVsnError = fromVsnError;
exports.validationLevels = validationLevels;
exports.validateWithDiagnostics = validateWithDiagnostics;
const errors_js_1 = require("./errors.js");
const validate_js_1 = require("./validate.js");
const recovery_js_1 = require("./recovery.js");
/** Diagnostic severity (library vocabulary, not a protocol identifier). */
exports.Severity = {
    ERROR: "error", WARNING: "warning", INFO: "info",
};
/** Diagnostic category: frozen protocol error vs library-only vs derived data. */
exports.Category = {
    PROTOCOL: "protocol", LIBRARY: "library", DERIVED: "derived",
};
/** Build a PROTOCOL-category diagnostic from a frozen VSN error. */
function fromVsnError(e, operation) {
    return {
        code: e.code, name: e.name, severity: exports.Severity.ERROR,
        category: exports.Category.PROTOCOL, message: e.message,
        byteOffset: e.byteOffset, operation, cause: e,
    };
}
/** Validation levels implied by a requested level, matching Python. */
function validationLevels(level) {
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
function validateWithDiagnostics(data, level = "Full") {
    const diags = [];
    for (const lvl of validationLevels(level)) {
        try {
            if (lvl === "Structural")
                (0, validate_js_1.validateStructural)(data);
            else if (lvl === "Semantic")
                (0, validate_js_1.validateSemantic)(data);
            else if (lvl === "Recovery")
                (0, recovery_js_1.recover)(data);
            else if (lvl === "Content")
                (0, validate_js_1.validateContent)(data);
        }
        catch (e) {
            if (e instanceof errors_js_1.VsnError)
                diags.push(fromVsnError(e, lvl));
            else
                diags.push({
                    code: -1, name: "LIBRARY_ERROR", severity: exports.Severity.ERROR,
                    category: exports.Category.LIBRARY, message: String(e), operation: lvl, cause: e,
                });
            break;
        }
    }
    return diags;
}
//# sourceMappingURL=diagnostics.js.map