@echo off
rem Standard VSN C library build script (MSVC).
rem Usage: build.bat [target]   target = test (default) | probe | interop
setlocal
set VCVARS="C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist %VCVARS% set VCVARS="C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
call %VCVARS% >nul 2>&1
cd /d "C:\CampMember\BinaryRevisionWithProtocol\Libraries\C"
set TARGET=%1
if "%TARGET%"=="" set TARGET=test
if /I "%TARGET%"=="test" (
  cl /nologo /W4 /O2 /Fe:test_vsn.exe vsn.c test_vsn.c 1>nul 2>&1 && (test_vsn.exe)
) else if /I "%TARGET%"=="probe" (
  cl /nologo /W4 /O2 /Fe:limit_probe.exe vsn.c limit_probe.c 1>nul 2>&1 && (limit_probe.exe)
) else if /I "%TARGET%"=="interop" (
  cl /nologo /W4 /O2 /Fe:vsn_interop.exe vsn.c interop_cli.c 1>nul 2>&1
)
endlocal
