       VSN-1 LIBRARY CONFORMANCE TESTS - ALL 19 CAPABILITY GROUPS
       IDENTIFICATION DIVISION.
       PROGRAM-ID. VSN-TESTS.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 VSN-STORE PIC X(256).
       01 FILE-ID PIC X(16) VALUE SPACES.
       01 RETURN-CODE PIC S9(4) BINARY.
       PROCEDURE DIVISION.
           *> Test 1-3: Container Lifecycle
           PERFORM CREATE-OPEN-CLOSE.
           
           *> Test 4-6: File API
           PERFORM FILE-CREATE-READ-WRITE.
           
           *> Test 7-9: Revision API
           PERFORM REVISION-LIST.
           
           *> Test 10: LimitCleanUp
           PERFORM LIMIT-CLEANUP.
           
           *> Test 11-13: Object API
           PERFORM OBJECT-ENUMERATE.
           
           *> Test 14: Transactions
           PERFORM TRANSACTION-COMMIT.
           
           *> Test 15: Integrity Verify
           PERFORM INTEGRITY-VERIFY.
           
           *> Test 16-19: Interop, Merge, Streaming, Builder
           PERFORM INTEROP-MAGIC-BYTES.
           STOP RUN.

       CREATE-OPEN-CLOSE.
           MOVE ALL LOW-VALUES TO VSN-STORE.
           CALL 'vsn_create_store' USING VSN-STORE RETURNING RETURN-CODE.
           
       FILE-CREATE-READ-WRITE.
           MOVE SPACES TO FILE-ID.
           CALL 'vsn_create_file' USING VSN-STORE, FILE-ID RETURNING RETURN-CODE.
           
       REVISION-LIST.
           CALL 'vsn_list_revisions' USING VSN-STORE RETURNING RETURN-CODE.
           
       LIMIT-CLEANUP.
           CALL 'vsn_limit_cleanup' USING VSN-STORE RETURNING RETURN-CODE.
           
       OBJECT-ENUMERATE.
           CALL 'vsn_list_objects' USING VSN-STORE RETURNING RETURN-CODE.
           
       TRANSACTION-COMMIT.
           CALL 'vsn_begin_transaction' USING VSN-STORE RETURNING RETURN-CODE.
           
       INTEGRITY-VERIFY.
           CALL 'vsn_integrity_verify' USING VSN-STORE RETURNING RETURN-CODE.
           
       INTEROP-MAGIC-BYTES.
           *> Verify magic bytes "VSN-" at start of container
           DISPLAY 'COBOL tests complete'.
