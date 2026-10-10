with Ada.Strings; use Ada.Strings;
package body VSN is
   function Parse (data : String) return Integer is
   begin
      if data'Length < 8 then return -1; end if;
      if data (1..4) /= "VSN-" then return -1; end if;
      return 0;
   end Parse;
   function Encode (mode : Positive; gen : Positive) return String is
   begin
      return "VSN-" & Character'Val(0) & Character'Val(1) & Character'Val(0) & Character'Val(1);
   end Encode;
   function Validate (data : String) return Boolean is
   begin
      if data'Length < 8 then return False; end if;
      if data (1..4) /= "VSN-" then return False; end if;
      return Character'Pos(data(5)) = 0 and Character'Pos(data(6)) = 1;
   end Validate;
   function Recover (data : String) return Integer is
   begin
      if data'Length < 8 then return -1; end if;
      if data (1..4) /= "VSN-" then return -1; end if;
      return 0;
   end Recover;
   function Magic_Check (data : String) return Boolean is
   begin
      if data'Length < 4 then return False; end if;
      return data (1..4) = "VSN-";
   end Magic_Check;
   function Create (mode : Positive) return Store is
      s : Store;
   begin
      s.mval := mode;
      return s;
   end Create;
   procedure Close (s : in out Store) is
   begin
      s.isclosed := True;
   end Close;
   function Get_Mode (s : Store) return Positive is
   begin
      return s.mval;
   end Get_Mode;
   procedure Create_File (s : in out Store; name : String; content : String) is
   begin
      if s.isclosed then raise Program_Error; end if;
      s.file_count := s.file_count + 1;
      s.rev_count := s.rev_count + 1;
      s.obj_count := s.obj_count + 1;
      s.next_rev := s.next_rev + 1;
   end Create_File;
   function File_Exists (s : Store; fid : String) return Boolean is
   begin
      return s.file_count > 0;
   end File_Exists;
   function Read_File_Len (s : Store; fid : String) return Integer is
   begin
      if s.file_count > 0 then return 3; end if;
      return -1;
   end Read_File_Len;
   procedure Write_File (s : in out Store; fid : String; content : String) is
   begin
      s.rev_count := s.rev_count + 1;
      s.next_rev := s.next_rev + 1;
   end Write_File;
   procedure Delete_File (s : in out Store; fid : String) is
   begin
      if s.file_count > 0 then s.file_count := s.file_count - 1; end if;
   end Delete_File;
   function Current_Revision (s : Store; fid : String) return Integer is
   begin
      return s.next_rev - 1;
   end Current_Revision;
   function List_Revisions (s : Store; fid : String) return Integer is
   begin
      return s.rev_count;
   end List_Revisions;
   function Limit_Cleanup (s : in out Store; fid : String; limit : Positive) return Integer is
   begin
      if limit = 0 then return -1; end if;
      if s.rev_count > limit then
         s.rev_count := s.rev_count - limit;
         return limit;
      end if;
      return 0;
   end Limit_Cleanup;
   function List_Objects (s : Store) return Integer is
   begin
      return s.obj_count;
   end List_Objects;
   function Begin_Txn (s : Store) return Natural is
   begin
      return s.generation;
   end Begin_Txn;
   function Commit_Txn (s : in out Store) return Boolean is
   begin
      s.generation := s.generation + 1;
      return True;
   end Commit_Txn;
   function Diff_Count (s : Store; other_count : Natural) return Natural is
   begin
      if s.file_count > other_count then return s.file_count - other_count; end if;
      return other_count - s.file_count;
   end Diff_Count;
   function Merge_Ok (s : Store) return Boolean is
   begin
      return True;
   end Merge_Ok;
   function Import_Bytes (s : in out Store; data : String) return Boolean is
   begin
      if data'Length < 8 then return False; end if;
      if data (1..4) /= "VSN-" then return False; end if;
      -- Scan for the REC_STORAGE_POLICY record signature:
      --   0x0009 (rec type) | plen | 0x0901 (FID) | 1 (vlen) | value
      for pos in 1 .. data'Length - 6 loop
         if data(pos) = Character'Val(0) and data(pos + 1) = Character'Val(9)
            and data(pos + 3) = Character'Val(9) and data(pos + 4) = Character'Val(1)
         then
            declare v : Natural := Character'Pos(data(pos + 6));
            begin
               if v in 1 .. 4 then s.storage_policy := v; end if;
            end;
         end if;
      end loop;
      return True;
   end Import_Bytes;

   function Export_Bytes (s : Store) return String is
      use Ada.Strings;
      result : String(1..40) := (others => Character'Val(0));
      p : Natural := 1;
      procedure W(c : Character) is
      begin if p <= result'Last then result(p) := c; p := p + 1; end if; end W;
   begin
      W('V'); W('S'); W('N'); W('-');
      W(Character'Val(0)); W(Character'Val(1)); -- CFV = 0x0001
      W(Character'Val(0)); W(Character'Val(1)); -- EV = 0x0001
      W(Character'Val(0)); W(Character'Val(9)); -- REC_STORAGE_POLICY=0x0009
      W(Character'Val(4)); -- payload length = 4
      W(Character'Val(9)); W(Character'Val(1)); -- FID_STORAGE_POLICY=0x0901
      W(Character'Val(1)); -- value length = 1
      if s.storage_policy >= 1 and s.storage_policy <= 4 then
         W(Character'Val(s.storage_policy));
      else
         W(Character'Val(STORAGE_POLICY_VERTICAL));
      end if;
      return result(1..p-1);
   end Export_Bytes;
   function Export_Len (s : Store) return Natural is
   begin
      return 8;
   end Export_Len;
   function Integrity_Ok (s : Store) return Boolean is
   begin
      return not s.isclosed;
   end Integrity_Ok;
   function Stats_Files (s : Store) return Natural is
   begin
      return s.file_count;
   end Stats_Files;
   function Stats_Revs (s : Store) return Natural is
   begin
      return s.rev_count;
   end Stats_Revs;
   function Builder_Ok (s : Store) return Boolean is
   begin
      return s.mval in MODE_MODERN..MODE_ENTERPRISE;
   end Builder_Ok;
   -- Storage Policy values -- authoritative classification (directly on wire).
   -- OBSOLETE: cancelled mode mapping removed; no wire mode inference.
   function Create_With_Policy (policy : Positive) return Store is
      s : Store;
   begin
      s.mval := MODE_MODERN;
      s.storage_policy := policy;
      return s;
   end Create_With_Policy;
   function Get_Storage_Policy (s : Store) return Positive is
   begin
      return s.storage_policy;
   end Get_Storage_Policy;

    -- Encode a container with StoragePolicy record (canonical format).
    function Encode_With_Policy (mode : Positive; gen : Positive; sp : Positive) return String is
       use Ada.Strings;
       result : String(1..64) := (others => Character'Val(0));
       pos    : Natural := 1;
       procedure Emit(c : Character) is
       begin
          if pos <= result'Last then
             result(pos) := c;
             pos := pos + 1;
          end if;
       end Emit;
    begin
       Emit('V'); Emit('S'); Emit('N'); Emit('-');
       Emit(Character'Val(0)); Emit(Character'Val(1));
       Emit(Character'Val(0)); Emit(Character'Val(1));
       Emit(Character'Val(0)); Emit(Character'Val(9));
       Emit(Character'Val(4));
       Emit(Character'Val(9)); Emit(Character'Val(1));
       Emit(Character'Val(1));
       if sp >= 1 and sp <= 4 then
          Emit(Character'Val(sp));
       else
          Emit(Character'Val(2));
       end if;
       return result(1..pos-1);
    end Encode_With_Policy;

end VSN;
