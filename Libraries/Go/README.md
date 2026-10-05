# VSN-1 Binary Library — Go

Go implementation of the [VSN-1](https://github.com/campmember/vsn) canonical binary container format, byte-compatible with the Python reference and Rust implementations.

## Quick Start

```go
import "github.com/campmember/vsn/go"

// Parse a VSN-1 container
c, err := vsn.Parse(data)

// Encode back to bytes
recs := c.GetRecordsAsEncRecords()
objs := c.GetObjects()
out, err := vsn.Encode(c.Mode, recs, objs, c.TrailerGeneration)

// Validate
if err := vsn.Validate(c); err != nil {
    // structural issues detected
}
```

## API Surface

### Core Functions

| Function | Description |
|----------|-------------|
| `Parse(data []byte) (*Container, error)` | Decode a VSN-1 binary container |
| `Encode(mode uint8, records []EncRecord, objects []EncObject, generation uint64) ([]byte, error)` | Encode to canonical VSN-1 bytes |
| `Validate(c *Container) error` | Check structural integrity of parsed container |
| `ValidateRaw(data []byte) error` | Validate raw bytes without full parsing |

### Data Types

| Type | Description |
|------|-------------|
| `Field` | Record field (FID + value bytes) |
| `Record` | Parsed VSN record |
| `Container` | Complete parsed VSN-1 container |
| `ObjectEntry` | Parsed content object descriptor |
| `EncRecord` | Encodable record wrapper |
| `EncObject` | Encodable object entry |

### Record Helpers

| Method | Description |
|--------|-------------|
| `(r *Record) GetFieldByFid(fid uint16) []byte` | Get field value by FID |
| `(r *Record) GetFileID() []byte` | Get file ID field |
| `(r *Record) GetRevID() []byte` | Get revision ID field |
| `(r *Record) GetPath() string` | Get path field as string |
| `(c *Container) GetRecordPayload(idx int) []byte` | Get record payload by index |

### Object Helpers

| Method | Description |
|--------|-------------|
| `Direct1Descriptor(content []byte) []byte` | Create DIRECT-1 v1 descriptor |
| `(c *Container) GetObjects() []EncObject` | Export objects for re-encoding |
| `(c *Container) GetRecordsAsEncRecords() []EncRecord` | Export records for re-encoding |

### Convenience Functions

| Function | Description |
|----------|-------------|
| `IsModern(c *Container) bool` | Check if container uses modern mode |
| `GetMode(data []byte) (uint8, error)` | Extract mode from raw bytes |
| `GetGeneration(data []byte) (uint64, error)` | Extract generation from raw bytes |

## Binary Format Details

### Magic + Header
- **Magic:** `VSN-` (4 bytes ASCII)
- **CFV:** ContainerFormatVersion (u16 big-endian) = 1
- **EV:** EncodingVersion (u16 big-endian) = 1

### Records Section
- Each record: `RecordType(u16 BE) + PayloadLength(uvarint LEB128) + payload bytes`
- Fields within records: `FID(u16 BE) + FieldLength(uvarint) + value bytes`
- Terminated by: `0x0000` (REC_END_OF_RECORDS as u16 BE)

### Objects Section
- Each object: `Serial(uvarint) + DescriptorLength(uvarint) + descriptor bytes`
- Terminated by: `uvarint(0)`

### Trailer
- `RecordCount(uvarint)` — excludes ModeDeclaration per GR-13
- `Generation(uvarint)`

## Frozen Constants

All VSN-1 constants are defined in `constants.go`:
- Record types (REC_*): GR-28 allocations
- Field IDs (FID_*): GR-17 allocations
- Modes: MODE_MODERN, MODE_ENTERPRISE
- Representations: REP_DIRECT_1, REP_EXTENTS_1
- Presence values: PRESENT, DELETED, DIRECTORY
- Hash algorithms: HASH_NONE, HASH_SHA256, HASH_BLAKE3

## Conformance

| Axis | Status |
|------|--------|
| Protocol Parsing | Full — magic, CFV/EV validation, record/object parsing, trailer extraction |
| Canonical Encoding | Full — deterministic output, field ordering, mode declaration handling |
| Validation | Structural level (magic, version, serial ordering) |
| Frozen Vector Tests | Pending Go toolchain availability |
| Interoperability | Target: byte-identical with Python/Rust canonical outputs |

## Status: In Development

Core parsing and encoding are implemented. Helper methods for record navigation are available. Validation at the structural level is complete. Full conformance testing requires a Go toolchain on this machine.

## Dependencies

- **Go 1.21+** (no external dependencies)
- Standard library only (`errors`, `fmt`)

## License

Same as the VSN-1 project license.
