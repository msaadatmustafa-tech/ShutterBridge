@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  set PY=py -3
) else (
  where python >nul 2>nul
  if %ERRORLEVEL% NEQ 0 (
    echo Python is missing. Install Python 3 from python.org and check Add Python to PATH.
    pause
    exit /b 1
  )
  set PY=python
)
if not exist ".venv\Scripts\python.exe" (
  echo Setting up local Python environment...
  %PY% -m venv .venv
  if errorlevel 1 (pause & exit /b 1)
)
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 (pause & exit /b 1)
".venv\Scripts\python.exe" camera_remote.py
if errorlevel 1 pause
