#!/usr/bin/env python3
p = r"C:\CampMember\BinaryRevisionWithProtocol\Libraries\JavaScript-TypeScript\tests\test_vsn_caps.ts"
c = open(p, "r", encoding="utf-8").read()
c = c.replace('    const { VsnContainer } = require("../src/api.js");\n', '')
c = c.replace('    const { VsnContainer } = require("../src/api.js");\r\n', '')
open(p, "w", encoding="utf-8", newline="").write(c)
print("ok" if 'require("../src/api.js")' not in open(p,"r",encoding="utf-8").read() else "FAILED")



# Detect line ending
lf = "\n" if "\r\n" not in c else "\r\n"

old = """function cap19() { // Interop (frozen vectors)
    const vecNames = ["DIRECT-01", "EXT-01"];
    for (const name of vecNames) {
        try {
            const data = readFileSync("../../TestVectors/" + name + ".vsn");
            checkCap(19, data.length > 8 && data.toString("utf8", 0, 4) === "VSN-", name + ": valid header");
            checkCap(19, verifyIntegrity(create()).valid !== false, name + ": integrity ok");
        } catch (e) {
            console.log("SKIP 19 " + name + ": " + e.message);
        }
    }
}""".replace("\n", lf)

new = """function cap19() { // Interop (frozen vectors) — parse + materialize
    const { VsnContainer } = require("../src/api.js");
    const vecNames = ["DIRECT-01", "DIRECT-02", "DIRECT-03", "EXT-01", "EXT-02-and-EXT-03"];
    for (const name of vecNames) {
        const data = readFileSync("../../TestVectors/" + name + ".vsn");
        checkCap(19, data.length > 8, name + ": non-trivial size");
        checkCap(19, data.toString("utf8", 0, 4) === "VSN-", name + ": valid header magic");
        const cont = new VsnContainer(data);
        checkCap(19, cont.records.length >= 1, name + ": at least 1 record");
        checkCap(19, cont.objects.length >= 1, name + ": at least 1 object");
        const first = cont.objects[0];
        const content = cont.materialize(first.serial);
        checkCap(19, content.length >= 0, name + ": materialize succeeded (" + content.length + " bytes)");
    }
    const good = readFileSync("../../TestVectors/DIRECT-01.vsn");
    const bad = Buffer.from(good); bad[0] = 0x42;
    let threw = false;
    try { new VsnContainer(bad); } catch (e) { threw = true; }
    checkCap(19, threw, "corrupted vector rejected");
}""".replace("\n", lf)

if old not in c:
    # Normalize by trying LF
    old_lf = old.replace("\r\n", "\n")
    new_lf = new.replace("\r\n", "\n")
    if old_lf in c:
        c = c.replace(old_lf, new_lf)
    else:
        print("OLD not found")
        raise SystemExit(1)
else:
    c = c.replace(old, new)

with open(p, "w", newline="") as f:
    f.write(c)
print("patched OK")
