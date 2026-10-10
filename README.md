# BinaryRevisionWithProtocol

Binary Revision Protocol (VSN-1) is a canonical binary format for file revisions that enables efficient storage, retrieval, and management of file histories. This repository contains the VSN-1 specification, reference documentation, and implementations across 31 programming languages.

## Current Storage Policy Architecture

VSN-1 uses four canonical storage policies to classify storage representation intent. These policies are stored directly in the container as a `REC_STORAGE_POLICY` record (0x0009) with field ID `FID_STORAGE_POLICY` (0x0901) and a single byte value (1-4):

| Value | Policy | Description |
|-------|--------|-------------|
| `1` | `HIGHLY_VERTICAL` | Maximum storage-efficiency effort within explicit resource and safety limits. Aggressive deduplication, content sharing, and revision-to-revision reuse are permitted. |
| `2` | `VERTICAL` | High storage efficiency with more bounded optimization. Deduplication and content sharing are preferred but bounded; EXTENTS-1 permitted with depth limits. |
| `3` | `HORIZONTAL` | Prefer straightforward representations with limited reuse. Complete content objects preferred; basic deduplication permitted. Limited/shallow EXTENTS only if permitted by ENTERPRISE frozen semantics. |
| `4` | `HIGHLY_HORIZONTAL` | Maximum straightforwardness. DIRECT-1 required for emitted content; EXTENTS-1 forbidden. Reconstruction dependencies forbidden; each object contains complete logical content. |

These policies are implementation-local configuration values and do not appear as wire-mode identifiers. The wire mode constants MODERN and ENTERPRISE are deprecated and kept only for backward compatibility.

## Architecture and Data Lifecycle

A VSN-1 container follows this lifecycle:
1. **Creation**: A container is created with a storage policy (1-4) and optional optimization configuration.
2. **File Operations**: Files can be created, read, updated, deleted, renamed, and listed within the container.
3. **Revisions**: Changes are committed as revisions, each referencing a file tree and metadata.
4. **Commit**: A revision is accepted via a CommitMarker, becoming immutable canonical data.
5. **Storage Policy Encoding**: The selected storage policy is stored as a `REC_STORAGE_POLICY` record in the container header.
6. **Reading**: Containers can be opened, and file content or revision history can be recovered.
7. **Storage Policy Decoding**: The storage policy is read from the `REC_STORAGE_POLICY` record to understand the writer's intent.
8. **Conformance**: Frozen test vectors verify protocol correctness across implementations.

## Quick Start

Here is a minimal example using the C library:

```c
#include "vsn.h"
#include <stdio.h>
#include <string.h>

int main() {
    uint8_t buffer[4096];
    size_t out_len;
    VsnContainer *c = NULL;
    FileId fid;
    const char *content = "Hello, VSN!";

    // Create container with storage policy VERTICAL (2)
    vsn_create(&c, STORAGE_VERTICAL);

    // Create a file
    vsn_create_file(c, "hello.txt", (const uint8_t *)content, strlen(content), &fid);

    // Commit changes
    vsn_commit(c, buffer, sizeof(buffer), &out_len);

      // Output now contains the canonical VSN-1 bytes
    
    fwrite(buffer, 1, out_len, stdout);

    vsn_close(c);
    return 0;
}
Build with: `gcc -o example example.c vsn.c`
Expected output: A VSN-1 container storing the string "Hello, VSN!" with storage policy 2.

## Language Support

The repository provides VSN-1 library implementations for 31 languages. All implementations have been built and verified via the conformance suite. Refer to `Libraries/Compiled/BUILD_MANIFEST.json` for detailed build status, artifacts, and consumer test results.

Implementations are located under `Libraries/<Language>/` (e.g., `Libraries/C/`, `Libraries/Python/`). Each language provides:
- Source code in the canonical directory.
- Compiled artifacts (where applicable) in `Libraries/Compiled/<Language>/`.
- Consumer tests in `Libraries/Consumer/<Language>/` (for 7 languages with independent consumers).
- API documentation in the source or language-specific READMEs.

## Protocol and Conformance

The current VSN-1 protocol invariants include:
- `REC_STORAGE_POLICY = 0x0009` (Storage Policy record type)
- `FID_STORAGE_POLICY = 0x0901` (Storage Policy field ID)
- Storage Policy payload: exactly one byte, valid values 1-4
- Frozen conformance vectors: 5 files (`DIRECT-01.vsn` through `EXT-02-and-EXT-03.vsn`) with SHA-256 hashes recorded in `Libraries/Conformance/corpus/manifest.json`

To run the conformance suite:
1. Ensure Docker is installed and running.
2. Execute: `python Libraries/Conformance/run_conformance.py`
The suite executes all 31 language test suites in containers and reports verification status.

## Build, Test, and Contribute

### Building an Individual Language
Each language's build process is documented in its source directory. Generally:
```bash
# Example for C
cd Libraries/C
gcc -c vsn.c -o libvsn.a   # or vsn.so for shared library
```

### Running Consumer Tests
Independent consumers (where available) are in `Libraries/Consumer/<Language>/`. Consult the language's README for build and test instructions.

### Running the Conformance Suite
```bash
python Libraries/Conformance/run_conformance.py
```

### Artifact Freshness
Per the repository freshness policy: whenever source changes, rebuild affected distributables and run consumer tests. Replace old artifacts only after validation.

## Limitations and Scope

- The VSN-1 protocol defines a binary container format but does not prescribe specific algorithms for deduplication, compression, or similarity search. Storage policies express intent, not guaranteed behavior.
- Not all language implementations provide identical API surface; consult language-specific documentation.
- The repository does not guarantee production readiness for any language implementation; users should evaluate suitability for their use case.
- Historical wire-mode constants (MODERN=0x01, ENTERPRISE=0x02) are deprecated and retained only for backward compatibility with legacy readers.

## License and Project Metadata

This repository does not specify a license. Users must assume all rights are reserved unless otherwise indicated. See the repository URL for updates: https://github.com/LRCroft/BinaryRevisionWithProtocol
