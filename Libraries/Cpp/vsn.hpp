#pragma once
#include "../C/vsn.h"
#include <string>
#include <vector>
#include <stdexcept>

namespace vsn {

struct Error : std::runtime_error {
    int code;
    Error(int c, const char* m) : std::runtime_error(m), code(c) {}
};

// Throws vsn::Error when rc != VSN_ERR_OK; returns normally when rc == OK.
void throw_if(int rc);

// RAII container over the C core.
class Container {
public:
    explicit Container(int mode);
    explicit Container(const uint8_t* data, size_t len);
    ~Container();
    Container(const Container&) = delete;
    Container& operator=(const Container&) = delete;
    VsnContainer* raw() const { return c; }

    FileId create_file(const std::string& path, const uint8_t* content, size_t len);
    std::vector<uint8_t> read_file(const FileId& fid) const;
    void write_file(const FileId& fid, const uint8_t* content, size_t len);
    void delete_file(const FileId& fid);
    void rename_file(const FileId& fid, const std::string& new_path);
    std::vector<FileId> list_files() const;
    std::vector<uint32_t> list_revisions(const FileId& fid) const;
    std::vector<uint8_t> checkout(const FileId& fid, uint32_t rev) const;
    std::vector<uint8_t> materialize(uint32_t serial) const;
    std::vector<uint32_t> limit_cleanup(const FileId& fid, uint32_t limit);
    std::vector<uint8_t> commit() const;
    std::vector<uint32_t> list_objects() const;
    int mode() const { return c->mode; }
    uint32_t generation() const { return c->generation; }

private:
    VsnContainer* c;
};

// Extended capabilities (validation / recovery / diagnostics / integrity / storage)
bool validate_level(const uint8_t* data, size_t len, const char* level);
struct Diagnostic { int code; std::string name; std::string message; };
Diagnostic validate_diagnostics(const uint8_t* data, size_t len, const char* level);
std::vector<uint8_t> recover(const uint8_t* data, size_t len);
bool verify_integrity(const uint8_t* data, size_t len, bool* stable);
struct StorageStats { int record_count, object_count, file_count, revision_count; };
StorageStats storage_stats(const VsnContainer* c);

// Transactions
void tx_commit(VsnContainer* c, VsnTx& tx);
void tx_rollback(VsnTx& tx);

// Builder API: staged multi-file construction over the same C core.
// The header-only facade cannot reuse C's struct layout, so it stages
// files in memory and materialises them one container at a time.
class ContainerBuilder {
public:
    explicit ContainerBuilder(int mode) : mode_(mode) {}
    FileId add(const std::string& path, const uint8_t* content, size_t len) {
        staged_.push_back({path, std::vector<uint8_t>(content, content + len)});
        VsnContainer* c = vsn_create(mode_);
        if (!c) throw Error(VSN_ERR_CAP, "alloc");
        FileId got{};
        int rc = VSN_ERR_OK;
        for (auto& s : staged_) {
            FileId f; rc = vsn_create_file(c, s.first.c_str(),
                                           s.second.data(), s.second.size(), &f);
            if (rc != VSN_ERR_OK) break;
            if (s.first == path) got = f;
        }
        FileId* fs = nullptr; int n = 0;
        if (rc == VSN_ERR_OK) rc = vsn_list_files(c, &fs, &n);
        if (rc == VSN_ERR_OK && n > 0)
            staged_ids_.assign(fs, fs + n);
        vsn_close(c); throw_if(rc);
        last_ = got;
        return last_;
    }
    std::vector<uint8_t> build() const {
        VsnContainer* c = vsn_create(mode_);
        if (!c) throw Error(VSN_ERR_CAP, "alloc");
        int rc = VSN_ERR_OK;
        for (auto& s : staged_) {
            FileId f; rc = vsn_create_file(c, s.first.c_str(),
                                           s.second.data(), s.second.size(), &f);
            if (rc != VSN_ERR_OK) break;
        }
        static uint8_t buf[1 << 20]; size_t n = 0;
        if (rc == VSN_ERR_OK) rc = vsn_commit(c, buf, sizeof(buf), &n);
        vsn_close(c); throw_if(rc);
        return std::vector<uint8_t>(buf, buf + n);
    }
    int file_count() const { return (int)staged_.size(); }

private:
    int mode_;
    std::vector<std::pair<std::string, std::vector<uint8_t>>> staged_;
    std::vector<FileId> staged_ids_;
    FileId last_{};
};

}  // namespace vsn