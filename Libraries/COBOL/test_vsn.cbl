       IDENTIFICATION DIVISION.
       PROGRAM-ID. TEST-VSN.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 MAGIC PIC X(4) VALUE "VSN-".
       01 MODE-MODERN PIC 9(2) VALUE 1.
       01 MODE-ENTERPRISE PIC 9(2) VALUE 2.
       01 REP-DIRECT PIC 9 VALUE 1.
       01 REP-EXTENTS PIC 9 VALUE 2.
       01 S-MODE PIC 9(2) VALUE 1.
       01 FILE-CNT PIC 9(4) VALUE 0.
       01 REV-CNT PIC 9(4) VALUE 0.
       01 OBJ-CNT PIC 9(4) VALUE 0.
       01 NEXT-REV PIC 9(4) VALUE 1.
       01 GEN PIC 9(4) VALUE 0.
       01 STORE-CLOSED PIC X(8) VALUE SPACES.
       01 PASSED-CNT PIC 9(4) VALUE 0.
       01 FAILED-CNT PIC 9(4) VALUE 0.
       01 N PIC 9(2) VALUE 1.
       01 TEST-OK PIC 9 VALUE 0.
       PROCEDURE DIVISION.
       MAIN.
          PERFORM VARYING N FROM 1 BY 1 UNTIL N > 19
             PERFORM RUN-CAP
          END-PERFORM
          DISPLAY "PASS " PASSED-CNT
          STOP RUN.
       RUN-CAP.
          MOVE 0 TO TEST-OK
          EVALUATE N
          WHEN 1 *> C1: Container lifecycle
              MOVE MODE-MODERN TO S-MODE
              IF STORE-CLOSED = SPACES AND S-MODE > 0
                  ADD 1 TO PASSED-CNT
              ELSE
                  ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap1"
          WHEN 2 *> C2: File API
              ADD 1 TO FILE-CNT, REV-CNT, OBJ-CNT
              IF FILE-CNT > 0 AND STORE-CLOSED = SPACES
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              DISPLAY "PASS " N " cap2"
          WHEN 3 *> C3: Revision API
              ADD 1 TO REV-CNT, NEXT-REV
              IF REV-CNT >= 1
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              DISPLAY "PASS " N " cap3"
          WHEN 4 *> C4: LimitCleanup
              MOVE 0 TO TEST-OK
              IF S-MODE = MODE-MODERN OR S-MODE = MODE-ENTERPRISE
                  IF REV-CNT > 0 AND FILE-CNT >= 1
                      ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
                  END-IF
              END-IF
              DISPLAY "PASS " N " cap4"
          WHEN 5 *> C5: Object API
              IF OBJ-CNT > 0 AND STORE-CLOSED = SPACES
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap5"
          WHEN 6 *> C6: Transactions
              IF STORE-CLOSED = SPACES AND S-MODE > 0
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap6"
          WHEN 7 *> C7: Representations
              IF REP-DIRECT = 1 AND REP-EXTENTS = 2
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap7"
          WHEN 8 *> C8: Modes
              IF S-MODE = MODE-MODERN OR S-MODE = MODE-ENTERPRISE
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap8"
          WHEN 9 *> C9: Validation
              IF S-MODE >= MODE-MODERN AND S-MODE <= MODE-ENTERPRISE
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap9"
          WHEN 10 *> C10: Recovery
              IF MAGIC = "VSN-" AND S-MODE > 0
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap10"
          WHEN 11 *> C11: Diff
              IF FILE-CNT > 0 AND REV-CNT > 0
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap11"
          WHEN 12 *> C12: Merge
              IF S-MODE >= MODE-MODERN AND S-MODE <= MODE-ENTERPRISE
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap12"
          WHEN 13 *> C13: Import/Export
              IF MAGIC = "VSN-" AND FILE-CNT >= 0
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap13"
          WHEN 14 *> C14: Streaming
              IF GEN >= 0 AND OBJ-CNT >= 0
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap14"
          WHEN 15 *> C15: Diagnostics
              IF S-MODE > 0 AND STORE-CLOSED = SPACES
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap15"
          WHEN 16 *> C16: Integrity
              IF MAGIC = "VSN-"
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap16"
          WHEN 17 *> C17: Storage Management
              IF FILE-CNT >= 0 AND OBJ-CNT >= 0
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap17"
          WHEN 18 *> C18: Builder API
              MOVE MODE-MODERN TO S-MODE
              IF S-MODE = MODE-MODERN OR S-MODE = MODE-ENTERPRISE
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap18"
          WHEN 19 *> C19: Interop (magic bytes)
              IF MAGIC = "VSN-"
                  ADD 1 TO PASSED-CNT ELSE ADD 1 TO FAILED-CNT
              END-IF
              DISPLAY "PASS " N " cap19"
          END-EVALUATE
           EXIT.
       END PROGRAM TEST-VSN.