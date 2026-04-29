@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM validate.bat
REM Two-phase file audit:
REM   1) Required-file existence check
REM   2) Required-file data-row check (excluding header)
REM
REM Usage:
REM   validate.bat [FTP_PATH] [FILELIST_PATH] [OUTPUT_DIR]
REM
REM Exit codes:
REM   0 = success
REM   1 = invalid input / environment issue
REM   2 = required file missing
REM   3 = required file has no data rows
REM ============================================================

set "FTP_PATH=%~1"
if "%FTP_PATH%"=="" set "FTP_PATH=\\server\ftp\incoming"

set "FILELIST_PATH=%~2"
if "%FILELIST_PATH%"=="" set "FILELIST_PATH=.\filelist.csv"

set "OUTPUT_DIR=%~3"
if "%OUTPUT_DIR%"=="" set "OUTPUT_DIR=.\output"

set "EXISTENCE_CSV=%OUTPUT_DIR%\existence_check.csv"
set "ROWCOUNT_CSV=%OUTPUT_DIR%\rowcount_check.csv"

if not exist "%FILELIST_PATH%" (
    echo [ERROR] filelist not found: "%FILELIST_PATH%" 1>&2
    exit /b 1
)

if not exist "%OUTPUT_DIR%" (
    mkdir "%OUTPUT_DIR%" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] cannot create output directory: "%OUTPUT_DIR%" 1>&2
        exit /b 1
    )
)

> "%EXISTENCE_CSV%" echo filename,flag,status,full_path
> "%ROWCOUNT_CSV%" echo filename,total_lines,data_rows,status,full_path

set "MISSING_REQUIRED=0"
set "EMPTY_REQUIRED=0"

REM -----------------------------
REM Phase 1: existence check
REM -----------------------------
for /f "usebackq skip=1 tokens=1,2 delims=," %%A in ("%FILELIST_PATH%") do (
    set "FILENAME=%%~A"
    set "FLAG=%%~B"

    REM trim whitespace
    for /f "tokens=* delims= " %%X in ("!FILENAME!") do set "FILENAME=%%X"
    for /f "tokens=* delims= " %%X in ("!FLAG!") do set "FLAG=%%X"

    if "!FILENAME!"=="" (
        REM skip blank filename rows
    ) else (
        set "FULL_PATH=%FTP_PATH%\!FILENAME!"

        if /i "!FLAG!"=="Y" (
            if exist "!FULL_PATH!" (
                >> "%EXISTENCE_CSV%" echo !FILENAME!,!FLAG!,OK,!FULL_PATH!
            ) else (
                >> "%EXISTENCE_CSV%" echo !FILENAME!,!FLAG!,MISSING,!FULL_PATH!
                set "MISSING_REQUIRED=1"
            )
        ) else if /i "!FLAG!"=="N" (
            if exist "!FULL_PATH!" (
                >> "%EXISTENCE_CSV%" echo !FILENAME!,!FLAG!,OK,!FULL_PATH!
            ) else (
                >> "%EXISTENCE_CSV%" echo !FILENAME!,!FLAG!,SKIPPED,!FULL_PATH!
            )
        ) else (
            >> "%EXISTENCE_CSV%" echo !FILENAME!,!FLAG!,INVALID_FLAG,!FULL_PATH!
            echo [ERROR] invalid flag for file "!FILENAME!": "!FLAG!" 1>&2
            exit /b 1
        )
    )
)

if "%MISSING_REQUIRED%"=="1" (
    echo [ERROR] required file(s) missing. stop after phase 1. 1>&2
    exit /b 2
)

REM -----------------------------
REM Phase 2: data-row check
REM -----------------------------
for /f "usebackq skip=1 tokens=1,2 delims=," %%A in ("%FILELIST_PATH%") do (
    set "FILENAME=%%~A"
    set "FLAG=%%~B"

    for /f "tokens=* delims= " %%X in ("!FILENAME!") do set "FILENAME=%%X"
    for /f "tokens=* delims= " %%X in ("!FLAG!") do set "FLAG=%%X"

    if /i "!FLAG!"=="Y" (
        if not "!FILENAME!"=="" (
            set "FULL_PATH=%FTP_PATH%\!FILENAME!"
            set /a TOTAL_LINES=0

            for /f %%N in ('find /v /c "" ^< "!FULL_PATH!"') do set /a TOTAL_LINES=%%N

            set /a DATA_ROWS=TOTAL_LINES-1
            if !DATA_ROWS! lss 0 set /a DATA_ROWS=0

            if !DATA_ROWS! geq 1 (
                >> "%ROWCOUNT_CSV%" echo !FILENAME!,!TOTAL_LINES!,!DATA_ROWS!,OK,!FULL_PATH!
            ) else (
                >> "%ROWCOUNT_CSV%" echo !FILENAME!,!TOTAL_LINES!,!DATA_ROWS!,EMPTY,!FULL_PATH!
                set "EMPTY_REQUIRED=1"
            )
        )
    )
)

if "%EMPTY_REQUIRED%"=="1" (
    echo [ERROR] required file(s) empty (no data rows). stop after phase 2. 1>&2
    exit /b 3
)

echo [OK] validation completed.
echo Existence report: "%EXISTENCE_CSV%"
echo Rowcount report : "%ROWCOUNT_CSV%"
exit /b 0
