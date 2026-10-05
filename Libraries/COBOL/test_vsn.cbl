       IDENTIFICATION DIVISION.
       PROGRAM-ID. TEST-VSN.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 OP-ARG PIC S9(9) COMP-5 VALUE 0.
       01 A1-ARG PIC S9(9) COMP-5 VALUE 0.
       01 A2-ARG PIC S9(9) COMP-5 VALUE 0.
       01 BUF PIC X(64) VALUE SPACES.
       01 N PIC 9(2) VALUE 0.
       01 PASSED PIC 9(4) VALUE 0.
       01 FAILED PIC 9(4) VALUE 0.
       01 CAP-OK PIC 9 VALUE 0.
       PROCEDURE DIVISION.
       MAIN.
           PERFORM VARYING N FROM 1 BY 1 UNTIL N > 19
               PERFORM RUN-CAP
               IF CAP-OK = 1
                   ADD 1 TO PASSED
                   DISPLAY "PASS " N
               ELSE
                   ADD 1 TO FAILED
                   DISPLAY "FAIL " N
               END-IF
           END-PERFORM
           DISPLAY "SUMMARY " PASSED "/19"
           IF FAILED > 0 MOVE 1 TO RETURN-CODE
           ELSE MOVE 0 TO RETURN-CODE END-IF
           STOP RUN.
       CALL-LIB.
           CALL "VSN-LIBRARY" USING OP-ARG A1-ARG A2-ARG BUF
           END-CALL.
       RUN-CAP.
           MOVE 1 TO CAP-OK
           EVALUATE N
           WHEN 1
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 2 TO A1-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 2 MOVE 0 TO CAP-OK END-IF
               MOVE 2 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
           WHEN 2
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 3 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT > 0 MOVE 0 TO CAP-OK END-IF
               MOVE 6 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
               MOVE 5 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 6 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 0 MOVE 0 TO CAP-OK END-IF
           WHEN 3
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 3 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 4 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 4 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 7 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT >= 3 MOVE 0 TO CAP-OK END-IF
           WHEN 4
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 3 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 4 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 4 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 4 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 4 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 4 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 8 TO OP-ARG
               MOVE 3 TO A1-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 3 MOVE 0 TO CAP-OK END-IF
               MOVE 8 TO OP-ARG
               MOVE 0 TO A1-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = -1 MOVE 0 TO CAP-OK END-IF
           WHEN 5
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 3 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 9 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT >= 1 MOVE 0 TO CAP-OK END-IF
               MOVE 25 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT >= 1 MOVE 0 TO CAP-OK END-IF
           WHEN 6
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 11 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 0 MOVE 0 TO CAP-OK END-IF
               MOVE 12 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
               MOVE 12 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 2 MOVE 0 TO CAP-OK END-IF
           WHEN 7
               MOVE 27 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
               MOVE 28 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 2 MOVE 0 TO CAP-OK END-IF
           WHEN 8
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 10 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
               MOVE 1 TO OP-ARG
               MOVE 2 TO A1-ARG
               PERFORM CALL-LIB
               MOVE 10 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 2 MOVE 0 TO CAP-OK END-IF
           WHEN 9
               MOVE 18 TO OP-ARG
               MOVE 8 TO A1-ARG
               PERFORM CALL-LIB
               MOVE 13 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 0 MOVE 0 TO CAP-OK END-IF
               MOVE "XXXX" TO BUF(1:4)
               MOVE 13 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = -1 MOVE 0 TO CAP-OK END-IF
           WHEN 10
               MOVE 18 TO OP-ARG
               MOVE 8 TO A1-ARG
               PERFORM CALL-LIB
               MOVE 14 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 0 MOVE 0 TO CAP-OK END-IF
               MOVE "XXXX" TO BUF(1:4)
               MOVE 14 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = -1 MOVE 0 TO CAP-OK END-IF
           WHEN 11
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 3 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 16 TO OP-ARG
               MOVE 0 TO A1-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
               MOVE 16 TO OP-ARG
               MOVE 1 TO A1-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 0 MOVE 0 TO CAP-OK END-IF
           WHEN 12
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 17 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
               MOVE 1 TO OP-ARG
               MOVE 7 TO A1-ARG
               PERFORM CALL-LIB
               MOVE 17 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 0 MOVE 0 TO CAP-OK END-IF
           WHEN 13
               MOVE 18 TO OP-ARG
               MOVE 8 TO A1-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 8 MOVE 0 TO CAP-OK END-IF
               IF BUF(1:4) NOT = "VSN-" MOVE 0 TO CAP-OK END-IF
               MOVE 19 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
               MOVE "XXXX" TO BUF(1:4)
               MOVE 19 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = -1 MOVE 0 TO CAP-OK END-IF
           WHEN 14
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 20 TO OP-ARG
               MOVE 4 TO A1-ARG
               MOVE "ABCD" TO BUF(1:4)
               PERFORM CALL-LIB
               MOVE 20 TO OP-ARG
               MOVE 3 TO A1-ARG
               MOVE "EFG" TO BUF(1:3)
               PERFORM CALL-LIB
               MOVE 21 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 7 MOVE 0 TO CAP-OK END-IF
           WHEN 15
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 23 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 0 MOVE 0 TO CAP-OK END-IF
               MOVE 1 TO OP-ARG
               MOVE 9 TO A1-ARG
               PERFORM CALL-LIB
               MOVE 23 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = -1 MOVE 0 TO CAP-OK END-IF
           WHEN 16
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 22 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 0 MOVE 0 TO CAP-OK END-IF
               MOVE 2 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 22 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = -1 MOVE 0 TO CAP-OK END-IF
           WHEN 17
               MOVE 1 TO OP-ARG A1-ARG
               PERFORM CALL-LIB
               MOVE 3 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 3 TO OP-ARG
               PERFORM CALL-LIB
               MOVE 24 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 2 MOVE 0 TO CAP-OK END-IF
               MOVE 25 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT >= 2 MOVE 0 TO CAP-OK END-IF
           WHEN 18
               MOVE 26 TO OP-ARG
               MOVE 2 TO A1-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 2 MOVE 0 TO CAP-OK END-IF
               MOVE 10 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 2 MOVE 0 TO CAP-OK END-IF
               MOVE 26 TO OP-ARG
               MOVE 1 TO A1-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
           WHEN 19
               MOVE 18 TO OP-ARG
               MOVE 8 TO A1-ARG
               PERFORM CALL-LIB
               MOVE 15 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 1 MOVE 0 TO CAP-OK END-IF
               MOVE "XXXX" TO BUF(1:4)
               MOVE 15 TO OP-ARG
               PERFORM CALL-LIB
               IF A2-ARG NOT = 0 MOVE 0 TO CAP-OK END-IF
           WHEN OTHER
               MOVE 0 TO CAP-OK
           END-EVALUATE.
