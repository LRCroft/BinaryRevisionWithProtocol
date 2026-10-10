       IDENTIFICATION DIVISION.
       PROGRAM-ID. CONSUMER.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 OP-ARG PIC S9(9) COMP-5 VALUE 0.
       01 A1-ARG PIC S9(9) COMP-5 VALUE 0.
       01 A2-ARG PIC S9(9) COMP-5 VALUE 0.
       01 BUF PIC X(64) VALUE SPACES.
       01 P PIC 9(3) VALUE 0.
       01 SP-OK PIC 9 VALUE 1.
       01 SP-CHK PIC 9 VALUE 1.
       PROCEDURE DIVISION.
       MAIN.
           MOVE 1 TO SP-OK
           PERFORM VARYING P FROM 1 BY 1 UNTIL P > 4
               PERFORM SP-ITER
           END-PERFORM
           IF SP-OK = 1
               DISPLAY "CONSUMER COBOL PASS"
           ELSE
               DISPLAY "CONSUMER COBOL FAIL"
               MOVE 1 TO RETURN-CODE
           END-IF
           STOP RUN.
       SP-ITER.
           MOVE 1 TO SP-CHK
           MOVE P TO A1-ARG
           MOVE 29 TO OP-ARG
           PERFORM CALL-LIB
           MOVE 30 TO OP-ARG
           PERFORM CALL-LIB
           IF A2-ARG NOT = P MOVE 0 TO SP-CHK END-IF
           MOVE 64 TO A1-ARG
           MOVE 18 TO OP-ARG
           PERFORM CALL-LIB
           IF A2-ARG NOT = 15 MOVE 0 TO SP-CHK END-IF
           IF BUF(1:4) NOT = "VSN-" MOVE 0 TO SP-CHK END-IF
           IF BUF(9:3) NOT = X"000904" MOVE 0 TO SP-CHK END-IF
           IF BUF(12:2) NOT = X"0901" MOVE 0 TO SP-CHK END-IF
           IF BUF(14:1) NOT = X"01" MOVE 0 TO SP-CHK END-IF
           EVALUATE P
               WHEN 1 IF BUF(15:1) NOT = X"01" MOVE 0 TO SP-CHK END-IF
               WHEN 2 IF BUF(15:1) NOT = X"02" MOVE 0 TO SP-CHK END-IF
               WHEN 3 IF BUF(15:1) NOT = X"03" MOVE 0 TO SP-CHK END-IF
               WHEN 4 IF BUF(15:1) NOT = X"04" MOVE 0 TO SP-CHK END-IF
           END-EVALUATE
           MOVE 15 TO A1-ARG
           MOVE 19 TO OP-ARG
           PERFORM CALL-LIB
           IF A2-ARG NOT = 1 MOVE 0 TO SP-CHK END-IF
           MOVE 30 TO OP-ARG
           PERFORM CALL-LIB
           IF A2-ARG NOT = P MOVE 0 TO SP-CHK END-IF
           IF SP-CHK = 0 MOVE 0 TO SP-OK END-IF
           EXIT.
       CALL-LIB.
           CALL "VSN-LIBRARY" USING OP-ARG A1-ARG A2-ARG BUF
           END-CALL.
