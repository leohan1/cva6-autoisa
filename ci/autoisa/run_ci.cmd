@echo off
REM ============================================================
REM  AutoISA Direct-CI CI harness - CMD entry point
REM ============================================================
REM
REM  Thin wrapper that calls run_ci.py via Python.  Use this if
REM  you don't want to invoke python directly.
REM
REM  Usage:
REM    run_ci.cmd                         REM all testbenches
REM    run_ci.cmd --tb autoisa_ci_harness_v0
REM    run_ci.cmd --clean                 REM wipe xsim work + logs
REM
REM  Override the project root by setting CI_PROJECT_ROOT, or
REM  override the Vivado bin path by setting CI_VIVADO_BIN.
REM
REM ============================================================

setlocal
set "PYTHON=python"
where %PYTHON% >NUL 2>&1
if errorlevel 1 (
    echo ERROR: python not found on PATH.  Install Python 3.8+ or set PYTHON.
    exit /b 2
)

if not defined CI_PROJECT_ROOT set "CI_PROJECT_ROOT=%~dp0..\.."
if not defined CI_VIVADO_BIN   set "CI_VIVADO_BIN=D:\apps\HLS\2025.2\Vivado\bin"

%PYTHON% "%~dp0run_ci.py" --root "%CI_PROJECT_ROOT%" --vivado "%CI_VIVADO_BIN%" %*
exit /b %ERRORLEVEL%
