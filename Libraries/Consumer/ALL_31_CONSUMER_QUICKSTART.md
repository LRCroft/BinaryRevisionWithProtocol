# VSN-1 Consumer Quickstart — 2026-10-10

How to consume the library through its public API. The 7 languages below ship an independent consumer under
`Libraries/Consumer/<Lang>/` (public interface only). All other languages are consumed via their package/source (see ALL_31_PACKAGE_EXPORT_STATUS.md).

## Python (via `sys.path`; not pip-installable yet)
```
import sys; sys.path.insert(0, "Libraries/Python")
import vsn
s = vsn.VsnStore.create(); f = s.create_file("a.txt", b"data")
ok = vsn.validate_container(s.to_bytes(), "Full") == []
```

## C# (dotnet project reference to `Libraries/CSharp/Vsn`)
```
var s = VsnStore.Create(); VsnStore.Create(VsnStore.StoragePolicy.Vertical);
```

## Go (module `replace` to `../Go`)
```
s, _ := vsn.Create(vsn.StoragePolicyVertical)
```

## Java (compiled against `../Java/VsnLib.java`)
```
var s = VsnLib.create(VsnLib.StoragePolicy.VERTICAL);
```

## JavaScript-TypeScript (`vsn-typescript`, CJS or ESM)
```
const { VsnStore } = require("vsn-typescript");
const s = new VsnStore(); s.createFile("a.txt", Buffer.from("data"));
```

## Rust (path dep `vsn-rust`)
```
let s = vsn_rust::Store::with_policy(vsn_rust::StoragePolicy::Vertical);
```

## C (link `vsn.c` / include `vsn.h`)
```
VsnContainer *c = vsn_create_with_policy(STORAGE_VERTICAL);
```

Run any consumer: see `ALL_31_CONSUMER_TEST_RESULTS.md` for toolchain + exit-code evidence.
