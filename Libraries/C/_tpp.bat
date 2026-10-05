@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cd /d C:\CampMember\BinaryRevisionWithProtocol\Libraries\C
cl /nologo /W3 /c /TP /Fo:_t.obj vsn.c
if exist _t.obj del _t.obj