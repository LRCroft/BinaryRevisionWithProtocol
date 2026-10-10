// VSN-1 C++ library. The C core (vsn.c) is compiled as C and linked into this
// build (see build.bat); the facade here adds RAII, std::vector, and exceptions.
#include "vsn.hpp"
#include <cstring>
#include <utility>

namespace vsn {

static const char* errmsg(int rc) {
    switch (rc) {
        case VSN_ERR_BAD_MAGIC: return "bad magic";
        case VSN_ERR_BAD_CFV: return "bad cfv";
        case VSN_ERR_BAD_EV: return "bad ev";
        case VSN_ERR_MISSING_OBJECT: return "missing object";
        case VSN_ERR_MISSING_REF: return "missing reference";
        case VSN_ERR_INVALID_STATE: return "invalid state";
        case VSN_ERR_TRUNCATED: return "truncated";
        case VSN_ERR_PRIM: return "invalid primitive";
        case VSN_ERR_CAP: return "capacity exceeded";
        case VSN_ERR_MALFORMED: return "malformed";
        default: return "vsn error";
    }
}

void throw_if(int rc) {
    if (rc != VSN_ERR_OK) throw Error(rc, errmsg(rc));
}

Container::Container(int mode) { c = vsn_create(mode); if (!c) throw Error(VSN_ERR_CAP, "alloc"); }
Container::Container(const uint8_t* data, size_t len) { c = vsn_open(data, len); if (!c) throw Error(VSN_ERR_MALFORMED, "open"); }
Container::~Container() { if (c) vsn_close(c); }

FileId Container::create_file(const std::string& path, const uint8_t* content, size_t len) {
    FileId f; throw_if(vsn_create_file(c, path.c_str(), content, len, &f)); return f;
}
std::vector<uint8_t> Container::read_file(const FileId& fid) const {
    uint8_t buf[MAX_CONTENT]; size_t n = 0; throw_if(vsn_read_file(c, &fid, buf, sizeof(buf), &n));
    return std::vector<uint8_t>(buf, buf + n);
}
void Container::write_file(const FileId& fid, const uint8_t* content, size_t len) {
    throw_if(vsn_write_file(c, &fid, content, len));
}
void Container::delete_file(const FileId& fid) { throw_if(vsn_delete_file(c, &fid)); }
void Container::rename_file(const FileId& fid, const std::string& p) { throw_if(vsn_rename_file(c, &fid, p.c_str())); }
std::vector<FileId> Container::list_files() const {
    FileId* f = nullptr; int n = 0; throw_if(vsn_list_files(c, &f, &n));
    return std::vector<FileId>(f, f + n);
}
std::vector<uint32_t> Container::list_revisions(const FileId& fid) const {
    uint32_t* r = nullptr; int n = 0; throw_if(vsn_list_revisions(c, &fid, &r, &n));
    return std::vector<uint32_t>(r, r + n);
}
std::vector<uint8_t> Container::checkout(const FileId& fid, uint32_t rev) const {
    uint8_t buf[MAX_CONTENT]; size_t n = 0; throw_if(vsn_checkout_revision(c, &fid, rev, buf, sizeof(buf), &n));
    return std::vector<uint8_t>(buf, buf + n);
}
std::vector<uint8_t> Container::materialize(uint32_t serial) const {
    uint8_t buf[MAX_CONTENT]; size_t n = 0; throw_if(vsn_materialize(c, serial, buf, sizeof(buf), &n));
    return std::vector<uint8_t>(buf, buf + n);
}
std::vector<uint32_t> Container::limit_cleanup(const FileId& fid, uint32_t limit) {
    uint32_t* r = nullptr; int n = 0; throw_if(vsn_limit_cleanup(c, &fid, limit, &r, &n));
    return std::vector<uint32_t>(r, r + n);
}
std::vector<uint8_t> Container::commit() const {
    std::vector<uint8_t> buf(1 << 20); size_t n = 0;
    throw_if(vsn_commit(c, buf.data(), buf.size(), &n));
    buf.resize(n);
    return buf;
}
std::vector<uint32_t> Container::list_objects() const {
    uint32_t* s = nullptr; int n = 0; throw_if(vsn_list_objects(c, &s, &n));
    return std::vector<uint32_t>(s, s + n);
}

bool validate_level(const uint8_t* data, size_t len, const char* level) {
    return vsn_validate_level(data, len, level ? level : "Full") == VSN_ERR_OK;
}
Diagnostic validate_diagnostics(const uint8_t* data, size_t len, const char* level) {
    VsnDiagnostic d; int n = 0;
    vsn_validate_diagnostics(data, len, level, &d, 1, &n);
    return Diagnostic{ d.code, d.name ? d.name : "", d.message ? d.message : "" };
}
std::vector<uint8_t> recover(const uint8_t* data, size_t len) {
    std::vector<uint8_t> buf(len * 4 + 65536); size_t n = 0;
    int rc = vsn_recover(data, len, buf.data(), buf.size(), &n);
    if (rc != VSN_ERR_OK && rc != VSN_ERR_CAP) throw Error(rc, errmsg(rc));
    buf.resize(n);
    return buf;
}
bool verify_integrity(const uint8_t* data, size_t len, bool* stable) {
    int s = -1; int rc = vsn_verify_integrity(data, len, &s);
    if (stable) *stable = (s == 1);
    return rc == VSN_ERR_OK;
}
StorageStats storage_stats(const VsnContainer* c) {
    VsnStorageStats s; vsn_storage_stats(c, &s);
    return StorageStats{ s.record_count, s.object_count, s.file_count, s.revision_count };
}
void tx_commit(VsnContainer* c, VsnTx& tx) { throw_if(vsn_tx_commit(c, &tx)); }
void tx_rollback(VsnTx& tx) { throw_if(vsn_tx_rollback(&tx)); }

// ---- Storage Policy integration ----

VsnContainer* create_with_storage_policy_raw(int policy, int /*default_mode*/) {
    // Canonical writer: delegates to C vsn_create_with_policy which emits REC_STORAGE_POLICY.
    int val = policy;
    if (val < 1 || val > 4) val = static_cast<int>(STORAGE_HIGHLY_VERTICAL);
    return vsn_create_with_policy(val);
}


}  // namespace vsn
