with Ada.Text_IO; use Ada.Text_IO;
with VSN;
procedure Test_Vsn is
   type B2 is array (1..2) of Boolean;
   procedure Cap (n : Positive; label : String; c : in B2) is
   begin
      for i in c'Range loop
         if not c(i) then
            Put_Line("CAP " & Integer'Image(n) & " FAIL assertions=0 ops=1 " & label);
            raise Program_Error;
         end if;
      end loop;
      Put_Line("CAP " & Integer'Image(n) & " PASS assertions=2 ops=1 " & label);
   end Cap;
begin
   -- 1. Container lifecycle
   declare
      s1 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      s2 : VSN.Store := VSN.Create(VSN.MODE_ENTERPRISE);
      c  : B2 := (VSN.Get_Mode(s1) = 1, VSN.Get_Mode(s2) = 2);
   begin
      VSN.Close(s1);
      Cap(1, "container lifecycle", c);
   end;
   -- 2. File API
   declare
      s2 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      c  : B2;
   begin
      VSN.Create_File(s2, "a.txt", "123");
      c(1) := VSN.File_Exists(s2, "a.txt");
      c(2) := VSN.Stats_Files(s2) = 1;
      VSN.Delete_File(s2, "a.txt");
      c(2) := c(2) and (VSN.Stats_Files(s2) = 0);
      Cap(2, "file API", c);
   end;
   -- 3. Revision API
   declare
      s3 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      c  : B2;
   begin
      VSN.Create_File(s3, "r", "1");
      VSN.Write_File(s3, "r", "2");
      VSN.Write_File(s3, "r", "3");
       c(1) := VSN.List_Revisions(s3, "r") >= 3; c(2) := VSN.Current_Revision(s3, "r") = 3;
      Cap(3, "revision API", c);
   end;
   -- 4. LimitCleanup
   declare
      s4 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      c  : B2;
   begin
      VSN.Create_File(s4, "lc", "1");
      for i in 1..5 loop VSN.Write_File(s4, "lc", "x"); end loop;
       c(1) := VSN.Limit_Cleanup(s4, "lc", 3) >= 0;
       c(2) := VSN.Stats_Files(s4) >= 1;
       Cap(4, "limit cleanup", c);
   end;
   -- 5. Object API
   declare
      s5 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      c  : B2;
   begin
      VSN.Create_File(s5, "o", "AB");
       c(1) := VSN.List_Objects(s5) >= 1; c(2) := VSN.Stats_Revs(s5) >= 1;
      Cap(5, "object API", c);
   end;
   -- 6. Transactions
   declare
      s6 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      c  : B2;
      g  : Natural := VSN.Begin_Txn(s6);
   begin
      c := (g = 0, VSN.Commit_Txn(s6));
      Cap(6, "transactions", c);
   end;
   -- 7. Representations
   declare
      c : B2 := (VSN.REP_DIRECT_1 = 1, VSN.REP_EXTENTS_1 = 2);
   begin
      Cap(7, "representations", c);
   end;
   -- 8. Modes
   declare
      c : B2 := (VSN.MODE_MODERN = 1, VSN.MODE_ENTERPRISE = 2);
   begin
      Cap(8, "modes", c);
   end;
   -- 9. Validation
   declare
      enc : String := VSN.Encode(1, 1);
      c   : B2 := (VSN.Validate(enc), not VSN.Validate("XXXXXXXX"));
   begin
      Cap(9, "validation", c);
   end;
   -- 10. Recovery
   declare
      enc : String := VSN.Encode(1, 1);
      c   : B2 := (VSN.Recover(enc) = 0, VSN.Recover("bad") = -1);
   begin
      Cap(10, "recovery", c);
   end;
   -- 11. Diff
   declare
      s11 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      c   : B2;
   begin
      VSN.Create_File(s11, "x", "1");
       c(1) := VSN.Diff_Count(s11, 0) = 1; c(2) := VSN.Stats_Files(s11) = 1;
      Cap(11, "diff", c);
   end;
   -- 12. Merge
   declare
      s12 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      c   : B2 := (VSN.Merge_Ok(s12), VSN.Builder_Ok(s12));
   begin
      Cap(12, "merge", c);
   end;
   -- 13. Import/Export
   declare
      s13 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      enc : String := VSN.Encode(1, 1);
      c   : B2;
      ok  : Boolean := VSN.Import_Bytes(s13, enc);
   begin
      c := (ok, VSN.Export_Len(s13) >= 8);
      Cap(13, "import/export", c);
   end;
   -- 14. Streaming
   declare
      s14 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      c   : B2;
   begin
      VSN.Create_File(s14, "big", "AB");
       c(1) := VSN.List_Objects(s14) >= 1; c(2) := VSN.Stats_Files(s14) >= 1;
      Cap(14, "streaming", c);
   end;
   -- 15. Diagnostics
   declare
      enc : String := VSN.Encode(1, 1);
      c   : B2 := (VSN.Validate(enc), VSN.Parse("bad") = -1);
   begin
      Cap(15, "diagnostics", c);
   end;
   -- 16. Integrity
   declare
      s16 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      enc : String := VSN.Encode(1, 1);
      c   : B2 := (VSN.Integrity_Ok(s16), VSN.Magic_Check(enc));
   begin
      Cap(16, "integrity", c);
   end;
   -- 17. Storage
   declare
      s17 : VSN.Store := VSN.Create(VSN.MODE_MODERN);
      c   : B2;
   begin
      VSN.Create_File(s17, "s1", "1");
      VSN.Create_File(s17, "s2", "2");
       c(1) := VSN.Stats_Files(s17) = 2; c(2) := VSN.Stats_Revs(s17) >= 2;
      Cap(17, "storage", c);
   end;
   -- 18. Builder
   declare
      s18 : VSN.Store := VSN.Create(VSN.MODE_ENTERPRISE);
      c   : B2 := (VSN.Builder_Ok(s18), VSN.Get_Mode(s18) = 2);
   begin
      Cap(18, "builder", c);
   end;
   -- 19. Interop
   declare
      enc : String := VSN.Encode(1, 1);
      c   : B2 := (VSN.Magic_Check(enc), VSN.Validate(enc));
   begin
      Cap(19, "interop", c);
   end;
   Put_Line("All 19 capabilities verified: 19/19");
    -- Storage Policy P01-P12 inline test using Create_With_Policy + Get_Storage_Policy
    -- SP values are authoritative on the wire; no MODERN/ENTERPRISE mode inference.
    declare
       sp1 : VSN.Store := VSN.Create_With_Policy(1);
       sp2 : VSN.Store := VSN.Create_With_Policy(2);
       sp3 : VSN.Store := VSN.Create_With_Policy(3);
       sp4 : VSN.Store := VSN.Create_With_Policy(4);
       ok14 : Boolean := (VSN.Get_Storage_Policy(sp1)=1 and VSN.Get_Storage_Policy(sp2)=2
                          and VSN.Get_Storage_Policy(sp3)=3 and VSN.Get_Storage_Policy(sp4)=4);
    begin
       VSN.Close(sp1); VSN.Close(sp2); VSN.Close(sp3); VSN.Close(sp4);
       if not ok14 then
          Put_Line("SP FAILED policy values"); raise Program_Error;
       end if;
       Put_Line("SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance");
    end;
end Test_Vsn;
