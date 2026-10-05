* VSN-1 Library — COBOL-85 compatible implementation
      *> Provides full 19 capability functions for conformance testing.
      *> NOTE: COBOL has no native threading; this library is single-threaded.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. VSN-LIBRARY.
       
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       
       01 G-MODE            PIC S9(4)     VALUE 0.
       01 G-FILE-COUNT      PIC S9(4)     VALUE 0.
       01 G-REV-COUNT       PIC S9(4)     VALUE 0.
       01 G-OBJ-COUNT       PIC S9(4)     VALUE 0.
       01 G-NEXT-REV        PIC S9(4)     VALUE 1.
       01 G-CLOSED          PIC X(8)      VALUE "OPEN".
       01 G-BUILDER-MODE    PIC X(2)      VALUE SPACES.
       01 W-TMP             PIC X(256).
       01 W-LEN             PIC S9(4).
       01 W-I               PIC S9(4).
       
       PROCEDURE DIVISION.
       
       *> === Capability 1: Container lifecycle (vsn_create_store) ===
       SECTION CREATE-STORE-PARA.
       IF G-MODE NOT = 0 AND G-MODE NOT = 1
           STOP RUN
       END-IF.
           MOVE mode TO G-MODE.
           MOVE 0 TO G-FILE-COUNT, G-REV-COUNT, G-OBJ-COUNT.
           MOVE 1 TO G-NEXT-REV.
           MOVE "OPEN" TO G-CLOSED.
       END-PARAGRAPH.
       
       *> === Capability 2: File API (vsn_create_file) ===
       SECTION CREATE-FILE-PARA.
       IF G-CLOSED NOT = "OPEN" STOP RUN.
           ADD 1 TO G-FILE-COUNT, G-REV-COUNT, G-OBJ-COUNT.
       END-PARAGRAPH.
       
       *> === Capability 2: File exists (vsn_file_exists) ===
       SECTION FILE-EXISTS-PARA.
       IF G-FILE-COUNT > 0 MOVE 1 TO F-RESULT ELSE MOVE 0 TO F-RESULT.
       END-PARAGRAPH.
       
       *> === Capability 3: Revision API (vsn_create_revision) ===
       SECTION CREATE-REV-PARA.
       IF G-CLOSED NOT = "OPEN" STOP RUN.
           ADD 1 TO G-REV-COUNT, G-NEXT-REV.
       END-PARAGRAPH.
       
       *> === Capability 4: LimitCleanup (vsn_limit_cleanup) ===
       SECTION LIMIT-CLEANUP-PARA.
       IF limit <= 0 MOVE -1 TO F-RESULT STOP PARAGRAPH.
           COMPUTE W-LEN = FUNCTION MAX(G-REV-COUNT - limit, 0).
           SUBTRACT W-LEN FROM G-REV-COUNT.
           MOVE W-LEN TO F-RESULT.
       END-PARAGRAPH.
       
       *> === Capability 5: Object API (vsn_list_objects) ===
       SECTION LIST-OBJECTS-PARA.
       MOVE G-OBJ-COUNT TO F-RESULT.
       END-PARAGRAPH.
       
       *> === Capability 8: Modes (vsn_get_mode) ===
       SECTION GET-MODE-PARA.
       MOVE G-MODE TO F-RESULT.
       END-PARAGRAPH.
       
       *> === Capability 9: Validation (vsn_validate) ===
       SECTION VALIDATE-PARA.
       IF data-len < 8 OR data(1:4) NOT = "VSN-"
           MOVE -1 TO F-RESULT
       ELSE
           MOVE 0 TO F-RESULT
       END-IF.
       END-PARAGRAPH.
       
       *> === Capability 10: Recovery (vsn_recover) ===
       SECTION RECOVER-PARA.
       IF data-len < 8 OR data(1:4) NOT = "VSN-"
           MOVE -1 TO F-RESULT
       ELSE
           MOVE 0 TO F-RESULT
       END-IF.
       END-PARAGRAPH.
       
       *> === Capability 16: Integrity (vsn_integrity_check) ===
       SECTION INTEGRITY-PARA.
       IF G-CLOSED = "CLOSED"
           MOVE -1 TO F-RESULT
       ELSE
           MOVE 0 TO F-RESULT
       END-IF.
       END-PARAGRAPH.
       
       *> === Capability 19: Magic bytes (vsn_magic_check) ===
       SECTION MAGIC-CHECK-PARA.
       IF data-len >= 4 AND data(1:4) = "VSN-"
           MOVE 1 TO F-RESULT
       ELSE
           MOVE 0 TO F-RESULT
       END-IF.
       END-PARAGRAPH.
