import { randomUUID } from "crypto";
import { parse } from "./container.js";
import type { ParsedContainer } from "./container.js";
import { encode, direct1Descriptor } from "./writer.js";
import type { EncodedRecord, EncodedObject } from "./writer.js";
import { parseObjectHeader, materializeDirect, materializeExtents } from "./representations.js";
import { materializeDirectStream, materializeExtentsStream } from "./representations.js";
import { validate as validateContainer } from "./validate.js";
import { VsnError } from "./errors.js";
import { putUvarint } from "./primitives.js";
import {
  REC_MODE_DECLARATION, REC_FILE_IDENTITY, REC_REVISION, REC_CONTENT_OBJECT,
  REC_FILE_HEAD, REC_COMMIT_MARKER, REC_STORAGE_POLICY, FID_MODE, FID_STORAGE_POLICY,
  FID_FILE_ID, FID_REV_ID,
  FID_REV_FILE_ID, FID_REV_OBJECT_SERIAL, FID_REV_PATH, FID_REV_PRESENCE,
  FID_HEAD_FILE_ID, FID_HEAD_REV_ID, FID_OBJECT_SERIAL, FID_OBJECT_SIZE,
  FID_COMMIT_GENERATION, MODE_MODERN, MODE_ENTERPRISE, PRESENT, DELETED,
  REP_DIRECT_1, REP_EXTENTS_1, REP_VERSION_1,
} from "./constants.js";

// Tier 3: simple async mutex for thread-safe operations
class Mutex {
  private _queue: Array<() => void> = [];
  private _locked = false;
  async acquire(): Promise<void> {
    if (!this._locked) { this._locked = true; return; }
    return new Promise(r => this._queue.push(r));
  }
  release(): void {
    const next = this._queue.shift();
    if (next) { next(); } else { this._locked = false; }
  }
  async withLock<T>(fn: () => T): Promise<T> { await this.acquire(); try { return fn(); } finally { this.release(); } }
}
export { Mutex };

export interface FileInfo { fileId: Buffer; path: string | null; headRevision: number | null; }
export interface RevisionInfo {
  revisionId: number; fileId: Buffer; objectSerial: number | null;
  path: string | null; presence: number;
}
export interface ObjectInfo {
  serial: number; length: number; representationIdentity: number; representationVersion: number;
}
export interface ContainerInfo {
  mode: number; generation: number; fileCount: number; objectCount: number; revisionCount: number;
}

function fileKey(fid: Buffer): string { return Buffer.from(fid).toString("hex"); }

/** Generated FileId: 16 opaque bytes of identity, never a content hash. */
export function generateFileId(): Buffer {
  return Buffer.from(randomUUID().replace(/-/g, ""), "hex");
}
/** Mutable VSN-1 container with the full library API. */
export class VsnStore {
  private data: Buffer = Buffer.alloc(0);
  private parsed: ParsedContainer | null = null;
  private closed = false;
  private modeValue: number;
  private storagePolicy: number = 2; // default VERTICAL
  private fileIds = new Map<string, FileInfo>();
  private revisions = new Map<number, RevisionInfo>();
  private objects = new Map<number, Buffer>();
  private contentCache = new Map<number, Buffer>();
  private nextObjectSerial = 1;
  private nextRevisionId = 1;
  private generationValue = 0;

  constructor(data?: Buffer, mode: number = MODE_MODERN) {
    if (data !== undefined) {
      this.data = Buffer.from(data);
      this.parsed = parse(this.data);
      this.modeValue = this.parsed.mode ?? mode;
    } else {
      this.modeValue = mode;
    }
    this.buildState();
  }

  static create(mode: number = MODE_MODERN): VsnStore { return new VsnStore(undefined, mode); }
  static createWithPolicy(policy: number): VsnStore {
    // Canonical writer: stores policy directly; toBytes emits REC_STORAGE_POLICY.
    const s = new VsnStore(undefined, MODE_MODERN);
    s.storagePolicy = policy > 0 ? policy : 2;
    return s;
  }
private buildState(): void {
    this.fileIds.clear(); this.revisions.clear(); this.objects.clear();
    this.contentCache.clear();
    this.nextObjectSerial = 1; this.nextRevisionId = 1; this.generationValue = 0;
    if (!this.parsed) return;
    for (const rec of this.parsed.records) {
      if (rec.rtype === REC_FILE_IDENTITY) {
        const f = rec.getField(FID_FILE_ID);
        if (f) this.fileIds.set(fileKey(f.value), {
          fileId: Buffer.from(f.value), path: null, headRevision: null });
      } else if (rec.rtype === REC_REVISION) {
        this.applyRevisionRecord(rec);
      } else if (rec.rtype === REC_FILE_HEAD) {
        const fid = rec.getField(FID_HEAD_FILE_ID);
        const rid = rec.getField(FID_HEAD_REV_ID);
        if (fid && rid) {
          const info = this.fileIds.get(fileKey(fid.value));
          if (info) info.headRevision = Number(rid.asUvarint());
        }
      } else if (rec.rtype === REC_COMMIT_MARKER) {
        const g = rec.getField(FID_COMMIT_GENERATION);
        if (g) this.generationValue = Number(g.asUvarint());
      }
    }
    for (const obj of this.parsed.objects) {
      const serial = Number(obj.serial);
      this.objects.set(serial, Buffer.from(obj.descriptor));
      if (serial >= this.nextObjectSerial) this.nextObjectSerial = serial + 1;
    }
  }
private applyRevisionRecord(
    rec: { getField(fid: number): { value: Buffer; asUvarint(): bigint } | undefined },
  ): void {
    const ridF = rec.getField(FID_REV_ID);
    const fidF = rec.getField(FID_REV_FILE_ID);
    if (!ridF || !fidF) return;
    const rid = Number(ridF.asUvarint());
    const objF = rec.getField(FID_REV_OBJECT_SERIAL);
    const pathF = rec.getField(FID_REV_PATH);
    const presF = rec.getField(FID_REV_PRESENCE);
    const path = pathF ? pathF.value.toString("utf8") : null;
    this.revisions.set(rid, {
      revisionId: rid, fileId: Buffer.from(fidF.value),
      objectSerial: objF ? Number(objF.asUvarint()) : null,
      path, presence: presF ? presF.value[0] : PRESENT,
    });
    if (rid >= this.nextRevisionId) this.nextRevisionId = rid + 1;
    const info = this.fileIds.get(fileKey(fidF.value));
    if (info && pathF) info.path = path;
  }

  private checkOpen(): void {
    if (this.closed) throw new VsnError(0x0001, "container is closed");
  }
get mode(): number { return this.modeValue; }
  get generation(): number { return this.generationValue; }
  get isClosed(): boolean { return this.closed; }

  close(): void { this.closed = true; this.contentCache.clear(); }

  reopen(data?: Buffer): void {
    this.checkOpen();
    if (data === undefined) data = this.data;
    this.data = Buffer.from(data);
    this.parsed = parse(this.data);
    this.buildState();
  }

  inspect(): ContainerInfo {
    this.checkOpen();
    return {
      mode: this.modeValue, generation: this.generationValue,
      fileCount: this.fileIds.size, objectCount: this.objects.size,
      revisionCount: this.revisions.size,
    };
  }

  // --- File API ---

  /** Create a file and its first Revision; returns the FileId. */
  createFile(path: string, content: Buffer = Buffer.alloc(0)): Buffer {
    this.checkOpen();
    for (const info of this.fileIds.values())
      if (info.path === path) throw new VsnError(0x000A, `duplicate path ${path}`);
    const fileId = generateFileId();
    this.fileIds.set(fileKey(fileId), { fileId, path, headRevision: null });
    const serial = this.addObject(content);
    const rid = this.nextRevisionId++;
    this.revisions.set(rid, {
      revisionId: rid, fileId, objectSerial: serial, path, presence: PRESENT });
    this.fileIds.get(fileKey(fileId))!.headRevision = rid;
    return fileId;
  }
  static open(data: Buffer): VsnStore { return new VsnStore(data); }
readFile(fileId: Buffer): Buffer {
    this.checkOpen();
    const info = this.fileIds.get(fileKey(fileId));
    if (!info) throw new VsnError(0x0009, "unknown FileId");
    if (info.headRevision === null) throw new VsnError(0x0009, "no accepted revision");
    const rev = this.revisions.get(info.headRevision)!;
    if (rev.presence === DELETED) throw new VsnError(0x0009, "file is deleted");
    if (rev.objectSerial === null) return Buffer.alloc(0);
    return this.materialize(rev.objectSerial);
  }

  writeFile(fileId: Buffer, content: Buffer): void {
    this.checkOpen();
    const info = this.fileIds.get(fileKey(fileId));
    if (!info) throw new VsnError(0x0009, "unknown FileId");
    const serial = this.addObject(content);
    const rid = this.nextRevisionId++;
    this.revisions.set(rid, {
      revisionId: rid, fileId, objectSerial: serial, path: info.path, presence: PRESENT });
    info.headRevision = rid;
  }

  deleteFile(fileId: Buffer): void {
    this.checkOpen();
    const info = this.fileIds.get(fileKey(fileId));
    if (!info) throw new VsnError(0x0009, "unknown FileId");
    const rid = this.nextRevisionId++;
    this.revisions.set(rid, {
      revisionId: rid, fileId, objectSerial: null, path: info.path, presence: DELETED });
    info.headRevision = rid;
  }

  renameFile(fileId: Buffer, newPath: string): void {
    this.checkOpen();
    const info = this.fileIds.get(fileKey(fileId));
    if (!info) throw new VsnError(0x0009, "unknown FileId");
    for (const [key, other] of this.fileIds)
      if (key !== fileKey(fileId) && other.path === newPath)
        throw new VsnError(0x000A, `duplicate path ${newPath}`);
    const oldRev = info.headRevision !== null ? this.revisions.get(info.headRevision) : undefined;
    const rid = this.nextRevisionId++;
    this.revisions.set(rid, {
      revisionId: rid, fileId, objectSerial: oldRev?.objectSerial ?? null,
      path: newPath, presence: oldRev?.presence ?? PRESENT });
    info.headRevision = rid;
    info.path = newPath;
  }

  listFiles(): FileInfo[] {
    this.checkOpen();
    return [...this.fileIds.values()].map((i) => ({ ...i, fileId: Buffer.from(i.fileId) }));
  }

  fileExists(fileId: Buffer): boolean {
    this.checkOpen();
    const info = this.fileIds.get(fileKey(fileId));
    if (!info || info.headRevision === null) return false;
    return this.revisions.get(info.headRevision)!.presence !== DELETED;
  }

  getFileId(path: string): Buffer | null {
    this.checkOpen();
    for (const info of this.fileIds.values())
      if (info.path === path) return Buffer.from(info.fileId);
    return null;
  }

  getFileMetadata(fileId: Buffer): FileInfo {
    this.checkOpen();
    const info = this.fileIds.get(fileKey(fileId));
    if (!info) throw new VsnError(0x0009, "unknown FileId");
    return { ...info, fileId: Buffer.from(info.fileId) };
  }

  // --- Revision API ---

  listRevisions(fileId?: Buffer): number[] {
    this.checkOpen();
    const all = [...this.revisions.values()];
    if (fileId === undefined) return all.map((r) => r.revisionId).sort((a, b) => a - b);
    const key = fileKey(fileId);
    return all.filter((r) => fileKey(r.fileId) === key)
      .map((r) => r.revisionId).sort((a, b) => a - b);
  }

  getRevision(revisionId: number): RevisionInfo {
    this.checkOpen();
    const rev = this.revisions.get(revisionId);
    if (!rev) throw new VsnError(0x0009, `unknown RevisionId ${revisionId}`);
    return { ...rev, fileId: Buffer.from(rev.fileId) };
  }

  getCurrentRevision(fileId: Buffer): number | null {
    this.checkOpen();
    const info = this.fileIds.get(fileKey(fileId));
    return info ? info.headRevision : null;
  }

  /** Compare two revisions of a file; returns whether content differs. */
  compareRevisions(fileId: Buffer, revA: number, revB: number): boolean {
    return !this.checkoutRevision(fileId, revA).equals(this.checkoutRevision(fileId, revB));
  }

  /** Revision metadata including the owning FileId and presence. */
  revisionMetadata(revisionId: number): RevisionInfo { return this.getRevision(revisionId); }

  checkoutRevision(fileId: Buffer, revisionId: number): Buffer {
    this.checkOpen();
    const rev = this.revisions.get(revisionId);
    if (!rev) throw new VsnError(0x0009, `unknown RevisionId ${revisionId}`);
    if (fileKey(rev.fileId) !== fileKey(fileId))
      throw new VsnError(0x000B, "RevisionId does not belong to FileId");
    if (rev.objectSerial === null) return Buffer.alloc(0);
    return this.materialize(rev.objectSerial);
  }

  restoreRevision(fileId: Buffer, revisionId: number): void {
    this.checkOpen();
    const rev = this.revisions.get(revisionId);
    if (!rev) throw new VsnError(0x0009, `unknown RevisionId ${revisionId}`);
    if (fileKey(rev.fileId) !== fileKey(fileId))
      throw new VsnError(0x000B, "RevisionId does not belong to FileId");
    const content = rev.objectSerial === null ? Buffer.alloc(0) : this.materialize(rev.objectSerial);
    this.writeFile(fileId, content);
  }

  // --- History retention (Library capability, NOT a VSN protocol rule) ---

  /**
   * LimitCleanUp: retain only the newest `limit` revisions of a file.
   *
   * LIBRARY capability, not a VSN-1 protocol rule. Scope is a single file's
   * history, matching the VSN revision model in which every Revision names one
   * FileId and each file has its own head.
   *
   * `limit` is the maximum number of revisions retained and MUST be >= 1;
   * limit 0 is rejected (0x000C) so a slipped argument cannot silently destroy
   * an entire history. If the file already has <= limit revisions, nothing is
   * removed.
   *
   * Retained revisions are never rewritten: their RevisionId, contents and
   * ObjectSerial are untouched, so the next commit() re-emits them identically.
   * The head revision is the newest, so it is always retained and the FileHead
   * record can never be left dangling.
   *
   * Objects are deliberately NOT removed: the object section is a shared content
   * store that a retained revision elsewhere, or an EXTENTS-1 COPY operand, may
   * still reference. Reclaiming objects is a separate operation.
   *
   * @returns the removed RevisionIds in ascending order. Idempotent: a repeated
   * call removes nothing. The change is applied atomically to in-memory state;
   * persist it with the normal commit().
   */
  limitCleanup(fileId: Buffer, limit: number): number[] {
    this.checkOpen();
    if (!Number.isInteger(limit) || limit < 1)
      throw new VsnError(0x000C, `LimitCleanUp limit must be >= 1, got ${limit}`);
    const info = this.fileIds.get(fileKey(fileId));
    if (!info) throw new VsnError(0x0009, "unknown FileId");

    // Canonical revision ordering is ascending RevisionId.
    const key = fileKey(fileId);
    const rids: number[] = [];
    for (const rev of this.revisions.values())
      if (fileKey(rev.fileId) === key) rids.push(rev.revisionId);
    rids.sort((a, b) => a - b);
    if (rids.length <= limit) return [];         // nothing to do; state untouched

    const removed = rids.slice(0, rids.length - limit);
    const head = info.headRevision;
    if (head !== null && removed.includes(head))
      // Defensive: the head is the newest revision, so this cannot happen while
      // limit >= 1. Refuse rather than emit a dangling FileHead.
      throw new VsnError(0x000C, `LimitCleanUp would remove head revision ${head}`);

    // Apply atomically: snapshot the entries being removed, mutate, and restore
    // them on any failure so a failed cleanup never leaves partially pruned
    // history behind.
    const snapshot = new Map<number, RevisionInfo>();
    for (const rid of removed) snapshot.set(rid, this.revisions.get(rid)!);
    try {
      for (const rid of removed) this.revisions.delete(rid);
      this.contentCache.clear();
    } catch (e) {
      for (const [rid, rev] of snapshot) this.revisions.set(rid, rev);
      throw e;
    }
    return removed;
  }

  // --- Object API ---

  addObject(content: Buffer): number {
    const serial = this.nextObjectSerial++;
    this.objects.set(serial, direct1Descriptor(content));
    return serial;
  }

  /** Register an explicit object descriptor (used for EXTENTS-1/COPY vectors). */
  addObjectDescriptor(descriptor: Buffer, serial?: number): number {
    const sid = serial ?? this.nextObjectSerial++;
    if (sid >= this.nextObjectSerial) this.nextObjectSerial = sid + 1;
    this.objects.set(sid, Buffer.from(descriptor));
    return sid;
  }

  listObjects(): number[] {
    this.checkOpen();
    return [...this.objects.keys()].sort((a, b) => a - b);
  }

  getObjectInfo(serial: number): ObjectInfo {
    this.checkOpen();
    const desc = this.objects.get(serial);
    if (!desc) throw new VsnError(0x0008, `missing object ${serial}`);
    const { identity, version, remainder } = parseObjectHeader(desc);
    return {
      serial, length: remainder.length,
      representationIdentity: identity, representationVersion: version };
  }

  getObjectMetadata(serial: number): ObjectInfo { return this.getObjectInfo(serial); }

  getObjectSerial(fileId: Buffer, revisionId?: number): number | null {
    this.checkOpen();
    const info = this.fileIds.get(fileKey(fileId));
    if (!info) throw new VsnError(0x0009, "unknown FileId");
    const rid = revisionId ?? info.headRevision;
    if (rid === null) return null;
    const rev = this.revisions.get(rid);
    return rev ? rev.objectSerial : null;
  }

  materialize(serial: number, visited?: Set<number>): Buffer {
    visited ??= new Set<number>();
    if (visited.has(serial))
      throw new VsnError(0x000C, `dependency cycle at ObjectSerial ${serial}`);
    const cached = this.contentCache.get(serial);
    if (cached) return cached;
    const desc = this.objects.get(serial);
    if (!desc) throw new VsnError(0x0008, `missing object ${serial}`);
    const { identity, version, remainder } = parseObjectHeader(desc);
    let out: Buffer;
    if (identity === REP_DIRECT_1 && version === REP_VERSION_1) {
      out = materializeDirect(remainder);
    } else if (identity === REP_EXTENTS_1 && version === REP_VERSION_1) {
      const next = new Set(visited);
      next.add(serial);
      out = materializeExtents(remainder, (s) => this.materialize(Number(s), new Set(next)));
    } else {
      throw new VsnError(0x0006, `unsupported representation 0x${identity.toString(16)} v${version}`);
    }
    this.contentCache.set(serial, out);
    return out;
  }

  // --- Canonical serialization ---

  /** Produce canonical VSN-1 bytes from current state (SR-* closure). */
  toBytes(): Buffer {
    this.checkOpen();
    this.generationValue += 1;
    const records: EncodedRecord[] = [];
    // Canonical: always emit REC_STORAGE_POLICY (authoritative on wire). NEVER ModeDeclaration.
    const policyVal = this.storagePolicy > 0 ? this.storagePolicy : 2;
    records.push({ rtype: REC_STORAGE_POLICY, fields: [{ fid: FID_STORAGE_POLICY, value: Buffer.from([policyVal]) }] });
    for (const info of this.fileIds.values())
      records.push({ rtype: REC_FILE_IDENTITY, fields: [{ fid: FID_FILE_ID, value: info.fileId }] });
    for (const rid of [...this.revisions.keys()].sort((a, b) => a - b)) {
      const rev = this.revisions.get(rid)!;
      const fields = [
        { fid: FID_REV_ID, value: putUvarint(rev.revisionId) },
        { fid: FID_REV_FILE_ID, value: rev.fileId },
      ];
      if (rev.objectSerial !== null)
        fields.push({ fid: FID_REV_OBJECT_SERIAL, value: putUvarint(rev.objectSerial) });
      if (rev.path !== null)
        fields.push({ fid: FID_REV_PATH, value: Buffer.from(rev.path, "utf8") });
      fields.push({ fid: FID_REV_PRESENCE, value: Buffer.from([rev.presence]) });
      records.push({ rtype: REC_REVISION, fields });
    }
    for (const serial of [...this.objects.keys()].sort((a, b) => a - b)) {
      // 0x0511 declared size is the LOGICAL content length (SR-27, DR-6), never
      // the representation payload length. Frozen vector EXT-02/EXT-03 is
      // authoritative: serial 20 has a 17-byte EXTENTS-1 remainder but declares
      // size 12 (its materialized length).
      // The field is OPTIONAL (SR-27), so it is omitted when the logical length
      // cannot be resolved (missing dependency, cycle, or an unsupported
      // representation, which is not an invalid state).
      const fields = [{ fid: FID_OBJECT_SERIAL, value: putUvarint(serial) }];
      try {
        fields.push({ fid: FID_OBJECT_SIZE, value: putUvarint(this.materialize(serial).length) });
      } catch {
        // Unresolvable object: 0x0511 omitted, which is fully valid.
      }
      records.push({ rtype: REC_CONTENT_OBJECT, fields });
    }
    for (const info of this.fileIds.values()) {
      if (info.headRevision !== null) {
        records.push({
          rtype: REC_FILE_HEAD,
          fields: [
            { fid: FID_HEAD_FILE_ID, value: info.fileId },
            { fid: FID_HEAD_REV_ID, value: putUvarint(info.headRevision) },
          ] });
      }
    }
    records.push({
      rtype: REC_COMMIT_MARKER,
      fields: [{ fid: FID_COMMIT_GENERATION, value: putUvarint(this.generationValue) }] });
    const objects: EncodedObject[] = [...this.objects.keys()].sort((a, b) => a - b)
      .map((s) => ({ serial: BigInt(s), descriptor: this.objects.get(s)! }));
    return encode(this.modeValue, records, objects, this.generationValue);
  }
/** Commit current state; CommitMarker is the sole acceptance authority. */
  commit(): Buffer {
    this.checkOpen();
    const data = this.toBytes();
    this.data = data;
    this.parsed = parse(data);
    this.contentCache.clear();
    return data;
  }

  /** Validate this store's canonical state at a requested level. */
  validate(level: "Structural" | "Semantic" | "Recovery" | "Content" | "Full" = "Full"): void {
    this.checkOpen();
    validateContainer(this.toBytes(), level);
  }

  /** Internal accessors used by StorageManager (derived data only). */
  get canonicalData(): Buffer { return this.data; }
  get parsedContainer(): ParsedContainer | null { return this.parsed; }

  /** Stream an object's logical content in chunks (no full copy required). */
  *materializeStream(serial: number, chunkSize = 65536, visited?: Set<number>): Generator<Buffer> {
    visited ??= new Set<number>();
    if (visited.has(serial))
      throw new VsnError(0x000C, `dependency cycle at ObjectSerial ${serial}`);
    const desc = this.objects.get(serial);
    if (!desc) throw new VsnError(0x0008, `missing object ${serial}`);
    const { identity, version, remainder } = parseObjectHeader(desc);
    if (identity === REP_DIRECT_1 && version === REP_VERSION_1) {
      yield* materializeDirectStream(remainder, chunkSize);
      return;
    }
    if (identity === REP_EXTENTS_1 && version === REP_VERSION_1) {
      const next = new Set(visited);
      next.add(serial);
      yield* materializeExtentsStream(
        remainder, (s) => this.materialize(Number(s), new Set(next)), chunkSize);
      return;
    }
    throw new VsnError(0x0006, `unsupported representation 0x${identity.toString(16)} v${version}`);
  }

  /** Stream a file's accepted content in chunks (SR-38 recovery path). */
  *readFileStream(fileId: Buffer, chunkSize = 65536): Generator<Buffer> {
    this.checkOpen();
    const info = this.fileIds.get(fileKey(fileId));
    if (!info) throw new VsnError(0x0009, "unknown FileId");
    if (info.headRevision === null) throw new VsnError(0x0009, "no accepted revision");
    const rev = this.revisions.get(info.headRevision)!;
    if (rev.presence === DELETED) throw new VsnError(0x0009, "file is deleted");
    if (rev.objectSerial === null) return;
    yield* this.materializeStream(rev.objectSerial, chunkSize);
  }
}
