@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cd /d C:\CampMember\BinaryRevisionWithProtocol\Libraries\C
cl /nologo /W4 /O2 /Fe:test_vsn.exe vsn.c test_vsn.c
