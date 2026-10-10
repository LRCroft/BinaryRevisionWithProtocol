import {
  REC_FILE_IDENTITY, REC_REVISION, REC_FILE_HEAD, REC_CONTENT_OBJECT,
  REC_COMMIT_MARKER, REC_MODE_DECLARATION,
  FID_FILE_ID, FID_REV_ID, FID_REV_FILE_ID, FID_REV_OBJECT_SERIAL,
  FID_REV_PATH, FID_REV_PRESENCE, FID_HEAD_FILE_ID, FID_HEAD_REV_ID,
  FID_OBJECT_SERIAL, FID_OBJECT_SIZE, FID_COMMIT_GENERATION, FID_MODE,
  MODE_MODERN, PRESENT, REP_DIRECT_1, REP_EXTENTS_1, REP_VERSION_1,
} from "./constants.js";
import { putUvarint, VsnError } from "./primitives.js";
import { encode, direct1Descriptor } from "./writer.js";
import type { EncodedRecord, EncodedObject } from "./writer.js";
import {
  parseObjectHeader, materializeDirect, materializeExtents,
} from "./representations.js";

/** Build a VSN-1 container incrementally with explicit, deterministic identities. */
export class ContainerBuilder {
  mode: number;
  readonly records: EncodedRecord[] = [];
  readonly objects: EncodedObject[] = [];
  private fileIds = new Set<string>();
  private revisionIds = new Set<number>();
  private objectSerials = new Set<number>();
  private nextObjectSerial = 1;

  constructor(mode: number = MODE_MODERN) { this.mode = mode; }

  /** Add a FileIdentity record (FileId is 16 bytes, FieldId 0x0101). */
  addFile(fileId: Buffer): this {
    if (fileId.length !== 16) throw new Error("FileId must be 16 bytes");
    const key = fileId.toString("hex");
    if (this.fileIds.has(key)) throw new Error("duplicate FileId");
    this.fileIds.add(key);
    this.records.push({ rtype: REC_FILE_IDENTITY, fields: [{ fid: FID_FILE_ID, value: fileId }] });
    return this;
  }

  /** Add a Revision record; the FileId must already be declared. */
  addRevision(
    fileId: Buffer, revisionId: number | bigint, objectSerial: number | bigint | null = null,
    path: string | null = null, presence: number = PRESENT,
  ): this {
    const key = fileId.toString("hex");
    if (!this.fileIds.has(key)) throw new Error("FileId not declared");
    const rid = Number(revisionId);
    if (this.revisionIds.has(rid)) throw new Error("duplicate RevisionId");
    this.revisionIds.add(rid);
    const fields = [
      { fid: FID_REV_ID, value: putUvarint(rid) },
      { fid: FID_REV_FILE_ID, value: fileId },
    ];
    if (objectSerial !== null)
      fields.push({ fid: FID_REV_OBJECT_SERIAL, value: putUvarint(Number(objectSerial)) });
    if (path !== null) fields.push({ fid: FID_REV_PATH, value: Buffer.from(path, "utf8") });
    fields.push({ fid: FID_REV_PRESENCE, value: Buffer.from([presence]) });
    this.records.push({ rtype: REC_REVISION, fields });
    return this;
  }

  /** Add a ContentObject record + DIRECT-1 object; returns the ObjectSerial. */
  addObject(content: Buffer, serial?: number): number {
    const sid = serial ?? this.nextObjectSerial;
    if (serial === undefined) this.nextObjectSerial += 1;
    if (sid >= this.nextObjectSerial) this.nextObjectSerial = sid + 1;
    if (this.objectSerials.has(sid)) throw new Error("duplicate ObjectSerial");
    this.objectSerials.add(sid);
    this.records.push({
      rtype: REC_CONTENT_OBJECT,
      fields: [
        { fid: FID_OBJECT_SERIAL, value: putUvarint(sid) },
        { fid: FID_OBJECT_SIZE, value: putUvarint(content.length) },
      ],
    });
    this.objects.push({ serial: BigInt(sid), descriptor: direct1Descriptor(content) });
    return sid;
  }

  /**
   * Materialize an object descriptor to its LOGICAL content.
   * SR-29: declared size 0x0511 is the expected logical content length in
   * bytes (validation metadata over logical content, never representation bytes).
   */
  private logicalContent(descriptor: Buffer, visited = new Set<string>()): Buffer {
    const key = descriptor.toString("hex");
    if (visited.has(key)) throw new VsnError(0x000C, "dependency cycle");
    visited.add(key);
    const { identity, version, remainder } = parseObjectHeader(descriptor);
    if (identity === REP_DIRECT_1 && version === REP_VERSION_1)
      return materializeDirect(remainder);
    if (identity === REP_EXTENTS_1 && version === REP_VERSION_1)
      return materializeExtents(remainder, (s) => {
        const entry = this.objects.find((o) => o.serial === s);
        if (!entry) throw new VsnError(0x0008, `missing object ${s}`);
        return this.logicalContent(entry.descriptor, new Set(visited));
      });
    throw new VsnError(0x0006, `unsupported representation 0x${identity.toString(16)} v${version}`);
  }

  /** Add a ContentObject record + an explicit descriptor (e.g. EXTENTS-1). */
  addObjectRaw(descriptor: Buffer, serial?: number): number {
    const sid = serial ?? this.nextObjectSerial;
    if (serial === undefined) this.nextObjectSerial += 1;
    if (sid >= this.nextObjectSerial) this.nextObjectSerial = sid + 1;
    if (this.objectSerials.has(sid)) throw new Error("duplicate ObjectSerial");
    this.objectSerials.add(sid);
    this.objects.push({ serial: BigInt(sid), descriptor });
    // 0x0511 is the LOGICAL content length (SR-29), never representation bytes.
    // It is optional (SR-27): omit it when the logical length cannot be
    // resolved yet (missing dependency, cycle, unsupported representation).
    const fields = [{ fid: FID_OBJECT_SERIAL, value: putUvarint(sid) }];
    try {
      fields.push({ fid: FID_OBJECT_SIZE, value: putUvarint(this.logicalContent(descriptor).length) });
    } catch {
      /* 0x0511 omitted: fully valid under SR-27 */
    }
    this.records.push({ rtype: REC_CONTENT_OBJECT, fields });
    return sid;
  }

  /** Add a FileHead record; FileId and RevisionId must already be declared. */
  setHead(fileId: Buffer, revisionId: number | bigint): this {
    const key = fileId.toString("hex");
    if (!this.fileIds.has(key)) throw new Error("FileId not declared");
    const rid = Number(revisionId);
    if (!this.revisionIds.has(rid)) throw new Error("RevisionId not declared");
    this.records.push({
      rtype: REC_FILE_HEAD,
      fields: [
        { fid: FID_HEAD_FILE_ID, value: fileId },
        { fid: FID_HEAD_REV_ID, value: putUvarint(rid) },
      ],
    });
    return this;
  }

  /** Produce canonical bytes. ModeDeclaration is prepended, CommitMarker is
   *  appended, and the trailer canonical count excludes ModeDeclaration (GR-13). */
  build(generation: number | bigint = 1): Buffer {
    const records: EncodedRecord[] = [
      { rtype: REC_MODE_DECLARATION, fields: [{ fid: FID_MODE, value: Buffer.from([this.mode]) }] },
      ...this.records,
      { rtype: REC_COMMIT_MARKER, fields: [{ fid: FID_COMMIT_GENERATION, value: putUvarint(Number(generation)) }] },
    ];
    return encode(this.mode, records, this.objects, Number(generation));
  }
}