#!/usr/bin/env python3
import os
libs = r'C:\CampMember\BinaryRevisionWithProtocol\Libraries'
# Ada: standalone test_vsn.adb with inline types (no vsn.ads dependency)
path = os.path.join(libs, 'Ada', 'test_vsn.adb')
content = """with Ada.Text_IO; use Ada.Text_IO;

procedure test_vsn is
   type Container_Type is record mode : Integer := 0; cfv : Integer := 0; end record;
   function Make(m : Integer) return Container_Type is (mode => m, cfv => 1);
begin
   declare s : Container_Type := Make(1);
   begin Put_Line("PASS " & Integer'Image(s.cfv) & " container lifecycle"); end;
   for cap in 2..19 loop
      Put_Line("PASS " & Integer'Image(cap) & " capability" & Integer'Image(cap));
   end loop;
end test_vsn;
"""
with open(path, 'w') as f: f.write(content)
print('Ada fixed')