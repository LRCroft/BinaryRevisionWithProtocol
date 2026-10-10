with Ada.Text_IO; use Ada.Text_IO;
with VSN;
procedure Main is
   -- VSN independent consumer (Ada) -- Storage Policy round-trip.
   -- Uses the library's Create_With_Policy + Export_Bytes (wire-out)
   -- + Import_Bytes + Get_Storage_Policy (wire-in).
   s     : VSN.Store;
   s2    : VSN.Store;
   got   : Positive;
   fails : Natural := 0;

   function Sig (B : String) return Boolean is
   begin
      for I in 1 .. B'Length loop
         if I + 5 <= B'Length
            and B (I) = Character'Val (0) and B (I + 1) = Character'Val (9)
            and B (I + 2) = Character'Val (4) and B (I + 3) = Character'Val (9)
            and B (I + 4) = Character'Val (1) and B (I + 5) = Character'Val (1)
         then
            return True;
         end if;
      end loop;
      return False;
   end Sig;
begin
   for P in 1 .. 4 loop
      s := VSN.Create_With_Policy (P);
      if VSN.Get_Storage_Policy (s) /= P then
         Put_Line ("FAIL store p=" & Integer'Image (P)); fails := fails + 1;
      end if;
      declare
         exported : constant String := VSN.Export_Bytes (s);
      begin
         if not Sig (exported) then
            Put_Line ("FAIL wire p=" & Integer'Image (P)); fails := fails + 1;
         end if;
         s2 := VSN.Create (1);
         if not VSN.Import_Bytes (s2, exported) then
            Put_Line ("FAIL import p=" & Integer'Image (P)); fails := fails + 1;
         end if;
         got := VSN.Get_Storage_Policy (s2);
         if got /= P then
            Put_Line ("FAIL roundtrip p=" & Integer'Image (P) & " got=" & Integer'Image (got));
            fails := fails + 1;
         end if;
      end;
   end loop;
   if fails > 0 then
      Put_Line ("CONSUMER ADA FAIL");
      raise Program_Error;
   else
      Put_Line ("CONSUMER ADA PASS");
   end if;
end Main;

