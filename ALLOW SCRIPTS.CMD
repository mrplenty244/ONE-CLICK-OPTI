@echo off
:: Check for Admin rights
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    goto uacprompt
) else ( goto gotadmin )

:: UAC Prompt Section
:uacprompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:: Actions to perform with Admin rights
:gotadmin
    :: Clean up the VBS script if it exists
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    
    :: Ensure we are operating relative to the script's location
    pushd "%CD%"
    CD /D "%~dp0"

    :: Clear screen (optional, can be removed if truly silent needed)
    cls

    :: Allow double click execution of PowerShell scripts via registry
    reg add "HKCR\Applications\powershell.exe\shell\open\command" /ve /t REG_SZ /d "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy unrestricted -File \"%%1\"" /f >nul 2>&1
    
    :: Set PowerShell Execution Policy to Unrestricted for Current User
    reg add "HKCU\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell" /v "ExecutionPolicy" /t REG_SZ /d "Unrestricted" /f >nul 2>&1
    
    :: Set PowerShell Execution Policy to Unrestricted for Local Machine (requires admin)
    reg add "HKLM\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell" /v "ExecutionPolicy" /t REG_SZ /d "Unrestricted" /f >nul 2>&1
    
    :: Unblock all downloaded files in the current directory and subdirectories
    :: Added redirection to suppress output from PowerShell itself
    powershell -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1
    
    :: Restore original directory (optional but good practice)
    popd 
    
    :: Exit the script automatically
    exit /B 
