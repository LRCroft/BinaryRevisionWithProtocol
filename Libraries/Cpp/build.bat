@echo off
rem VSN C++ library build + test (MSVC, C++17).
rem The C core (vsn.c) is compiled as C (separate object) and linked in; the
rem C++ facade (vsn.cpp) wraps it with RAII, std::vector, and exceptions.
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cd /d C:\CampMember\BinaryRevisionWithProtocol\Libraries\Cpp
set TARGET=%1
if "%TARGET%"=="" set TARGET=test
cl /nologo /W4 /O2 /c ..\C\vsn.c /Fo:vsn_core.obj
if %errorlevel% neq 0 exit /b %errorlevel%
if /I "%TARGET%"=="probe" (
  cl /nologo /W3 /EHsc /std:c++17 /O2 /STACK:8000000 /Fe:limit_probe_cpp.exe vsn.cpp limit_probe.cpp vsn_core.obj
  if %errorlevel% neq 0 exit /b %errorlevel%
  limit_probe_cpp.exe
) else (
  cl /nologo /W3 /EHsc /std:c++17 /O2 /STACK:8000000 /Fe:test_vsn_cpp.exe vsn.cpp test_vsn.cpp vsn_core.obj
  if %errorlevel% neq 0 exit /b %errorlevel%
  test_vsn_cpp.exe
)