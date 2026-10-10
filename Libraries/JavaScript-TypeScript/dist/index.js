"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.MODE_ENTERPRISE = exports.MODE_MODERN = exports.StoragePolicy = exports.diagnostics = exports.recovery = exports.validate_module = exports.representations = exports.container = exports.storage = exports.io_ops = exports.merge = exports.diff = void 0;
exports.create = create;
exports.validateContainer = validateContainer;
exports.recoverContainer = recoverContainer;
exports.importFile = importFile;
exports.exportFile = exportFile;
exports.transaction = transaction;
exports.inspectContainer = inspectContainer;
__exportStar(require("./constants.js"), exports);
__exportStar(require("./errors.js"), exports);
__exportStar(require("./primitives.js"), exports);
__exportStar(require("./container.js"), exports);
__exportStar(require("./representations.js"), exports);
__exportStar(require("./api.js"), exports);
__exportStar(require("./writer.js"), exports);
__exportStar(require("./builder.js"), exports);
__exportStar(require("./recovery.js"), exports);
__exportStar(require("./validate.js"), exports);
__exportStar(require("./diagnostics.js"), exports);
__exportStar(require("./transactions.js"), exports);
__exportStar(require("./store.js"), exports);
__exportStar(require("./io_ops.js"), exports);
__exportStar(require("./diff.js"), exports);
__exportStar(require("./merge.js"), exports);
__exportStar(require("./storage.js"), exports);
__exportStar(require("./integrity.js"), exports);
// Namespace re-exports mirror the Python module namespaces (vsn.diff, etc.).
exports.diff = __importStar(require("./diff.js"));
exports.merge = __importStar(require("./merge.js"));
exports.io_ops = __importStar(require("./io_ops.js"));
exports.storage = __importStar(require("./storage.js"));
exports.container = __importStar(require("./container.js"));
exports.representations = __importStar(require("./representations.js"));
exports.validate_module = __importStar(require("./validate.js"));
exports.recovery = __importStar(require("./recovery.js"));
exports.diagnostics = __importStar(require("./diagnostics.js"));
const store_js_1 = require("./store.js");
const diagnostics_js_1 = require("./diagnostics.js");
const recovery_js_1 = require("./recovery.js");
const io_ops_js_1 = require("./io_ops.js");
const transactions_js_1 = require("./transactions.js");
/** Create a new VSN container store. */
function create(mode = 1) { return store_js_1.VsnStore.create(mode); }
/** Validate a container, returning diagnostics rather than throwing. */
function validateContainer(data, level = "Full") {
    return (0, diagnostics_js_1.validateWithDiagnostics)(data, level);
}
/** Recover a container from potentially corrupted data. */
function recoverContainer(data) { return (0, recovery_js_1.recover)(data); }
/** Import a file into a store; returns the FileId. */
function importFile(store, path, content) {
    return (0, io_ops_js_1.importBytes)(store, path, content);
}
/** Export a file from a store; returns content bytes. */
function exportFile(store, fileId) {
    return (0, io_ops_js_1.exportBytes)(store, fileId);
}
/** Create a new transaction. */
function transaction(expectedRevisionId = null) {
    return new transactions_js_1.Transaction(expectedRevisionId);
}
/** Inspect a store and return container metadata. */
function inspectContainer(store) {
    return store.inspect();
}
// Re-export StoragePolicy enum for conformance tests
var constants_js_1 = require("./constants.js");
Object.defineProperty(exports, "StoragePolicy", { enumerable: true, get: function () { return constants_js_1.StoragePolicy; } });
Object.defineProperty(exports, "MODE_MODERN", { enumerable: true, get: function () { return constants_js_1.MODE_MODERN; } });
Object.defineProperty(exports, "MODE_ENTERPRISE", { enumerable: true, get: function () { return constants_js_1.MODE_ENTERPRISE; } });
//# sourceMappingURL=index.js.map