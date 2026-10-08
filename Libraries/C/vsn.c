#define _CRT_SECURE_NO_WARNINGS
#include "vsn.h"
#include <string.h>
#include <stdlib.h>

/* --- Primitives --- */

int vsn_read_uvarint(const uint8_t *data, size_t len, uint64_t *out, size_t *bytes_consumed) {
    uint64_t value = 0; int shift = 0; size_t i = 0;
    for (int idx = 0; idx < 10; idx++) {
        if (i >= len) return VSN_ERR_TRUNCATED;
        uint8_t b = data[i++];
        if (idx == 9) {
            if (b == 0x01) { *out = value | (1ULL << 63); *bytes_consumed = i; return VSN_ERR_OK; }
            return VSN_ERR_PRIM;
        }
        value |= (uint64_t)(b & 0x7F) << shift;
        if (!(b & 0x80)) {
            if (b == 0 && shift > 0) return VSN_ERR_PRIM;
            *out = value; *bytes_consumed = i; return VSN_ERR_OK;
        }
        shift += 7;
    }
    return VSN_ERR_PRIM;
}

int vsn_write_uvarint(uint64_t v, uint8_t *buf, size_t buf_len, size_t *bytes_written) {
    size_t i = 0;
    while (v >= 0x80) {
        if (i >= buf_len) return VSN_ERR_CAP;
        buf[i++] = (uint8_t)((v & 0x7F) | 0x80); v >>= 7;
    }
    if (i >= buf_len) return VSN_ERR_CAP;
    buf[i++] = (uint8_t)v; *bytes_written = i;
    return VSN_ERR_OK;
}

static void put_u16(uint8_t *buf, uint16_t v) { buf[0]=v>>8; buf[1]=v&0xFF; }
static uint16_t get_u16(const uint8_t *p) { return (uint16_t)((p[0]<<8)|p[1]); }

/* --- Parser --- */
static int parse_fields_into(const uint8_t *data, size_t len, VsnContainer *c, int rec_type) {
    size_t pos = 0;
    while (pos < len) {
        if (pos + 2 > len) return VSN_ERR_TRUNCATED;
        uint16_t fid = get_u16(data + pos); pos += 2;
        uint64_t flen; size_t fb;
        int rc = vsn_read_uvarint(data + pos, len - pos, &flen, &fb);
        if (rc != VSN_ERR_OK) return rc;
        pos += fb;
        if (flen > len - pos) return VSN_ERR_TRUNCATED;
        const uint8_t *val = data + pos; pos += flen;
        if (rec_type == REC_FILE_ID && fid == FID_FILE_ID && flen == 16) {
            if (c->file_count < MAX_FILES) {
                memcpy(c->files[c->file_count].id, val, 16);
                c->files[c->file_count].used = true; c->file_count++;
            }
        } else if (rec_type == REC_REVISION) {
            if (fid == FID_REV_ID) {
                uint64_t rid; size_t rb;
                if (vsn_read_uvarint(val, flen, &rid, &rb) == VSN_ERR_OK && c->rev_count < MAX_REVISIONS) {
                    c->revs[c->rev_count].rev_id = (uint32_t)rid;
                    c->revs[c->rev_count].used = true; c->rev_count++;
                    if (rid >= c->next_rev_id) c->next_rev_id = (uint32_t)rid + 1;
                }
            } else if (fid == FID_REV_FILE_ID && flen == 16 && c->rev_count > 0)
                memcpy(c->revs[c->rev_count-1].file_id.id, val, 16);
            else if (fid == FID_REV_SERIAL && c->rev_count > 0) {
                uint64_t s; size_t sb;
                if (vsn_read_uvarint(val, flen, &s, &sb) == VSN_ERR_OK)
                    c->revs[c->rev_count-1].object_serial = (uint32_t)s;
            } else if (fid == FID_REV_PATH && c->rev_count > 0) {
                size_t cp = flen < 255 ? flen : 255;
                memcpy(c->revs[c->rev_count-1].path, val, cp);
                c->revs[c->rev_count-1].path[cp] = 0;
            } else if (fid == FID_REV_PRESENCE && flen >= 1 && c->rev_count > 0)
                c->revs[c->rev_count-1].presence = val[0];
        } else if (rec_type == REC_COMMIT && fid == FID_COMMIT_GENERATION) {
            uint64_t gen; size_t gb;
            if (vsn_read_uvarint(val, flen, &gen, &gb) == VSN_ERR_OK) c->generation = (uint32_t)gen;
        } else if (rec_type == REC_MODE && fid == FID_MODE && flen >= 1)
            c->mode = val[0];
        else if (rec_type == REC_STORAGE_POLICY && fid == FID_STORAGE_POLICY && flen >= 1)
            c->storage_policy = val[0];
        else if (rec_type == REC_OBJ && fid == FID_OBJ_SERIAL) {
            uint64_t os; size_t ob;
            if (vsn_read_uvarint(val, flen, &os, &ob) == VSN_ERR_OK) {
                if (c->obj_count < MAX_OBJECTS) {
                    c->objects[c->obj_count].serial = (uint32_t)os;
                    c->objects[c->obj_count].used = true; c->obj_count++;
                }
                if (os >= c->next_serial) c->next_serial = (uint32_t)os + 1;
            }
        } else if (rec_type == REC_OBJ && fid == FID_OBJ_SIZE) {
            uint64_t osz; size_t ob;
            if (vsn_read_uvarint(val, flen, &osz, &ob) == VSN_ERR_OK && c->obj_count > 0)
                c->objects[c->obj_count-1].len = (uint32_t)osz;
        }
    }
    return VSN_ERR_OK;
}

/* --- Main Parser --- */
int vsn_parse(const uint8_t *data, size_t len, VsnContainer *out) {
    pthread_mutex_t saved_lock;
    memcpy(&saved_lock, &out->lock, sizeof(pthread_mutex_t));
    memset(out, 0, sizeof(*out));
    memcpy(&out->lock, &saved_lock, sizeof(pthread_mutex_t));
    if (len < 8) return VSN_ERR_TRUNCATED;
    if (memcmp(data, "VSN-", 4) != 0) return VSN_ERR_BAD_MAGIC;
    out->cfv = get_u16(data + 4);
    if (out->cfv != 1) return VSN_ERR_BAD_CFV;
    out->ev = get_u16(data + 6);
    if (out->ev != 1) return VSN_ERR_BAD_EV;
    out->mode = MODE_MODERN;
    out->next_rev_id = 1;
    out->next_serial = 1;
    size_t pos = 8;
    while (pos + 2 <= len) {
        uint16_t fid = get_u16(data + pos); pos += 2;
        uint64_t flen; size_t fb;
        int rc = vsn_read_uvarint(data + pos, len - pos, &flen, &fb);
        if (rc != VSN_ERR_OK) return rc;
        pos += fb;
        if (fid == FID_RECORDS_END) { if (flen != 0) return VSN_ERR_BAD_MAGIC; break; }
        if (flen > len - pos) return VSN_ERR_TRUNCATED;
        pos += flen;
    }
    while (pos + 2 <= len) {
        uint16_t rt = get_u16(data + pos);
        if (rt == REC_END) { pos += 2; break; }
        pos += 2;
        uint64_t rlen; size_t rb;
        int rc = vsn_read_uvarint(data + pos, len - pos, &rlen, &rb);
        if (rc != VSN_ERR_OK) return rc;
        pos += rb;
        if (rlen > len - pos) return VSN_ERR_TRUNCATED;
        if (rt >= 0x8000 && rt <= 0xFFFE) { pos += rlen; continue; }
        if (rt == 0xFFFF) return VSN_ERR_CAP;
        rc = parse_fields_into(data + pos, rlen, out, rt);
        if (rc != VSN_ERR_OK) return rc;
        pos += rlen;
    }
    while (pos < len) {
        uint64_t serial; size_t sb;
        int rc = vsn_read_uvarint(data + pos, len - pos, &serial, &sb);
        if (rc != VSN_ERR_OK) return rc;
        if (serial == 0) { pos += sb; break; }
        pos += sb;
        uint64_t olen; size_t ob;
        rc = vsn_read_uvarint(data + pos, len - pos, &olen, &ob);
        if (rc != VSN_ERR_OK) return rc;
        pos += ob;
        if (olen > len - pos) return VSN_ERR_TRUNCATED;
        for (int i = 0; i < out->obj_count; i++) {
            if (out->objects[i].serial == (uint32_t)serial) {
                size_t cp = olen < MAX_CONTENT ? olen : MAX_CONTENT - 1;
                memcpy(out->objects[i].data, data + pos, cp);
                out->objects[i].len = (uint32_t)olen;
                break;
            }
        }
        pos += olen;
    }
    if (pos < len) {
        uint64_t rcount; size_t rc2;
        if (vsn_read_uvarint(data + pos, len - pos, &rcount, &rc2) == VSN_ERR_OK)
            out->trailer_record_count = (uint32_t)rcount, pos += rc2;
    }
    if (pos < len) {
        uint64_t gen; size_t gc;
        if (vsn_read_uvarint(data + pos, len - pos, &gen, &gc) == VSN_ERR_OK)
            out->generation = (uint32_t)gen;
    }
    return VSN_ERR_OK;
}

/* --- Encoder helper --- */
static int enc_field(uint8_t *buf, size_t off, size_t cap, uint16_t fid, const uint8_t *val, size_t vlen) {
    if (off + 2 > cap) return -1;
    put_u16(buf + off, fid); off += 2;
    size_t wb;
    if (vsn_write_uvarint(vlen, buf + off, cap - off, &wb) != VSN_ERR_OK) return -1;
    off += wb;
    if (vlen > 0 && off + vlen > cap) return -1;
    if (vlen > 0) memcpy(buf + off, val, vlen);
    off += vlen;
    return (int)off;
}

static int enc_record(uint8_t *buf, size_t pos, size_t cap, uint16_t rt, const uint8_t *payload, size_t plen) {
    if (pos + 2 + 11 + plen > cap) return -1;
    buf[pos++] = rt >> 8; buf[pos++] = rt & 0xFF;
    size_t wb;
    if (vsn_write_uvarint(plen, buf + pos, cap - pos, &wb) != VSN_ERR_OK) return -1;
    pos += wb;
    memcpy(buf + pos, payload, plen); pos += plen;
    return (int)pos;
}


/* --- Main Encoder --- */
int vsn_encode(const VsnContainer *c, uint8_t *buf, size_t buf_len, size_t *out_len) {
    size_t pos = 0;
    if (buf_len < 16) return VSN_ERR_CAP;
    memcpy(buf, "VSN-", 4); pos = 4;
    put_u16(buf + pos, 1); pos += 2;
    put_u16(buf + pos, 1); pos += 2;
    pos = (size_t)enc_field(buf, pos, buf_len, FID_RECORDS_END, NULL, 0);
    if (pos < 0) return VSN_ERR_CAP;
    /* Storage Policy (authoritative on wire) - NEVER ModeDeclaration */
    {
        uint8_t sp = c->storage_policy > 0 ? c->storage_policy : STORAGE_VERTICAL;
        uint8_t pl[4]; pl[0]=FID_STORAGE_POLICY>>8; pl[1]=FID_STORAGE_POLICY&0xFF; pl[2]=1; pl[3]=sp;
        pos = (size_t)enc_record(buf, pos, buf_len, REC_STORAGE_POLICY, pl, 4);
        if (pos < 0) return VSN_ERR_CAP;
    }
    /* File identities */
    for (int i = 0; i < c->file_count; i++) {
        if (!c->files[i].used) continue;
        uint8_t pl[20]; pl[0]=FID_FILE_ID>>8; pl[1]=FID_FILE_ID&0xFF; pl[2]=16;
        memcpy(pl+3, c->files[i].id, 16);
        pos = (size_t)enc_record(buf, pos, buf_len, REC_FILE_ID, pl, 19);
        if (pos < 0) return VSN_ERR_CAP;
    }
    /* Revisions */
    for (int i = 0; i < c->rev_count; i++) {
        if (!c->revs[i].used) continue;
        size_t pathlen = strlen(c->revs[i].path);
        uint8_t pl[512]; size_t p = 0;
        pl[p++]=FID_REV_ID>>8; pl[p++]=FID_REV_ID&0xFF;
        uint8_t sv[10]; size_t svb; vsn_write_uvarint(c->revs[i].rev_id, sv, 10, &svb);
        pl[p++]=(uint8_t)svb; memcpy(pl+p, sv, svb); p+=svb;
        pl[p++]=FID_REV_FILE_ID>>8; pl[p++]=FID_REV_FILE_ID&0xFF;
        pl[p++]=16; memcpy(pl+p, c->revs[i].file_id.id, 16); p+=16;
        if (c->revs[i].object_serial > 0) {
            pl[p++]=FID_REV_SERIAL>>8; pl[p++]=FID_REV_SERIAL&0xFF;
            vsn_write_uvarint(c->revs[i].object_serial, sv, 10, &svb);
            pl[p++]=(uint8_t)svb; memcpy(pl+p, sv, svb); p+=svb;
        }
        if (pathlen > 0) {
            pl[p++]=FID_REV_PATH>>8; pl[p++]=FID_REV_PATH&0xFF;
            pl[p++]=(uint8_t)pathlen; memcpy(pl+p, c->revs[i].path, pathlen); p+=pathlen;
        }
        pl[p++]=FID_REV_PRESENCE>>8; pl[p++]=FID_REV_PRESENCE&0xFF;
        pl[p++]=1; pl[p++]=c->revs[i].presence;
        pos = (size_t)enc_record(buf, pos, buf_len, REC_REVISION, pl, p);
        if (pos < 0) return VSN_ERR_CAP;
    }
    /* Content objects */
    for (int i = 0; i < c->obj_count; i++) {
        if (!c->objects[i].used) continue;
        uint8_t pl[30]; size_t p = 0;
        pl[p++]=FID_OBJ_SERIAL>>8; pl[p++]=FID_OBJ_SERIAL&0xFF;
        uint8_t sv[10]; size_t svb; vsn_write_uvarint(c->objects[i].serial, sv, 10, &svb);
        pl[p++]=(uint8_t)svb; memcpy(pl+p, sv, svb); p+=svb;
        pl[p++]=FID_OBJ_SIZE>>8; pl[p++]=FID_OBJ_SIZE&0xFF;
        vsn_write_uvarint(c->objects[i].len, sv, 10, &svb);
        pl[p++]=(uint8_t)svb; memcpy(pl+p, sv, svb); p+=svb;
        pos = (size_t)enc_record(buf, pos, buf_len, REC_OBJ, pl, p);
        if (pos < 0) return VSN_ERR_CAP;
    }
    /* File heads */
    for (int fi = 0; fi < c->file_count; fi++) {
        if (!c->files[fi].used) continue;
        uint32_t head = 0;
        for (int ri = 0; ri < c->rev_count; ri++)
            if (c->revs[ri].used && memcmp(c->revs[ri].file_id.id, c->files[fi].id, 16)==0)
                if (c->revs[ri].rev_id > head) head = c->revs[ri].rev_id;
        if (head == 0) continue;
        uint8_t pl[30]; size_t p = 0;
        pl[p++]=FID_HEAD_FILE>>8; pl[p++]=FID_HEAD_FILE&0xFF;
        pl[p++]=16; memcpy(pl+p, c->files[fi].id, 16); p+=16;
        pl[p++]=FID_HEAD_REV>>8; pl[p++]=FID_HEAD_REV&0xFF;
        uint8_t sv[10]; size_t svb; vsn_write_uvarint(head, sv, 10, &svb);
        pl[p++]=(uint8_t)svb; memcpy(pl+p, sv, svb); p+=svb;
        pos = (size_t)enc_record(buf, pos, buf_len, REC_FILE_HEAD, pl, p);
        if (pos < 0) return VSN_ERR_CAP;
    }
    /* Commit marker */
    {
        uint8_t pl[12]; size_t p = 0;
        pl[p++]=FID_COMMIT_GEN>>8; pl[p++]=FID_COMMIT_GEN&0xFF;
        uint8_t sv[10]; size_t svb; vsn_write_uvarint(c->generation, sv, 10, &svb);
        pl[p++]=(uint8_t)svb; memcpy(pl+p, sv, svb); p+=svb;
        pos = (size_t)enc_record(buf, pos, buf_len, REC_COMMIT, pl, p);
        if (pos < 0) return VSN_ERR_CAP;
    }
    /* End of records */
    buf[pos++]=0; buf[pos++]=0;
    /* Objects section */
    for (int i = 0; i < c->obj_count; i++) {
        if (!c->objects[i].used) continue;
        size_t wb;
        if (vsn_write_uvarint(c->objects[i].serial, buf+pos, buf_len-pos, &wb)!=VSN_ERR_OK) return VSN_ERR_CAP;
        pos += wb;
        if (vsn_write_uvarint(c->objects[i].len, buf+pos, buf_len-pos, &wb)!=VSN_ERR_OK) return VSN_ERR_CAP;
        pos += wb;
        if (pos + c->objects[i].len > buf_len) return VSN_ERR_CAP;
        memcpy(buf+pos, c->objects[i].data, c->objects[i].len); pos += c->objects[i].len;
    }
    buf[pos++]=0;
    /* Trailer: canonical record count = every record EXCEPT ModeDeclaration
       (GR-13). Counts the records actually emitted above (used entries only). */
    uint32_t nfile=0, nrev=0, nobj=0, nheads=0;
    for (int i = 0; i < c->file_count; i++) if (c->files[i].used) nfile++;
    for (int i = 0; i < c->rev_count; i++) if (c->revs[i].used) nrev++;
    for (int i = 0; i < c->obj_count; i++) if (c->objects[i].used) nobj++;
    for (int fi = 0; fi < c->file_count; fi++) {
        if (!c->files[fi].used) continue;
        for (int ri = 0; ri < c->rev_count; ri++)
            if (c->revs[ri].used && memcmp(c->revs[ri].file_id.id, c->files[fi].id, 16)==0) { nheads++; break; }
    }
    uint32_t cc = nfile + nrev + nobj + nheads + 1; /* +1 = CommitMarker */
    { size_t wb; if (vsn_write_uvarint(cc, buf+pos, buf_len-pos, &wb)!=VSN_ERR_OK) return VSN_ERR_CAP; pos+=wb; }
    { size_t wb; if (vsn_write_uvarint(c->generation, buf+pos, buf_len-pos, &wb)!=VSN_ERR_OK) return VSN_ERR_CAP; pos+=wb; }
    *out_len = pos;
    return VSN_ERR_OK;
}

/* --- Store API --- */
VsnContainer *vsn_create(int mode) {
    VsnContainer *c = (VsnContainer *)calloc(1, sizeof(VsnContainer));
    c->cfv = 1; c->ev = 1; c->mode = mode;
    c->next_rev_id = 1; c->next_serial = 1; c->generation = 0;
    pthread_mutex_init(&c->lock, NULL);
    return c;
}

VsnContainer *vsn_create_with_policy(int storage_policy) {
    // Canonical writer: maps policy to wire mode; stores policy directly for encoder.
    int mode = MODE_MODERN;  // HIGHLY_VERTICAL(1), VERTICAL(2) → MODERN
    if (storage_policy >= 3)       // HORIZONTAL(3), HIGHLY_HORIZONTAL(4) → ENTERPRISE
        mode = MODE_ENTERPRISE;
    VsnContainer *c = vsn_create(mode);
    c->storage_policy = (uint8_t)(storage_policy > 0 ? storage_policy : STORAGE_HIGHLY_VERTICAL);
    return c;
}

static int vsn_create_into(VsnContainer *c, int mode) {
    if (!c) return VSN_ERR_PRIM;
    memset(c, 0, sizeof(*c));
    c->cfv = 1; c->ev = 1; c->mode = mode;
    c->next_rev_id = 1; c->next_serial = 1; c->generation = 0;
    return VSN_ERR_OK;
}

VsnContainer *vsn_open(const uint8_t *data, size_t len) {
    VsnContainer *c = (VsnContainer *)calloc(1, sizeof(VsnContainer));
    if (vsn_parse(data, len, c) != VSN_ERR_OK) { free(c); return NULL; }
    pthread_mutex_init(&c->lock, NULL);
    return c;
}

void vsn_close(VsnContainer *c) {
    if (c) { c->closed = true; pthread_mutex_destroy(&c->lock); free(c); }
}

int vsn_commit(VsnContainer *c, uint8_t *buf, size_t buf_len, size_t *out_len) {
    if (c->closed) return VSN_ERR_INVALID_STATE;
    c->generation++;
    int rc = vsn_encode(c, buf, buf_len, out_len);
    if (rc == VSN_ERR_OK) {
        /* Re-parse to update internal state */
        VsnContainer tmp;
        if (vsn_parse(buf, *out_len, &tmp) == VSN_ERR_OK) {
            pthread_mutex_t lock_backup;
            memcpy(&lock_backup, &c->lock, sizeof(pthread_mutex_t));
            memcpy(c, &tmp, sizeof(VsnContainer));
            memcpy(&c->lock, &lock_backup, sizeof(pthread_mutex_t));
            c->closed = false;
        }
    }
    return rc;
}

int vsn_reopen(VsnContainer *c, const uint8_t *data, size_t len) {
    if (c->closed) return VSN_ERR_INVALID_STATE;
    int rc = vsn_parse(data, len, c);
    return rc;
}

/* --- File API --- */
int vsn_create_file(VsnContainer *c, const char *path, const uint8_t *content, size_t len, FileId *out_fid) {
    if (c->closed) return VSN_ERR_INVALID_STATE;
    if (c->file_count >= MAX_FILES) return VSN_ERR_CAP;
    /* Generate a 16-byte file id (deterministic from path + count) */
    uint8_t fid[16];
    memset(fid, 0, 16);
    memcpy(fid, path, strlen(path) < 16 ? strlen(path) : 16);
    fid[15] = (uint8_t)c->file_count;
    int fi = c->file_count;
    memcpy(c->files[fi].id, fid, 16);
    c->files[fi].used = true; c->file_count++;
    /* Create object */
    if (c->obj_count >= MAX_OBJECTS) return VSN_ERR_CAP;
    uint32_t serial = c->next_serial++;
    size_t cp = len < MAX_CONTENT ? len : MAX_CONTENT - 1;
    /* DIRECT-1: rep_id(2) + version(1) + content */
    uint32_t desc_len = 2 + 1 + (uint32_t)cp;
    memcpy(c->objects[serial-1].data, "\x00\x01", 2);
    c->objects[serial-1].data[2] = 1;
    memcpy(c->objects[serial-1].data + 3, content, cp);
    c->objects[serial-1].serial = serial;
    c->objects[serial-1].len = desc_len;
    c->objects[serial-1].used = true;
    c->obj_count++;
    /* Create revision */
    if (c->rev_count >= MAX_REVISIONS) return VSN_ERR_CAP;
    c->revs[c->rev_count].rev_id = c->next_rev_id++;
    memcpy(c->revs[c->rev_count].file_id.id, fid, 16);
    c->revs[c->rev_count].object_serial = serial;
    strncpy(c->revs[c->rev_count].path, path, 255);
    c->revs[c->rev_count].presence = 1; /* PRESENT */
    c->revs[c->rev_count].used = true;
    c->rev_count++;
    if (out_fid) { memcpy(out_fid->id, fid, 16); out_fid->used = true; }
    return VSN_ERR_OK;
}

int vsn_read_file(VsnContainer *c, const FileId *fid, uint8_t *buf, size_t buf_len, size_t *out_len) {
    if (c->closed) return VSN_ERR_INVALID_STATE;
    /* Find newest revision for this file */
    int best = -1; uint32_t best_rid = 0;
    for (int i = 0; i < c->rev_count; i++) {
        if (!c->revs[i].used) continue;
        if (memcmp(c->revs[i].file_id.id, fid->id, 16) == 0) {
            if (c->revs[i].rev_id > best_rid) { best_rid = c->revs[i].rev_id; best = i; }
        }
    }
    if (best < 0) return VSN_ERR_MISSING_REF;
    uint32_t serial = c->revs[best].object_serial;
    for (int i = 0; i < c->obj_count; i++) {
        if (!c->objects[i].used) continue;
        if (c->objects[i].serial == serial) {
            /* Skip DIRECT-1 header (3 bytes) */
            size_t clen = c->objects[i].len > 3 ? c->objects[i].len - 3 : 0;
            if (clen > buf_len) return VSN_ERR_CAP;
            memcpy(buf, c->objects[i].data + 3, clen);
            *out_len = clen;
            return VSN_ERR_OK;
        }
    }
    return VSN_ERR_MISSING_REF;
}

int vsn_write_file(VsnContainer *c, const FileId *fid, const uint8_t *content, size_t len) {
    if (c->closed) return VSN_ERR_INVALID_STATE;
    if (c->rev_count >= MAX_REVISIONS) return VSN_ERR_CAP;
    if (c->obj_count >= MAX_OBJECTS) return VSN_ERR_CAP;
    uint32_t serial = c->next_serial++;
    size_t cp = len < MAX_CONTENT ? len : MAX_CONTENT - 1;
    memcpy(c->objects[c->obj_count].data, "\x00\x01", 2);
    c->objects[c->obj_count].data[2] = 1;
    memcpy(c->objects[c->obj_count].data + 3, content, cp);
    c->objects[c->obj_count].serial = serial;
    c->objects[c->obj_count].len = 3 + (uint32_t)cp;
    c->objects[c->obj_count].used = true; c->obj_count++;
    c->revs[c->rev_count].rev_id = c->next_rev_id++;
    memcpy(c->revs[c->rev_count].file_id.id, fid->id, 16);
    c->revs[c->rev_count].object_serial = serial;
    c->revs[c->rev_count].presence = 1;
    c->revs[c->rev_count].used = true; c->rev_count++;
    return VSN_ERR_OK;
}

int vsn_delete_file(VsnContainer *c, const FileId *fid) {
    if (c->closed) return VSN_ERR_INVALID_STATE;
    for (int i = 0; i < c->rev_count; i++) {
        if (c->revs[i].used && memcmp(c->revs[i].file_id.id, fid->id, 16) == 0)
            c->revs[i].presence = 2; /* DELETED */
    }
    return VSN_ERR_OK;
}

int vsn_rename_file(VsnContainer *c, const FileId *fid, const char *new_path) {
    if (c->closed) return VSN_ERR_INVALID_STATE;
    int best = -1; uint32_t best_rid = 0;
    for (int i = 0; i < c->rev_count; i++) {
        if (c->revs[i].used && memcmp(c->revs[i].file_id.id, fid->id, 16) == 0)
            if (c->revs[i].rev_id > best_rid) { best_rid = c->revs[i].rev_id; best = i; }
    }
    if (best >= 0) {
        strncpy(c->revs[best].path, new_path, 255);
        c->revs[best].path[255] = 0;
    }
    return VSN_ERR_OK;
}

int vsn_list_files(const VsnContainer *c, FileId **out, int *count) {
    *out = (FileId *)c->files;
    *count = c->file_count;
    return VSN_ERR_OK;
}

int vsn_list_revisions(const VsnContainer *c, const FileId *fid, uint32_t **out, int *count) {
    static uint32_t rev_ids[MAX_REVISIONS];
    int n = 0;
    for (int i = 0; i < c->rev_count; i++) {
        if (c->revs[i].used && memcmp(c->revs[i].file_id.id, fid->id, 16) == 0)
            rev_ids[n++] = c->revs[i].rev_id;
    }
    *out = rev_ids; *count = n;
    return VSN_ERR_OK;
}

int vsn_get_object_serial(const VsnContainer *c, const FileId *fid, uint32_t rev_id, uint32_t *out) {
    int best = -1; uint32_t best_rid = 0;
    for (int i = 0; i < c->rev_count; i++) {
        if (!c->revs[i].used) continue;
        if (memcmp(c->revs[i].file_id.id, fid->id, 16) != 0) continue;
        if (rev_id > 0 && c->revs[i].rev_id != rev_id) continue;
        if (c->revs[i].rev_id > best_rid) { best_rid = c->revs[i].rev_id; best = i; }
    }
    if (best < 0) { *out = 0; return VSN_ERR_OK; }
    if (c->revs[best].presence == 2) { *out = 0; return VSN_ERR_OK; }
    *out = c->revs[best].object_serial;
    return VSN_ERR_OK;
}

int vsn_checkout_revision(const VsnContainer *c, const FileId *fid, uint32_t rev_id, uint8_t *buf, size_t buf_len, size_t *out_len) {
    for (int i = 0; i < c->rev_count; i++) {
        if (!c->revs[i].used) continue;
        if (memcmp(c->revs[i].file_id.id, fid->id, 16) != 0) continue;
        if (c->revs[i].rev_id != rev_id) continue;
        if (c->revs[i].presence == 2) return VSN_ERR_OK;
        uint32_t serial = c->revs[i].object_serial;
        for (int j = 0; j < c->obj_count; j++) {
            if (!c->objects[j].used || c->objects[j].serial != serial) continue;
            size_t clen = c->objects[j].len > 3 ? c->objects[j].len - 3 : 0;
            if (clen > buf_len) return VSN_ERR_CAP;
            memcpy(buf, c->objects[j].data + 3, clen);
            *out_len = clen;
            return VSN_ERR_OK;
        }
        return VSN_ERR_MISSING_REF;
    }
    return VSN_ERR_MISSING_REF;
}

/* --- LimitCleanUp --- */
int vsn_limit_cleanup(VsnContainer *c, const FileId *fid, uint32_t limit, uint32_t **removed, int *removed_count) {
    if (c->closed) return VSN_ERR_INVALID_STATE;
    if (limit < 1) return VSN_ERR_INVALID_STATE;
    int found = 0;
    for (int i = 0; i < c->file_count; i++)
        if (c->files[i].used && memcmp(c->files[i].id, fid->id, 16) == 0) { found = 1; break; }
    if (!found) return VSN_ERR_MISSING_REF;
    static uint32_t rids[MAX_REVISIONS];
    int n = 0;
    for (int i = 0; i < c->rev_count; i++)
        if (c->revs[i].used && memcmp(c->revs[i].file_id.id, fid->id, 16) == 0)
            rids[n++] = c->revs[i].rev_id;
    if (n <= (int)limit) { *removed = NULL; *removed_count = 0; return VSN_ERR_OK; }
    /* Sort rids ascending (simple insertion sort) */
    for (int i = 1; i < n; i++) {
        uint32_t key = rids[i]; int j = i - 1;
        while (j >= 0 && rids[j] > key) { rids[j+1] = rids[j]; j--; }
        rids[j+1] = key;
    }
    int keep_start = n - (int)limit;
    int removed_n = 0;
    for (int i = 0; i < keep_start; i++) {
        for (int r = 0; r < c->rev_count; r++) {
            if (c->revs[r].used && c->revs[r].rev_id == rids[i]) { c->revs[r].used = false; break; }
        }
        rids[removed_n++] = rids[i];
    }
    *removed = rids; *removed_count = removed_n;
    return VSN_ERR_OK;
}

/* --- Materialize (DIRECT-1 + EXTENTS-1, DR-0..DR-12) --- */
static const uint8_t *vsn_find_obj(const VsnContainer *c, uint32_t serial, uint32_t *len) {
    for (int i = 0; i < c->obj_count; i++)
        if (c->objects[i].used && c->objects[i].serial == serial) { if (len) *len = c->objects[i].len; return c->objects[i].data; }
    return NULL;
}
static int read_operand(const uint8_t *d, size_t len, size_t *pos, int *kind,
                        uint64_t *num, const uint8_t **lit, size_t *litten) {
    uint64_t k; size_t nb;
    if (vsn_read_uvarint(d + *pos, len - *pos, &k, &nb) != VSN_ERR_OK) return VSN_ERR_PRIM;
    *pos += nb; *kind = (int)k; *num = 0; *lit = NULL; *litten = 0;
    if (k == OP_LITERAL_BYTES) {
        uint64_t l;
        if (vsn_read_uvarint(d + *pos, len - *pos, &l, &nb) != VSN_ERR_OK) return VSN_ERR_PRIM;
        if (l > len - (*pos + nb)) return VSN_ERR_TRUNCATED;
        *pos += nb; *lit = d + *pos; *litten = (size_t)l; *pos += (size_t)l;
    } else if (k == OP_OBJECT_SOURCE || k == OP_NUMERIC) {
        if (vsn_read_uvarint(d + *pos, len - *pos, num, &nb) != VSN_ERR_OK) return VSN_ERR_PRIM;
        *pos += nb;
    } else {
        return VSN_ERR_INVALID_STATE;
    }
    return VSN_ERR_OK;
}

static int mat_extents_body(const VsnContainer *c, const uint8_t *d, size_t dlen,
                            size_t pos, uint32_t self, uint8_t *buf, size_t cap, size_t *out_len);

static int mat_extents_body(const VsnContainer *c, const uint8_t *d, size_t dlen,
                            size_t pos, uint32_t self, uint8_t *buf, size_t cap, size_t *out_len) {
    uint64_t opcount; size_t nb;
    if (vsn_read_uvarint(d + pos, dlen - pos, &opcount, &nb) != VSN_ERR_OK) return VSN_ERR_PRIM;
    pos += nb;
    size_t olen = 0;
    for (uint64_t o = 0; o < opcount; o++) {
        uint64_t kind;
        if (vsn_read_uvarint(d + pos, dlen - pos, &kind, &nb) != VSN_ERR_OK) return VSN_ERR_PRIM;
        pos += nb;
        if (kind != OP_NESTED) return VSN_ERR_INVALID_STATE;
        uint64_t n;
        if (vsn_read_uvarint(d + pos, dlen - pos, &n, &nb) != VSN_ERR_OK) return VSN_ERR_PRIM;
        pos += nb;
        int hk; uint64_t hnum; const uint8_t *hlit; size_t hlitten;
        if (read_operand(d, dlen, &pos, &hk, &hnum, &hlit, &hlitten) != VSN_ERR_OK) return VSN_ERR_PRIM;
        if (hk == OP_OBJECT_SOURCE) {
            if (n != 3) return VSN_ERR_INVALID_STATE;
            int k2; uint64_t v2; const uint8_t *l2; size_t lt2;
            if (read_operand(d, dlen, &pos, &k2, &v2, &l2, &lt2) != VSN_ERR_OK) return VSN_ERR_PRIM;
            uint64_t off = v2;
            if (read_operand(d, dlen, &pos, &k2, &v2, &l2, &lt2) != VSN_ERR_OK) return VSN_ERR_PRIM;
            uint64_t clen = v2;
            if (hnum == self) return VSN_ERR_INVALID_STATE; /* direct dependency cycle */
            uint8_t tmp[MAX_CONTENT]; size_t slen2;
            if (vsn_materialize(c, (uint32_t)hnum, tmp, MAX_CONTENT, &slen2) != VSN_ERR_OK) return VSN_ERR_INVALID_STATE;
            if (off > slen2 || clen > slen2 - off) return VSN_ERR_INVALID_STATE;
            if (clen > cap - olen) return VSN_ERR_CAP;
            memcpy(buf + olen, tmp + off, clen); olen += clen;
        } else if (hk == OP_LITERAL_BYTES) {
            if (hlitten > cap - olen) return VSN_ERR_CAP;
            memcpy(buf + olen, hlit, hlitten); olen += hlitten;
            if (n >= 2) { int k2; uint64_t v2; const uint8_t *l2; size_t lt2;
                if (read_operand(d, dlen, &pos, &k2, &v2, &l2, &lt2) != VSN_ERR_OK) return VSN_ERR_PRIM; }
        } else {
            return VSN_ERR_INVALID_STATE;
        }
    }
    *out_len = olen; return VSN_ERR_OK;
}

int vsn_materialize(const VsnContainer *c, uint32_t serial, uint8_t *buf, size_t buf_len, size_t *out_len) {
    uint32_t dlen; const uint8_t *d = vsn_find_obj(c, serial, &dlen);
    if (!d || dlen < 3) return VSN_ERR_MISSING_OBJECT;
    uint64_t rep = ((uint64_t)d[0] << 8) | d[1];
    size_t pos = 2; uint64_t ver; size_t nb;
    if (vsn_read_uvarint(d + pos, dlen - pos, &ver, &nb) != VSN_ERR_OK) return VSN_ERR_PRIM;
    pos += nb;
    if (rep == REP_DIRECT_1 && ver == REP_VERSION_1) {
        size_t clen = dlen - pos;
        if (clen > buf_len) return VSN_ERR_CAP;
        memcpy(buf, d + pos, clen); *out_len = clen; return VSN_ERR_OK;
    }
    if (rep == REP_EXTENTS_1 && ver == REP_VERSION_1) {
        static int depth = 0;
        if (depth > 64) return VSN_ERR_INVALID_STATE; /* dependency cycle guard */
        depth++;
        int rc = mat_extents_body(c, d, dlen, pos, serial, buf, buf_len, out_len);
        depth--;
        return rc;
    }
    return VSN_ERR_INVALID_STATE; /* unsupported representation identity/version */
}

/* --- Validate (levels: Structural|Semantic|Recovery|Content|Full) --- */
int vsn_validate_level(const uint8_t *data, size_t len, const char *level) {
    VsnContainer c;
    int rc = vsn_parse(data, len, &c);
    if (rc != VSN_ERR_OK) return rc; /* structural failure */
    if (level && strcmp(level, "Structural") == 0) return VSN_ERR_OK;
    /* Semantic: exactly one mode, valid value; ENTERPRISE forbids EXTENTS-1 (GR-43). */
    if (c.mode != MODE_MODERN && c.mode != MODE_ENTERPRISE) return VSN_ERR_INVALID_STATE;
    if (c.mode == MODE_ENTERPRISE) {
        for (int i = 0; i < c.obj_count; i++) {
            if (!c.objects[i].used || c.objects[i].len < 3) continue;
            uint16_t rid = (uint16_t)((c.objects[i].data[0] << 8) | c.objects[i].data[1]);
            if (rid == REP_EXTENTS_1) return VSN_ERR_INVALID_STATE;
        }
    }
    /* every revision must name a known file */
    for (int i = 0; i < c.rev_count; i++) {
        if (!c.revs[i].used) continue;
        int known = 0;
        for (int f = 0; f < c.file_count; f++)
            if (c.files[f].used && memcmp(c.files[f].id, c.revs[i].file_id.id, 16) == 0) known = 1;
        if (!known) return VSN_ERR_MISSING_REF;
    }
    if (level && strcmp(level, "Semantic") == 0) return VSN_ERR_OK;
    /* Recovery: an accepted CommitMarker generation must be present. */
    if (c.generation == 0) return VSN_ERR_INVALID_STATE;
    if (level && strcmp(level, "Recovery") == 0) return VSN_ERR_OK;
    /* Content: every object must materialize (dependency validation + cycle). */
    for (int i = 0; i < c.obj_count; i++) {
        if (!c.objects[i].used) continue;
        uint8_t tmp[MAX_CONTENT]; size_t l;
        if (vsn_materialize(&c, c.objects[i].serial, tmp, MAX_CONTENT, &l) != VSN_ERR_OK)
            return VSN_ERR_INVALID_STATE;
    }
    return VSN_ERR_OK; /* Content and Full both pass here */
}

int vsn_validate(const uint8_t *data, size_t len, const char *level) {
    if (!level || strcmp(level, "Basic") == 0) level = "Structural";
    return vsn_validate_level(data, len, level);
}

/* --- Recover --- */
int vsn_recover(const uint8_t *data, size_t len, uint8_t *out_buf, size_t buf_len, size_t *out_len) {
    /* Try full parse first */
    VsnContainer tmp;
    int rc = vsn_parse(data, len, &tmp);
    if (rc == VSN_ERR_OK) {
        /* Re-encode canonical bytes */
        return vsn_encode(&tmp, out_buf, buf_len, out_len);
    }
    /* Truncated: try to recover by truncating at last valid boundary */
    for (size_t try_len = len; try_len > 10; try_len--) {
        rc = vsn_parse(data, try_len, &tmp);
        if (rc == VSN_ERR_OK) {
            return vsn_encode(&tmp, out_buf, buf_len, out_len);
        }
    }
    return VSN_ERR_TRUNCATED;
}

/* --- Builder --- */
int vsn_build_direct1(const uint8_t *content, size_t len, uint8_t *buf, size_t buf_len, size_t *out_len) {
    if (buf_len < 3 + len) return VSN_ERR_CAP;
    buf[0] = 0x00; buf[1] = 0x01; /* REP_DIRECT_1 */
    buf[2] = 1; /* version */
    memcpy(buf + 3, content, len);
    *out_len = 3 + len;
    return VSN_ERR_OK;
}

/* --- Object API (enumerate / inspect / materialize) --- */
static uint32_t g_obj_serials[MAX_OBJECTS];
int vsn_list_objects(const VsnContainer *c, uint32_t **out, int *count) {
    int n = 0;
    for (int i = 0; i < c->obj_count; i++) if (c->objects[i].used) g_obj_serials[n++] = c->objects[i].serial;
    for (int i = 1; i < n; i++) { uint32_t k = g_obj_serials[i]; int j = i - 1; while (j >= 0 && g_obj_serials[j] > k) { g_obj_serials[j + 1] = g_obj_serials[j]; j--; } g_obj_serials[j + 1] = k; }
    *out = g_obj_serials; *count = n; return VSN_ERR_OK;
}
int vsn_get_object_info(const VsnContainer *c, uint32_t serial, uint32_t *rep_id, uint32_t *version, uint32_t *desc_len) {
    uint32_t dlen; const uint8_t *d = vsn_find_obj(c, serial, &dlen);
    if (!d || dlen < 3) return VSN_ERR_MISSING_OBJECT;
    *rep_id = (uint32_t)((d[0] << 8) | d[1]);
    uint64_t ver; size_t nb;
    if (vsn_read_uvarint(d + 2, dlen - 2, &ver, &nb) != VSN_ERR_OK) return VSN_ERR_PRIM;
    *version = (uint32_t)ver; *desc_len = dlen; return VSN_ERR_OK;
}

/* --- Import/Export (binary-safe, NUL-preserving) --- */
int vsn_import_bytes(VsnContainer *c, const char *path, const uint8_t *content, size_t len, FileId *out_fid) {
    return vsn_create_file(c, path, content, len, out_fid);
}
int vsn_export_bytes(VsnContainer *c, const FileId *fid, uint8_t *buf, size_t buf_len, size_t *out_len) {
    return vsn_read_file(c, fid, buf, buf_len, out_len);
}

/* --- Builder API (high-level container construction) --- */
int vsn_builder_new(VsnBuilder *b, int mode) {
    if (!b) return VSN_ERR_PRIM;
    b->mode = (mode == MODE_ENTERPRISE) ? MODE_ENTERPRISE : MODE_MODERN;
    if (vsn_create_into(&b->store, b->mode) != VSN_ERR_OK) return VSN_ERR_CAP;
    return VSN_ERR_OK;
}
int vsn_builder_add(VsnBuilder *b, const char *path, const uint8_t *content, size_t len, FileId *out_fid) {
    if (!b) return VSN_ERR_PRIM;
    if (vsn_create_file(&b->store, path, content, len, out_fid) != VSN_ERR_OK)
        return VSN_ERR_INVALID_STATE;
    return VSN_ERR_OK;
}
int vsn_builder_build(VsnBuilder *b, uint8_t *buf, size_t buf_len, size_t *out_len) {
    if (!b) return VSN_ERR_PRIM;
    return vsn_commit(&b->store, buf, buf_len, out_len);
}
void vsn_builder_free(VsnBuilder *b) {
    if (!b) return;
    /* Drop any staged store state without committing. */
    memset(&b->store, 0, sizeof(b->store));
    b->mode = MODE_MODERN;
}

/* --- Transactions (stage -> commit; CommitMarker is the acceptance authority) --- */
int vsn_tx_begin(VsnTx *tx) { memset(tx, 0, sizeof(*tx)); tx->expected_rev = -1; return VSN_ERR_OK; }
int vsn_tx_stage_create(VsnTx *tx, const char *path) {
    if (tx->committed || tx->nops >= 64) return VSN_ERR_INVALID_STATE;
    VsnStagedOp *o = &tx->ops[tx->nops++]; o->op = 0; o->has_fid = 0;
    size_t cp = strlen(path) < 255 ? strlen(path) : 255; memcpy(o->path, path, cp); o->path[cp] = 0;
    return VSN_ERR_OK;
}
int vsn_tx_stage_update(VsnTx *tx, const FileId *fid) {
    if (tx->committed || tx->nops >= 64) return VSN_ERR_INVALID_STATE;
    VsnStagedOp *o = &tx->ops[tx->nops++]; o->op = 1; o->has_fid = 1; memcpy(o->fid.id, fid->id, 16); return VSN_ERR_OK;
}
int vsn_tx_stage_delete(VsnTx *tx, const FileId *fid) {
    if (tx->committed || tx->nops >= 64) return VSN_ERR_INVALID_STATE;
    VsnStagedOp *o = &tx->ops[tx->nops++]; o->op = 2; o->has_fid = 1; memcpy(o->fid.id, fid->id, 16); return VSN_ERR_OK;
}
int vsn_tx_rollback(VsnTx *tx) { tx->nops = 0; return VSN_ERR_OK; }
int vsn_tx_commit(VsnContainer *c, VsnTx *tx) {
    if (tx->committed) return VSN_ERR_INVALID_STATE; /* commit twice rejected */
    for (int i = 0; i < tx->nops; i++) {
        VsnStagedOp *o = &tx->ops[i];
        if (o->op == 0) { FileId f; if (vsn_create_file(c, o->path, (const uint8_t*)"", 0, &f) != VSN_ERR_OK) return VSN_ERR_INVALID_STATE; }
        else if (o->op == 1) { if (vsn_write_file(c, &o->fid, (const uint8_t*)"upd", 3) != VSN_ERR_OK) return VSN_ERR_INVALID_STATE; }
        else if (o->op == 2) { if (vsn_delete_file(c, &o->fid) != VSN_ERR_OK) return VSN_ERR_INVALID_STATE; }
    }
    tx->committed = 1; return VSN_ERR_OK;
}

/* --- Diff (derived, never canonical) --- */
static const char *head_path(const VsnContainer *c, const FileId *fid) {
    uint32_t best = 0; const char *bp = NULL;
    for (int i = 0; i < c->rev_count; i++)
        if (c->revs[i].used && memcmp(c->revs[i].file_id.id, fid->id, 16) == 0 && c->revs[i].rev_id > best) { best = c->revs[i].rev_id; bp = c->revs[i].path; }
    return bp;
}
int vsn_diff_files(const VsnContainer *a, const VsnContainer *b, VsnFileDiff *out) {
    memset(out, 0, sizeof(*out));
    for (int i = 0; i < a->file_count; i++) {
        if (!a->files[i].used) continue;
        const char *pa = head_path(a, &a->files[i]); if (!pa) continue;
        int j = -1;
        for (int k = 0; k < b->file_count; k++) { const char *pk = head_path(b, &b->files[k]); if (b->files[k].used && pk && strcmp(pk, pa) == 0) { j = k; break; } }
        if (j < 0) out->deleted++;
        else {
            uint8_t ca[MAX_CONTENT], cb_[MAX_CONTENT]; size_t la = 0, lb = 0;
            vsn_read_file((VsnContainer*)a, &a->files[i], ca, MAX_CONTENT, &la);
            vsn_read_file((VsnContainer*)b, &b->files[j], cb_, MAX_CONTENT, &lb);
            if (la == lb && (la == 0 || memcmp(ca, cb_, la) == 0)) out->unchanged++; else out->modified++;
        }
    }
    for (int k = 0; k < b->file_count; k++) {
        if (!b->files[k].used) continue;
        const char *pb = head_path(b, &b->files[k]); if (!pb) continue;
        int found = 0;
        for (int i = 0; i < a->file_count; i++) { const char *pi = head_path(a, &a->files[i]); if (a->files[i].used && pi && strcmp(pi, pb) == 0) { found = 1; break; } }
        if (!found) out->added++;
    }
    return VSN_ERR_OK;
}
int vsn_diff_revisions(const VsnContainer *c, const FileId *fid, uint32_t ra, uint32_t rb, int *changed, int32_t *delta_bytes) {
    uint8_t ca[MAX_CONTENT], cb_[MAX_CONTENT]; size_t la = 0, lb = 0;
    if (vsn_checkout_revision(c, fid, ra, ca, MAX_CONTENT, &la) != VSN_ERR_OK) return VSN_ERR_MISSING_REF;
    if (vsn_checkout_revision(c, fid, rb, cb_, MAX_CONTENT, &lb) != VSN_ERR_OK) return VSN_ERR_MISSING_REF;
    int ch = (la != lb) || (la > 0 && memcmp(ca, cb_, la) != 0);
    if (changed) *changed = ch; if (delta_bytes) *delta_bytes = (int32_t)lb - (int32_t)la;
    return VSN_ERR_OK;
}

/* --- Three-way merge (conflict detection) --- */
int vsn_three_way_merge(const VsnContainer *base, const VsnContainer *ours, const VsnContainer *theirs, VsnMergeResult *out) {
    memset(out, 0, sizeof(*out));
    out->has_content = 1;
    for (int i = 0; i < base->file_count; i++) {
        if (!base->files[i].used) continue;
        const char *pb = head_path(base, &base->files[i]); if (!pb) continue;
        uint8_t b_[MAX_CONTENT], o[MAX_CONTENT], t[MAX_CONTENT]; size_t lb = 0, lo = 0, lt = 0;
        vsn_read_file((VsnContainer*)base, &base->files[i], b_, MAX_CONTENT, &lb);
        for (int k = 0; k < ours->file_count; k++) { const char *po = head_path(ours, &ours->files[k]); if (ours->files[k].used && po && strcmp(po, pb) == 0) { vsn_read_file((VsnContainer*)ours, &ours->files[k], o, MAX_CONTENT, &lo); break; } }
        for (int k = 0; k < theirs->file_count; k++) { const char *pt = head_path(theirs, &theirs->files[k]); if (theirs->files[k].used && pt && strcmp(pt, pb) == 0) { vsn_read_file((VsnContainer*)theirs, &theirs->files[k], t, MAX_CONTENT, &lt); break; } }
        int ochanged = (lo != lb) || (lo > 0 && memcmp(o, b_, lo) != 0);
        int tchanged = (lt != lb) || (lt > 0 && memcmp(t, b_, lt) != 0);
        if (ochanged && tchanged && ((lo != lt) || (lo > 0 && memcmp(o, t, lo) != 0))) { out->n_conflicts++; out->has_content = 0; }
    }
    return VSN_ERR_OK;
}

/* --- Streaming (chunked, callback-driven) --- */
int vsn_export_stream(VsnContainer *c, const FileId *fid, int (*cb)(void*, const uint8_t*, size_t), void *ctx) {
    uint8_t full[MAX_CONTENT]; size_t flen = 0;
    int rc = vsn_read_file(c, fid, full, MAX_CONTENT, &flen);
    if (rc != VSN_ERR_OK) return rc;
    for (size_t off = 0; off < flen; off += 64) {
        size_t n = (flen - off) < 64 ? (flen - off) : 64;
        if (cb(ctx, full + off, n) != 0) return VSN_ERR_INVALID_STATE;
    }
    return VSN_ERR_OK;
}
int vsn_import_stream(VsnContainer *c, const char *path, int (*cb)(void*, uint8_t*, size_t), void *ctx, FileId *out_fid) {
    uint8_t acc[MAX_CONTENT]; size_t total = 0;
    for (;;) {
        uint8_t chunk[512];
        int n = cb(ctx, chunk, 512);
        if (n <= 0) break;
        if ((size_t)n > MAX_CONTENT - total) return VSN_ERR_CAP;
        memcpy(acc + total, chunk, n); total += n;
    }
    return vsn_create_file(c, path, acc, total, out_fid);
}

/* --- Storage management (derived statistics) --- */
int vsn_storage_stats(const VsnContainer *c, VsnStorageStats *out) {
    out->record_count = c->file_count + c->rev_count + c->obj_count + 1 + (c->generation ? 1 : 0) + 1;
    out->object_count = c->obj_count;
    out->file_count = c->file_count;
    out->revision_count = c->rev_count;
    return VSN_ERR_OK;
}

/* --- Diagnostics (structured validation output) --- */
static const struct { int code; const char *name; const char *msg; } g_diagmap[] = {
    { VSN_ERR_BAD_MAGIC, "BadMagic", "Invalid container magic" },
    { VSN_ERR_BAD_CFV, "BadCfv", "Unsupported container format version" },
    { VSN_ERR_BAD_EV, "BadEv", "Unsupported evolution version" },
    { VSN_ERR_TRUNCATED, "Truncated", "Truncated container" },
    { VSN_ERR_MALFORMED, "Malformed", "Malformed container" },
    { VSN_ERR_MISSING_REF, "MissingReference", "Dangling reference" },
    { VSN_ERR_PRIM, "PrimError", "Invalid primitive encoding" },
    { VSN_ERR_CAP, "Capacity", "Capacity exceeded" },
    { VSN_ERR_INVALID_STATE, "InvalidState", "Invalid semantic state" },
};
int vsn_validate_diagnostics(const uint8_t *data, size_t len, const char *level,
                             VsnDiagnostic *out, int cap, int *n_out) {
    int rc = vsn_validate_level(data, len, level ? level : "Full");
    if (rc == VSN_ERR_OK) { if (n_out) *n_out = 0; return VSN_ERR_OK; }
    int n = 0;
    for (int i = 0; i < 9 && n < cap; i++) {
        if (g_diagmap[i].code == rc) { out[n].code = rc; out[n].name = g_diagmap[i].name; out[n].message = g_diagmap[i].msg; n++; break; }
    }
    if (n == 0 && n < cap) { out[n].code = rc; out[n].name = "Error"; out[n].message = "Validation failed"; n++; }
    if (n_out) *n_out = n;
    return rc;
}

/* --- Integrity (reparse + re-encode stability) --- */
int vsn_verify_integrity(const uint8_t *data, size_t len, int *stable) {
    VsnContainer c;
    int rc = vsn_parse(data, len, &c);
    if (rc != VSN_ERR_OK) { if (stable) *stable = 0; return rc; }
    uint8_t re[65536]; size_t rl = 0;
    if (vsn_encode(&c, re, sizeof(re), &rl) != VSN_ERR_OK) { if (stable) *stable = 0; return VSN_ERR_CAP; }
    int s = (rl == len && memcmp(data, re, len) == 0);
    if (stable) *stable = s;
    return s ? VSN_ERR_OK : VSN_ERR_MALFORMED;
}
