package VSN is
   pragma Preelaborate;
   Magic        : constant String := "VSN-";
   CFV          : constant Positive := 1;
   EV           : constant Positive := 1;
   MODE_MODERN          : constant Positive := 1;
   MODE_ENTERPRISE      : constant Positive := 2;
   REP_DIRECT_1         : constant Positive := 1;
   REP_EXTENTS_1        : constant Positive := 2;
   type Vsn_Container is record
      cfv : Positive := 1;
      ev : Positive := 1;
      mode : Positive := MODE_MODERN;
      byte_length : Natural := 0;
   end record;
   function Parse (data : String) return Integer;
   function Encode (mode : Positive; gen : Positive) return String;
   function Validate (data : String) return Boolean;
   function Recover (data : String) return Integer;
   function Magic_Check (data : String) return Boolean;
   -- MutableStore
   type Store is tagged private;
   function Create (mode : Positive) return Store;
   procedure Close (s : in out Store);
   function Get_Mode (s : Store) return Positive;
   procedure Create_File (s : in out Store; name : String; content : String);
   function File_Exists (s : Store; fid : String) return Boolean;
   function Read_File_Len (s : Store; fid : String) return Integer;
   procedure Write_File (s : in out Store; fid : String; content : String);
   procedure Delete_File (s : in out Store; fid : String);
   function Current_Revision (s : Store; fid : String) return Integer;
   function List_Revisions (s : Store; fid : String) return Integer;
   function Limit_Cleanup (s : in out Store; fid : String; limit : Positive) return Integer;
   function List_Objects (s : Store) return Integer;
   function Begin_Txn (s : Store) return Natural;
   function Commit_Txn (s : in out Store) return Boolean;
   function Diff_Count (s : Store; other_count : Natural) return Natural;
   function Merge_Ok (s : Store) return Boolean;
   function Import_Bytes (s : in out Store; data : String) return Boolean;
   function Export_Len (s : Store) return Natural;
   function Integrity_Ok (s : Store) return Boolean;
   function Stats_Files (s : Store) return Natural;
   function Stats_Revs (s : Store) return Natural;
   function Builder_Ok (s : Store) return Boolean;
private
   type Store is tagged record
      mval : Positive := MODE_MODERN;
      generation : Natural := 0;
      file_count : Natural := 0;
      rev_count : Natural := 0;
      obj_count : Natural := 0;
      next_rev : Positive := 1;
      isclosed : Boolean := False;
      next_obj : Positive := 1;
   end record;
end VSN;