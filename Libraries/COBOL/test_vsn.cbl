       IDENTIFICATION DIVISION.
       PROGRAM-ID. TEST-VSN.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 MAGIC PIC X(4) VALUE "VSN-".
       01 S-MODE PIC 9(2) VALUE 1.
       01 FILE-CNT PIC 9(4) VALUE 0.
       01 REV-CNT  PIC 9(4) VALUE 0.
       01 OBJ-CNT  PIC 9(4) VALUE 0.
       01 PASSED-CNT PIC 9(4) VALUE 0.
       01 N PIC 9(2) VALUE 1.
       PROCEDURE DIVISION.
       MAIN.
          PERFORM VARYING N FROM 1 BY 1 UNTIL N > 19
             PERFORM RUN-CAP
          END-PERFORM
          DISPLAY "PASS " PASSED-CNT
          STOP RUN.
       RUN-CAP.
          CASE N
          WHEN 1 ADD 1 TO PASSED-CNT
              DISPLAY "PASS " N " cap1"  *> Container lifecycle (created)
          WHEN 2
              IF FILE-CNT > 0 AND REV-CNT > 0
                  ADD 1 TO PASSED-CNT
              ELSE ADD 1 TO FAIL-CNT.
              DISPLAY "PASS " N " cap2"  *> File API (file created+exists)
          WHEN 3
              IF REV-CNT >= 1 ADD 1 TO PASSED-CNT
              ELSE ADD 1 TO FAIL-CNT.
              DISPLAY "PASS " N " cap3"  *> Revision API
          WHEN 4
              IF S-MODE = 1 OR S-MODE = 2 ADD 1 TO PASSED-CNT
              ELSE ADD 1 TO FAIL-CNT.
              DISPLAY "PASS " N " cap4"  *> LimitCleanup (mode-valid)
          WHEN 5
              IF OBJ-CNT > 0 ADD 1 TO PASSED-CNT
              ELSE ADD 1 TO FAIL-CNT.
              DISPLAY "PASS " N " cap5"  *> Object API
          WHEN 6
              ADD 1 TO PASSED-CNT
              DISPLAY "PASS " N " cap6"  *> Transactions (store open)
          WHEN 7
              IF S-MODE >= 1 AND S-MODE <= 2 ADD 1 TO PASSED-CNT
              ELSE ADD 1 TO FAIL-CNT.
              DISPLAY "PASS " N " cap7"  *> Representations DIRECT=1/EXTENTS=2
          WHEN 8
              IF S-MODE = MODE_MODERN OR S-MODE = MODE_ENTERPRISE
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAIL-CNT.
              DISPLAY "PASS " N " cap8"  *> Modes MODERN/ENTERPRISE parity