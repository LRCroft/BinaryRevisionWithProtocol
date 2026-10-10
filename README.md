# BinaryRevisionWithProtocol

**VSN — Binary Revision Protocol**

File history that works with any binary format.

VSN defines a standardized binary container for storing file revisions. Instead of reinventing revision history in every application, VSN provides a shared foundation that works across 31 programming languages. Choose your storage strategy—from maximum efficiency to straightforward self-contained content—and let VSN handle the binary format details.

## What is VSN?

Imagine tracking changes to a file: from version A to version B to version C. VSN gives you a reliable binary container for storing and recovering that history. The format defines how revisions are encoded, while implementations decide how to optimize storage based on your selected policy.

- **Storage policies** express your intent: prioritize storage efficiency or favor simple, self-contained representations.
- **Cross-language compatibility** means a VSN file written in Python can be read in C, Java, or any of the 31 supported languages.
- **Frozen test vectors** ensure implementations stay compatible with the canonical format.

## The Four Storage Policies

VSN uses four canonical storage policies to guide how implementations store revisions. These are configuration values—not wire-mode identifiers—and map directly to your priorities:

- **HIGHLY_VERTICAL (1)**: Push storage efficiency to implementation limits. Aggressive deduplication and sharing.
- **VERTICAL (2)**: Favor storage efficiency with bounded optimization. Preferred sharing within defined limits.
- **HORIZONTAL (3)**: Prefer straightforward storage. Complete content objects; limited reuse.
- **HIGHLY_HORIZONTAL (4)**: Maximum straightforwardness. Each object contains full logical content; minimal dependencies.

*Choose the strategy that fits your workload—from compact revision history to simple, snapshots.*

## Why 31 Languages?

The repository includes VSN implementations for 31 programming languages, from systems languages like C and Rust to higher-level languages like Python and JavaScript. This isn’t just about source code—each implementation has been built, tested against the conformance suite, and verified to read and write the shared binary format.

Explore the implementation for your language under `Libraries/<Language>/`. Build outputs and test results are documented in the [compiled artifacts manifest](Libraries/Compiled/BUILD_MANIFEST.json).

## How VSN Works

At a high level, VSN follows a simple lifecycle:

1. **Create** a container with your chosen storage policy.
2. **Add or update** files as your application evolves.
3. **Commit** changes to establish an accepted revision.
4. **Open** the container later to recover any past revision.

The format defines how this lifecycle is encoded in binary. Implementations handle the details—like mapping storage policies to internal optimizations—while ensuring any VSN file can be read by any other implementation.

## Quick Start

Here’s a minimal example using the C library:

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
    vsn_create_with_policy(&c, STORAGE_VERTICAL);

    // Create a file
    vsn_create_file(c, "hello.txt", (const uint8_t *)content, strlen(content), &fid);

    // Commit changes
    vsn_commit(c, buffer, sizeof(buffer), &out_len);

    // Output now contains the canonical VSN bytes
    fwrite(buffer, 1, out_len, stdout);

    vsn_close(c);
    return 0;
}
```
Build and run:
```bash
# From the repository root
gcc -o example Libraries/C/vsn.c example.c
./example > hello.vsn  # Creates a VSN container
```

## Where to Go Next

- **Protocol specification**: Details on the binary format, records, and invariants → [`Libraries/Documentation/VSN1_Protocol_Specification.md`](Libraries/Documentation/VSN1_Protocol_Specification.md)
- **Architecture overview**: Layers, design principles, and the storage policy → optimization configuration hierarchy → [`Libraries/Documentation/VSN1_Architecture.md`](Libraries/Documentation/VSN1_Architecture.md)
- **API reference**: Language-specific usage and build instructions → See each language’s directory under [`Libraries/`](Libraries/)
- **Conformance and test vectors**: How we verify compatibility across languages → [`Libraries/Conformance/`](Libraries/Conformance/)
- **Compiled artifacts**: Build status and output files for all 31 languages → [`Libraries/Compiled/BUILD_MANIFEST.json`](Libraries/Compiled/BUILD_MANIFEST.json)

## Testing and Conformance

Run the full conformance suite to check implementation compatibility:
```bash
python Libraries/Conformance/run_conformance.py
```
This executes test suites for all 31 languages in Docker containers and verifies they can read and write the canonical format using the frozen test vectors.

## Contributing

We welcome your interest! Whether you’re looking to:
- Try VSN in your language of choice
- Report an issue or inconsistency
- Improve documentation or examples
- Suggest enhancements to the storage policy guidance

Start by exploring the [`Libraries/`](Libraries/) directory for your language. Check the [issue tracker](https://github.com/LRCroft/BinaryRevisionWithProtocol/issues) for existing discussions, and feel free to open a new issue or pull request.

## License

This repository does not currently specify a license. Unless otherwise indicated, all rights are reserved. Please check the repository for any updates regarding licensing.

