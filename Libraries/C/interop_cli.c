/* VSN C interop CLI (frozen VSN, byte-identical to the reference writers).
 *
 *   interop_cli.exe write <root>  ->  <root>/c/<scenario>.vsn   (4 scenarios)
 *   interop_cli.exe read  <root>  ->  JSON: {"lang":"c","results":{...}}
 *
 * Links against vsn.c (see build_debug.bat / interop build). The writer below
 * is a faithful re-implementation of the canonical encoder so that C emits
 * exactly the same bytes as the Python / C# / TypeScript bindings.
 */
#define _CRT_SECURE_NO_WARNINGS 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <direct.h>
#include "vsn.h"

/* ---- growable byte buffer ---- */
typedef struct { uint8_t *b; size_t len, cap; } Buf;
static int brsv(Buf *x, size_t n) {
    if (x->len + n <= x->cap) return 0;
    size_t c = x->cap ? x->cap : 256;
    while (c < x->len + n) c <<= 1;
    uint8_t *p = (uint8_t*)realloc(x->b, c);
    if (!p) return -1;
    x->b = p; x->cap = c; return 0;
}
static void bpush(Buf *x, uint8_t v) { if (brsv(x, 1) == 0) x->b[x->len++] = v; }
static void bbytes(Buf *x, const uint8_t *s, size_t n) { if (brsv(x, n) == 0) { memcpy(x->b + x->len, s, n); x->len += n; } }
static void pu16(Buf *x, uint16_t v) { bpush(x, (uint8_t)(v >> 8)); bpush(x, (uint8_t)v); }
static void pvar(Buf *x, uint64_t v) { while (v >= 0x80) { bpush(x, (uint8_t)(v | 0x80)); v >>= 7; } bpush(x, (uint8_t)v); }
static void cfield(Buf *x, uint16_t fid, const uint8_t *v, size_t n) { pu16(x, fid); pvar(x, n); if (n) bbytes(x, v, n); }
static size_t varbytes(uint64_t v) { size_t n = 1; while (v >= 0x80) { v >>= 7; n++; } return n; }
static void cfieldvar(Buf *x, uint16_t fid, uint64_t v) { pu16(x, fid); pvar(x, varbytes(v)); pvar(x, v); }

/* ---- scenario accumulator ---- */
typedef struct { uint32_t serial; uint8_t *desc; size_t dlen; } Obj;
typedef struct { Buf recs; Obj objs[8]; int nobj; int nrec; int mode; } S;

static void add_rec(S *s, uint16_t rtype, const uint8_t *f, size_t flen) {
    pu16(&s->recs, rtype); pvar(&s->recs, flen); if (flen) bbytes(&s->recs, f, flen); s->nrec++;
}
static void fid_bytes(uint8_t *out, int byte) { for (int i = 0; i < 16; i++) out[i] = (uint8_t)byte; }

static void add_file(S *s, int byte) {
    uint8_t fid[16]; Buf fb = {0};
    fid_bytes(fid, byte); cfield(&fb, FID_FILE_ID, fid, 16);
    add_rec(s, REC_FILE_ID, fb.b, fb.len); free(fb.b);
}

/* ContentObject record (0x0511 = LOGICAL content length) + DIRECT-1 descriptor */
static void add_obj_direct(S *s, int serial, const uint8_t *content, size_t clen) {
    Buf fb = {0};
    cfieldvar(&fb, FID_OBJ_SERIAL, serial);
    cfieldvar(&fb, FID_OBJ_SIZE, clen);
    add_rec(s, REC_OBJ, fb.b, fb.len); free(fb.b);
    Buf d = {0};
    pu16(&d, REP_DIRECT_1); pvar(&d, REP_VERSION_1); if (clen) bbytes(&d, content, clen);
    s->objs[s->nobj].serial = serial; s->objs[s->nobj].desc = d.b; s->objs[s->nobj].dlen = d.len; s->nobj++;
}

/* Revision record */
static void add_rev(S *s, int fidbyte, int rev, int serial, const char *path) {
    uint8_t fid[16]; Buf fb = {0};
    fid_bytes(fid, fidbyte);
    cfieldvar(&fb, FID_REV_ID, rev);
    cfield(&fb, FID_REV_FILE_ID, fid, 16);
    if (serial > 0) cfieldvar(&fb, FID_REV_SERIAL, serial);
    if (path) cfield(&fb, FID_REV_PATH, (const uint8_t*)path, strlen(path));
    cfield(&fb, FID_REV_PRESENCE, (const uint8_t[]){1}, 1);
    add_rec(s, REC_REVISION, fb.b, fb.len); free(fb.b);
}

/* FileHead record */
static void add_head(S *s, int fidbyte, int rev) {
    uint8_t fid[16]; Buf fb = {0};
    fid_bytes(fid, fidbyte);
    cfield(&fb, FID_HEAD_FILE, fid, 16);
    cfieldvar(&fb, FID_HEAD_REV, rev);
    add_rec(s, REC_FILE_HEAD, fb.b, fb.len); free(fb.b);
}

/* ---- EXTENTS-1 operand builders (VR-23) ---- */
static void op_copy(Buf *x, int serial, int offset, int length) {
    pvar(x, OP_NESTED); pvar(x, 3);
    pvar(x, OP_OBJECT_SOURCE); pvar(x, serial);
    pvar(x, OP_NUMERIC); pvar(x, offset);
    pvar(x, OP_NUMERIC); pvar(x, length);
}
static void op_literal(Buf *x, const uint8_t *content, size_t len) {
    pvar(x, OP_NESTED); pvar(x, 2);
    pvar(x, OP_LITERAL_BYTES); pvar(x, len); if (len) bbytes(x, content, len);
    pvar(x, OP_NUMERIC); pvar(x, 0);
}
/* ContentObject record + arbitrary (EXTENTS-1) descriptor; 0x0511 = logical size */
static void add_obj_raw(S *s, int serial, const uint8_t *desc, size_t dlen, size_t logical) {
    Buf fb = {0};
    cfieldvar(&fb, FID_OBJ_SERIAL, serial);
    cfieldvar(&fb, FID_OBJ_SIZE, logical);
    add_rec(s, REC_OBJ, fb.b, fb.len); free(fb.b);
    uint8_t *d = (uint8_t*)malloc(dlen ? dlen : 1);
    if (dlen) memcpy(d, desc, dlen);
    s->objs[s->nobj].serial = serial; s->objs[s->nobj].desc = d; s->objs[s->nobj].dlen = dlen; s->nobj++;
}

/* ---- canonical assembly: header + mode + records + commit + objects + trailer ---- */
static Buf finish(S *s, int gen) {
    Buf o = {0};
    bbytes(&o, (const uint8_t*)"VSN-", 4);
    pu16(&o, 1);              /* ContainerFormatVersion */
    pu16(&o, 1);              /* EncodingVersion */
    cfield(&o, FID_RECORDS_END, NULL, 0);   /* RecordsEnd header marker */
    { Buf mf = {0}; cfield(&mf, FID_MODE, (const uint8_t[]){(uint8_t)s->mode}, 1);
      pu16(&o, REC_MODE); pvar(&o, mf.len); bbytes(&o, mf.b, mf.len); free(mf.b); }
    bbytes(&o, s->recs.b, s->recs.len);
    { Buf cf = {0}; cfieldvar(&cf, FID_COMMIT_GEN, gen);
      pu16(&o, REC_COMMIT); pvar(&o, cf.len); bbytes(&o, cf.b, cf.len); free(cf.b); }
    pu16(&o, REC_END);        /* end-of-records marker */
    for (int i = 0; i < s->nobj; i++) { pvar(&o, s->objs[i].serial); pvar(&o, s->objs[i].dlen); bbytes(&o, s->objs[i].desc, s->objs[i].dlen); }
    pvar(&o, 0);              /* end-of-objects marker */
    pvar(&o, s->nrec + 1);    /* canonical record count (excludes ModeDeclaration, includes Commit) */
    pvar(&o, gen);            /* accepting generation */
    free(s->recs.b);
    for (int i = 0; i < s->nobj; i++) free(s->objs[i].desc);
    return o;
}

/* ---- the four shared interop scenarios (deterministic, byte-identical) ---- */
static Buf build_scenario(const char *name) {
    S s = {0}; s.mode = MODE_MODERN;
    if (strcmp(name, "basic") == 0) {
        add_file(&s, 0x01);
        add_obj_direct(&s, 1, (const uint8_t*)"hello vsn\n", 10);
        add_rev(&s, 0x01, 1, 1, "hello.txt");
        add_head(&s, 0x01, 1);
        return finish(&s, 1);
    }
    if (strcmp(name, "extents") == 0) {
        add_file(&s, 0x02); add_file(&s, 0x03);
        add_obj_direct(&s, 1, (const uint8_t*)"hello vsn\n", 10);
        Buf ops = {0}; op_copy(&ops, 1, 0, 10); op_literal(&ops, (const uint8_t*)"!!", 2);
        Buf desc = {0}; pu16(&desc, REP_EXTENTS_1); pvar(&desc, REP_VERSION_1); pvar(&desc, 2); bbytes(&desc, ops.b, ops.len); free(ops.b);
        add_obj_raw(&s, 2, desc.b, desc.len, 12); free(desc.b);
        add_rev(&s, 0x02, 1, 1, "a.txt");
        add_rev(&s, 0x03, 2, 2, "b.txt");
        add_head(&s, 0x02, 1); add_head(&s, 0x03, 2);
        return finish(&s, 2);
    }
    if (strcmp(name, "enterprise") == 0) {
        s.mode = MODE_ENTERPRISE;
        add_file(&s, 0x04);
        add_obj_direct(&s, 1, (const uint8_t*)"enterprise", 10);
        add_rev(&s, 0x04, 1, 1, "e.txt");
        add_head(&s, 0x04, 1);
        return finish(&s, 1);
    }
    /* multifile: binary content incl NUL and 0xFF */
    add_file(&s, 0x05); add_file(&s, 0x06); add_file(&s, 0x07);
    { uint8_t bin[5] = {0x00, 0x01, 0xFF, 0x00, 0x7F}; add_obj_direct(&s, 1, bin, 5); }
    add_obj_direct(&s, 2, (const uint8_t*)"plain text", 10);
    add_obj_direct(&s, 3, (const uint8_t*)"", 0);
    add_rev(&s, 0x05, 1, 1, "bin.dat");
    add_rev(&s, 0x06, 2, 2, "text.txt");
    add_rev(&s, 0x07, 3, 3, "empty.txt");
    add_head(&s, 0x05, 1); add_head(&s, 0x06, 2); add_head(&s, 0x07, 3);
    return finish(&s, 3);
}

/* ---- canonical interpretation signature (reader side) ---- */
static void hexstr(const uint8_t *b, size_t n, char *out) {
    for (size_t i = 0; i < n; i++) sprintf(out + 2 * i, "%02x", b[i]);
    out[2 * n] = 0;
}
static int describe_sig(const uint8_t *data, size_t len, char *out, size_t outcap) {
    VsnContainer *c = vsn_open(data, len);
    if (!c) return -1;
    size_t off = 0;
    off += (size_t)snprintf(out + off, outcap - off, "mode=%d;gen=%u;", c->mode, c->generation);
    FileId *files = NULL; int nfiles = 0;
    vsn_list_files(c, &files, &nfiles);
    for (int i = 0; i < nfiles; i++) {
        FileId fid = files[i];
        uint32_t best = 0; const char *path = ""; uint32_t ser = 0; int have = 0;
        for (int r = 0; r < c->rev_count; r++) {
            if (!c->revs[r].used) continue;
            if (memcmp(c->revs[r].file_id.id, fid.id, 16) == 0 && c->revs[r].rev_id > best) {
                best = c->revs[r].rev_id; path = c->revs[r].path; ser = c->revs[r].object_serial; have = 1;
            }
        }
        char fh[33]; hexstr(fid.id, 16, fh);
        uint8_t content[4096]; size_t clen = 0;
        if (have && ser) vsn_materialize(c, ser, content, sizeof(content), &clen);
        char ch[8193]; if (clen) hexstr(content, clen, ch); else ch[0] = 0;
        off += (size_t)snprintf(out + off, outcap - off, "[%s|%s|%u|%u|%s];", fh, path, best, ser, ch);
    }
    vsn_close(c);
    return 0;
}

static const char *SCEN[4] = { "basic", "extents", "enterprise", "multifile" };
static const char *PEERS[4] = { "python", "csharp", "typescript", "c" };

static int write_all(const char *root) {
    char dir[1024]; snprintf(dir, sizeof(dir), "%s\\c", root);
    _mkdir(dir); /* succeeds even if it already exists */
    for (int i = 0; i < 4; i++) {
        Buf b = build_scenario(SCEN[i]);
        char path[1200]; snprintf(path, sizeof(path), "%s\\%s.vsn", dir, SCEN[i]);
        FILE *f = fopen(path, "wb");
        if (!f) { free(b.b); return 1; }
        fwrite(b.b, 1, b.len, f); fclose(f); free(b.b);
    }
    printf("{\"lang\": \"c\", \"wrote\": [\"basic\", \"extents\", \"enterprise\", \"multifile\"]}\n");
    return 0;
}

static int read_all(const char *root) {
    printf("{\"lang\": \"c\", \"results\": {");
    int first = 1;
    for (int pi = 0; pi < 4; pi++) {
        for (int si = 0; si < 4; si++) {
            char epath[1200]; snprintf(epath, sizeof(epath), "%s\\%s\\%s.vsn", root, PEERS[pi], SCEN[si]);
            int ok = 0;
            FILE *f = fopen(epath, "rb");
            if (f) {
                fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
                uint8_t *lb = (uint8_t*)malloc(sz > 0 ? (size_t)sz : 1);
                if (sz > 0) fread(lb, 1, (size_t)sz, f);
                fclose(f);
                Buf exp = build_scenario(SCEN[si]);
                char se[16384], sl[16384];
                int de = describe_sig(exp.b, exp.len, se, sizeof(se));
                int dl = describe_sig(lb, sz, sl, sizeof(sl));
                ok = (de == 0 && dl == 0 && strcmp(se, sl) == 0);
                free(exp.b); free(lb);
            }
            printf("%s\"%s/%s\": {\"ok\": %s}", first ? "" : ", ", PEERS[pi], SCEN[si], ok ? "true" : "false");
            first = 0;
        }
    }
    printf("}}\n");
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 3 || (strcmp(argv[1], "write") != 0 && strcmp(argv[1], "read") != 0)) {
        fprintf(stderr, "usage: interop_cli <write|read> <root>\n");
        return 2;
    }
    return strcmp(argv[1], "write") == 0 ? write_all(argv[2]) : read_all(argv[2]);
}
