@echo off
REM Benilde ClassRecord: backs up the whole database to a dated .sql file.
REM
REM Double-click this file (MySQL must be running in XAMPP). The backup goes
REM into a "backups" folder next to this file. Run it at least once a week,
REM and copy the backups folder to a flash drive or Google Drive now and then.
REM
REM To restore a backup: phpMyAdmin > benilde_classrecord > Import > choose the file.

set MYSQLDUMP=C:\xampp\mysql\bin\mysqldump.exe
set DB=benilde_classrecord
set OUT=%~dp0backups

if not exist "%MYSQLDUMP%" (
  echo Could not find %MYSQLDUMP%. Edit the MYSQLDUMP line if XAMPP is installed elsewhere.
  pause
  exit /b 1
)

if not exist "%OUT%" mkdir "%OUT%"

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmm"') do set STAMP=%%i

"%MYSQLDUMP%" -u root --single-transaction --routines %DB% > "%OUT%\%DB%_%STAMP%.sql"

if errorlevel 1 (
  echo Backup FAILED. Is MySQL running in the XAMPP Control Panel?
) else (
  echo Backup saved to %OUT%\%DB%_%STAMP%.sql
)
pause