: << 'CMDBLOCK'
@echo off
REM Cross-platform polyglot wrapper for the superpowers statusline.
REM On Windows: cmd.exe runs the batch portion, which finds and calls bash.
REM On Unix: the shell interprets this as a script (: is a no-op in bash).
REM
REM The statusline script uses an extensionless filename so Claude Code's
REM Windows auto-detection -- which prepends "bash" to any command containing
REM .sh -- doesn't interfere.
REM
REM Usage (as a statusLine command): run-statusline.cmd [options...]

set "STATUSLINE_DIR=%~dp0"

REM Try Git for Windows bash in standard locations
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%STATUSLINE_DIR%superpowers-statusline" %*
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%STATUSLINE_DIR%superpowers-statusline" %*
    exit /b %ERRORLEVEL%
)

REM Try bash on PATH (e.g. user-installed Git Bash, MSYS2, Cygwin)
where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%STATUSLINE_DIR%superpowers-statusline" %*
    exit /b %ERRORLEVEL%
)

REM No bash found - print nothing rather than an error, so the statusline
REM degrades to empty instead of showing a shell error.
exit /b 0
CMDBLOCK

# Unix: run the statusline script directly
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${SCRIPT_DIR}/superpowers-statusline" "$@"
