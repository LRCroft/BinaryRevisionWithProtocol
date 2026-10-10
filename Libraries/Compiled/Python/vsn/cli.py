"""VSN-1 command-line inspection tool (Python reference CLI).

Usage: python -m vsn.cli COMMAND file.vsn
Commands: inspect validate verify recover list-files list-revisions
          show-object materialize diff
"""
from __future__ import annotations

import sys

from . import constants as C
from .errors import VsnError
from .recovery import recover


def _usage() -> str:
    return "usage: python -m vsn.cli {inspect,validate,verify,recover,list-files,list-revisions,show-object,materialize} file.vsn"


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 2:
        print(_usage())
        return 2
    cmd, path = argv[0], argv[1]
    try:
        data = open(path, "rb").read()
        from .api import open as open_vsn
        c = open_vsn(data)
        if cmd == "inspect":
            print("container_format_version=%d encoding_version=%d mode=%d" % (
                c.container_format_version, c.encoding_version, c.mode or 0))
            print("records=%d objects=%d" % (len(c.records), len(c.objects)))
        elif cmd == "validate":
            from .validate import validate
            validate(data, "Full")
            print("VALID")
        elif cmd == "recover":
            r = recover(data)
            print("status=%s generation=%d" % (r.status, r.accepted_generation))
        elif cmd == "list-files":
            for fid, rid in c.files():
                print("%s -> %d" % (fid.hex(), rid))
        elif cmd == "list-revisions":
            for rec in c.records:
                if rec.rtype == C.REC_REVISION:
                    print(rec.field(C.FID_REV_ID).value_uvarint)
        elif cmd in ("show-object", "materialize"):
            serial = int(argv[2])
            sys.stdout.buffer.write(c.materialize(serial))
        elif cmd == "verify":
            for o in c.objects:
                c.materialize(o.serial)
            print("VERIFIED")
        else:
            print(_usage())
            return 2
    except VsnError as e:
        print("%s: %s" % (e.name, e.message), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
