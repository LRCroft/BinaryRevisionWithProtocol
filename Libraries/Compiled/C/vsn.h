#ifndef VSN_H
#define VSN_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif

/* VSN-1 error codes */
#define VSN_ERR_OK               0
#define VSN_ERR_BAD_MAGIC       0x0001
#define VSN_ERR_MALFORMED       0x0002
#define VSN_ERR_BAD_CFV         0x0003
#define VSN_ERR_BAD_EV          0x0004
#define VSN_ERR_MISSING_OBJECT  0x0008
#define VSN_ERR_MISSING_REF     0x0009
#define VSN_ERR_FIELD_ORDER     0x0011
#define VSN_ERR_INVALID_STATE   0x000C
#define VSN_ERR_TRUNCATED       0x0020
#define VSN_ERR_PRIM            0x0030
#define VSN_ERR_CAP             0x0040

/* Record types (GR-28) */
#define REC_END         0x0000
#define REC_FILE_ID     0x0001
#define REC_REVISION    0x0002
#define REC_FILE_HEAD   0x0004
#define REC_OBJ         0x0005
#define REC_COMMIT      0x0006
#define REC_MODE        0x0007             /* OBSOLETE: ModeDeclaration (deprecated, kept for reader compat) */
#define REC_STORAGE_POLICY 0x0009          /* New: authoritative storage classification */
#define REC_REP_DESC    0x0008             /* RepresentationDescriptor (defined after SP for numeric order) */

/* Field IDs */
#define FID_RECORDS_END 0x0000
#define FID_FILE_ID     0x0101
#define FID_REV_ID      0x0201
#define FID_REV_FILE_ID 0x0202
#define FID_REV_SERIAL  0x0203
#define FID_REV_PATH    0x0210
#define FID_REV_PRESENCE 0x0211
#define FID_HEAD_FILE   0x0401
#define FID_HEAD_REV    0x0402
#define FID_OBJ_SERIAL  0x0501
#define FID_OBJ_SIZE    0x0511
#define FID_COMMIT_GEN  0x0601
#define FID_COMMIT_GENERATION FID_COMMIT_GEN
#define FID_MODE        0x0701               /* OBSOLETE: ModeDeclaration field (deprecated) */
#define FID_STORAGE_POLICY 0x0901            /* StoragePolicy.field_id (new) */

/* Modes (GR-38) -- OBSOLETE: deprecated, kept for reader compatibility only */
#define MODE_MODERN       0x01               /* OBSOLETE: was MODERN wire mode */
#define MODE_ENTERPRISE   0x02               /* OBSOLETE: was ENTERPRISE wire mode */

/* ---- Storage Policy (REC_STORAGE_POLICY / FID_STORAGE_POLICY) ---- */
/* Authoritative four-way classification. Directly encoded in .vsn container. */

#define STORAGE_HIGHLY_VERTICAL       1        /* maximum optimization effort */
#define STORAGE_VERTICAL              2        /* bounded optimization effort */
#define STORAGE_HORIZONTAL            3        /* low optimization effort */
#define STORAGE_HIGHLY_HORIZONTAL     4        /* minimal optimization effort */

/* Error codes for storage policy validation */
#define VSN_ERR_INVALID_STORAGE_POLICY   0x0050
#define VSN_ERR_POLICY_WIRE_MODE_CONFLICT 0x0051
#define VSN_ERR_INVALID_OPT_CONFIG       0x0052

/* Representation IDs */
#define REP_DIRECT_1    0x0001
#define REP_EXTENTS_1   0x0002
#define REP_VERSION_1   1

/* Representation operand kinds (VR-23) */
#define OP_LITERAL_BYTES 0
#define OP_OBJECT_SOURCE 1
#define OP_NUMERIC       2
#define OP_NESTED        3

#define MAX_FILES       64
#define MAX_REVISIONS   256
#define MAX_OBJECTS     64
#define MAX_CONTENT     4096

typedef struct {
    uint8_t id[16];
    bool used;
} FileId;

typedef struct {
    uint32_t rev_id;
    FileId file_id;
    uint32_t object_serial;
    char path[256];
    uint8_t presence;
    bool used;
} Revision;

typedef struct {
    uint32_t serial;
    uint32_t len;
    uint8_t data[MAX_CONTENT];
    bool used;
} ContentObject;

typedef struct {
    uint16_t cfv, ev;
    int mode;
    uint8_t storage_policy;  // direct StoragePolicy value (1..4) from REC_STORAGE_POLICY
    uint32_t generation;
    uint32_t trailer_record_count;
    FileId files[MAX_FILES];
    int file_count;
    Revision revs[MAX_REVISIONS];
    int rev_count;
    ContentObject objects[MAX_OBJECTS];
    int obj_count;
    uint32_t next_rev_id;
    uint32_t next_serial;
    bool closed;
    pthread_mutex_t lock;
} VsnContainer;

/* Core API */
int vsn_parse(const uint8_t *data, size_t len, VsnContainer *out);
int vsn_encode(const VsnContainer *c, uint8_t *buf, size_t buf_len, size_t *out_len);
int vsn_materialize(const VsnContainer *c, uint32_t serial, uint8_t *buf, size_t buf_len, size_t *out_len);

/* Store API */
VsnContainer *vsn_create(int mode);
VsnContainer *vsn_open(const uint8_t *data, size_t len);
VsnContainer *vsn_create_with_policy(int storage_policy);
void vsn_close(VsnContainer *c);
int vsn_commit(VsnContainer *c, uint8_t *buf, size_t buf_len, size_t *out_len);
int vsn_reopen(VsnContainer *c, const uint8_t *data, size_t len);

int vsn_create_file(VsnContainer *c, const char *path, const uint8_t *content, size_t len, FileId *out_fid);
int vsn_read_file(VsnContainer *c, const FileId *fid, uint8_t *buf, size_t buf_len, size_t *out_len);
int vsn_write_file(VsnContainer *c, const FileId *fid, const uint8_t *content, size_t len);
int vsn_delete_file(VsnContainer *c, const FileId *fid);
int vsn_rename_file(VsnContainer *c, const FileId *fid, const char *new_path);
int vsn_list_files(const VsnContainer *c, FileId **out, int *count);

int vsn_list_revisions(const VsnContainer *c, const FileId *fid, uint32_t **out, int *count);
int vsn_get_object_serial(const VsnContainer *c, const FileId *fid, uint32_t rev_id, uint32_t *out);
int vsn_checkout_revision(const VsnContainer *c, const FileId *fid, uint32_t rev_id, uint8_t *buf, size_t buf_len, size_t *out_len);

int vsn_limit_cleanup(VsnContainer *c, const FileId *fid, uint32_t limit, uint32_t **removed, int *removed_count);

int vsn_validate(const uint8_t *data, size_t len, const char *level);
int vsn_recover(const uint8_t *data, size_t len, uint8_t *out_buf, size_t buf_len, size_t *out_len);

/* Builder */
int vsn_build_direct1(const uint8_t *content, size_t len, uint8_t *buf, size_t buf_len, size_t *out_len);

/* Primitives (public for testing) */
int vsn_read_uvarint(const uint8_t *data, size_t len, uint64_t *out, size_t *bytes_consumed);
int vsn_write_uvarint(uint64_t v, uint8_t *buf, size_t buf_len, size_t *bytes_written);

/* --- Extended Library capabilities (19-capability surface) --- */

/* Object API */
int vsn_list_objects(const VsnContainer *c, uint32_t **out, int *count);
int vsn_get_object_info(const VsnContainer *c, uint32_t serial,
                        uint32_t *rep_id, uint32_t *version, uint32_t *desc_len);

/* Validation levels: Structural|Semantic|Recovery|Content|Full */
int vsn_validate_level(const uint8_t *data, size_t len, const char *level);

/* Transactions: stage -> commit (CommitMarker is the acceptance authority).
   ExpectedRevisionId is a precondition only and is NEVER persisted. */
typedef struct {
    int op;            /* 0=create 1=update 2=delete */
    char path[256];
    FileId fid;
    int has_fid;
} VsnStagedOp;
typedef struct {
    VsnStagedOp ops[64];
    int nops;
    int32_t expected_rev; /* -1 = none */
    int committed;
} VsnTx;
int vsn_tx_begin(VsnTx *tx);
int vsn_tx_stage_create(VsnTx *tx, const char *path);
int vsn_tx_stage_update(VsnTx *tx, const FileId *fid);
int vsn_tx_stage_delete(VsnTx *tx, const FileId *fid);
int vsn_tx_rollback(VsnTx *tx);
int vsn_tx_commit(VsnContainer *c, VsnTx *tx);

/* Diff (derived, never canonical) */
typedef struct { int added, deleted, modified, unchanged; } VsnFileDiff;
int vsn_diff_files(const VsnContainer *a, const VsnContainer *b, VsnFileDiff *out);
int vsn_diff_revisions(const VsnContainer *c, const FileId *fid,
                       uint32_t ra, uint32_t rb, int *changed, int32_t *delta_bytes);

/* Three-way merge */
typedef struct { int n_conflicts; int has_content; } VsnMergeResult;
int vsn_three_way_merge(const VsnContainer *base, const VsnContainer *ours,
                        const VsnContainer *theirs, VsnMergeResult *out);

/* Import/Export (binary-safe) */
int vsn_import_bytes(VsnContainer *c, const char *path, const uint8_t *content,
                     size_t len, FileId *out_fid);
int vsn_export_bytes(VsnContainer *c, const FileId *fid,
                     uint8_t *buf, size_t buf_len, size_t *out_len);

/* Streaming (chunked) */
int vsn_export_stream(VsnContainer *c, const FileId *fid,
                      int (*cb)(void *ctx, const uint8_t *chunk, size_t n), void *ctx);
int vsn_import_stream(VsnContainer *c, const char *path,
                      int (*cb)(void *ctx, uint8_t *chunk, size_t cap), void *ctx,
                      FileId *out_fid);

/* Diagnostics */
typedef struct { int code; const char *name; const char *message; } VsnDiagnostic;
int vsn_validate_diagnostics(const uint8_t *data, size_t len, const char *level,
                             VsnDiagnostic *out, int cap, int *n_out);

/* Integrity */
int vsn_verify_integrity(const uint8_t *data, size_t len, int *stable);

/* Storage management (derived) */
typedef struct { int record_count, object_count, file_count, revision_count; } VsnStorageStats;
int vsn_storage_stats(const VsnContainer *c, VsnStorageStats *out);

/* Builder API */
typedef struct { int mode; VsnContainer store; } VsnBuilder;
int vsn_builder_new(VsnBuilder *b, int mode);
int vsn_builder_add(VsnBuilder *b, const char *path, const uint8_t *content,
                    size_t len, FileId *out_fid);
int vsn_builder_build(VsnBuilder *b, uint8_t *buf, size_t buf_len,
                      size_t *out_len);
void vsn_builder_free(VsnBuilder *b);

#ifdef __cplusplus
}
#endif

#endif