# VSN COBOL Library

Canonical implementation (Libraries/COBOL).

Files:
  vsn_lib.cbl   - VSN library, all 19 CAP APIs + Storage Policy (ops 29/30)
  test_vsn.cbl  - conformance test (19 CAPs + Storage Policy wire conformance P01-P17)

Compile (GnuCOBOL, free-format):
  cobc -x -free test_vsn.cbl vsn_lib.cbl -o test_vsn

Run:
  ./test_vsn

Expected output:
  CAP 01..19 PASS
  SP 01-12 PASS assertions=0047 storage policy wire conformance
  SUMMARY 0019/19
  exit code 0

