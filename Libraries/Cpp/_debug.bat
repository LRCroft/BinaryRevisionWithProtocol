@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cd /d C:\CampMember\BinaryRevisionWithProtocol\Libraries\Cpp
echo === O2 Ob0 ===
cl /nologo /W3 /EHsc /std:c++17 /O2 /Ob0 /STACK:8000000 /Fe:_b1.exe vsn.cpp test_vsn.cpp 1>nul 2>&1 && _b1.exe
echo "b1_exit=%errorlevel%"
echo === O2 Oy- ===
cl /nologo /W3 /EHsc /std:c++17 /O2 /Oy- /STACK:8000000 /Fe:_b2.exe vsn.cpp test_vsn.cpp 1>nul 2>&1 && _b2.exe
echo "b2_exit=%errorlevel%"

