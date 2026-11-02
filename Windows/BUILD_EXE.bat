@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo First run START_WINDOWS.bat.
  pause
  exit /b 1
)
".venv\Scripts\python.exe" -m pip install -r requirements-lock.txt
if errorlevel 1 (pause & exit /b 1)
".venv\Scripts\python.exe" -m PyInstaller --noconfirm --clean --onefile --windowed --name iPhoneCameraRemote camera_remote.py
if errorlevel 1 (pause & exit /b 1)
echo EXE created at dist\iPhoneCameraRemote.exe
pause
