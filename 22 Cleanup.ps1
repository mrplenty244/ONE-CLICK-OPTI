#Requires -RunAsAdministrator

<#
.SYNOPSIS
Performs system cleanup tasks silently.
Clears standard Temp folders and initiates an automated Disk Cleanup.

.DESCRIPTION
1. Ensures it is running with Administrator privileges.
2. Deletes the contents of the user's %TEMP% folder.
3. Deletes the contents of the system's %SystemDrive%\Windows\Temp folder.
4. Configures Disk Cleanup registry settings for a specific profile (sageset=65535)
   to select all available cleanup handlers.
5. Runs Disk Cleanup silently using the configured settings (/sagerun:65535).
   The cleanmgr process is started in the background and this script does NOT wait for it to finish.
6. Exits with code 0 on success, 1 on critical failure (like elevation).

.NOTES
- Requires Administrator privileges.
- Uses /sageset:65535 and /sagerun:65535 for Disk Cleanup automation to minimize
  conflict with user-defined settings (numbers 0-65534).
- Disk Cleanup (`cleanmgr.exe /sagerun:n`) runs in the background after being initiated.
  This script will finish before the cleanup itself might be fully complete.
- ErrorActionPreference is set to SilentlyContinue to avoid non-terminating errors
  halting the script (e.g., cannot delete a file in use in Temp).
#>

#region Elevation Check
# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    try {
        $ArgumentList = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', """$($PSCommandPath)"""
        )
        Start-Process PowerShell.exe -ArgumentList $ArgumentList -Verb RunAs -ErrorAction Stop
    } catch {
        # Exit silently with error code if elevation fails
        Exit 1
    }
    # Exit the current non-elevated instance
    Exit 0
}
#endregion

#region Console Setup - Optional, can be removed if absolutely no console output is desired
# $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)" # Uncomment if running standalone
# Clear-Host # Uncomment if running standalone and want a clean start
#endregion

# Suppress non-terminating errors for silent operation
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Starting automated system cleanup..." # Log for console/debug runs

# --- Step 1: Clear Temp Folders ---
Write-Host "[Cleanup] Clearing user temp folder ($env:TEMP)..."
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null # Use $env:TEMP for user temp

Write-Host "[Cleanup] Clearing system temp folder ($env:SystemRoot\Temp)..."
Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null # Use $env:SystemRoot for system temp

Write-Host "[Cleanup] Temp folders cleared (errors ignored)."

# --- Step 2: Automate Disk Cleanup (cleanmgr) ---
$sagesetNum = 65535 # Use a high number for sageset/sagerun to avoid conflicts
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
$stateFlagName = "StateFlags{0:0000}" -f $sagesetNum # e.g., StateFlags65535

Write-Host "[Cleanup] Configuring Disk Cleanup options via registry (Set: $sagesetNum)..."
try {
    # Get all available cleanup handlers (subkeys under VolumeCaches)
    $handlers = Get-ChildItem -Path $registryPath -ErrorAction Stop

    # Iterate through each handler and set its StateFlags value to 2 (checked)
    foreach ($handler in $handlers) {
        # Need temporary higher error action for this specific sensitive operation
        $oldErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Stop' # Ensure failure to set property stops this handler's attempt
        try {
            # Ensure the key exists before trying to set property
            if(Test-Path $handler.PSPath){
                 Set-ItemProperty -Path $handler.PSPath -Name $stateFlagName -Value 2 -Type DWord -Force
                 # Write-Host "  Set StateFlags for $($handler.PSChildName)" # Verbose log
            } else {
                 Write-Warning "  Handler path not found: $($handler.PSPath)"
            }
        } catch {
            Write-Warning "  Could not set StateFlags for $($handler.PSChildName) at $($handler.PSPath): $($_.Exception.Message)"
        } finally {
             $ErrorActionPreference = $oldErrorAction # Restore original preference
        }
    }
    Write-Host "[Cleanup] Disk Cleanup registry options configured."

    Write-Host "[Cleanup] Running Disk Cleanup silently (Set: $sagesetNum)..."
    # Run cleanmgr silently using the configured settings
    # DO NOT use -Wait, let it run in the background.
    try {
        # Start the process but don't wait for it
        Start-Process "cleanmgr.exe" -ArgumentList "/sagerun:$sagesetNum" -WindowStyle Hidden -ErrorAction Stop
        Write-Host "[Cleanup] Disk Cleanup process initiated successfully (running in background)."
        # No sleep needed here, script continues immediately
    } catch {
         # Log warning if cleanmgr fails to start, but script continues
         Write-Warning "[Cleanup] Failed to start cleanmgr.exe /sagerun: $($_.Exception.Message)"
    }

} catch {
    # Catch errors from Get-ChildItem primarily
    Write-Error "An error occurred during Disk Cleanup automation (likely finding handlers): $($_.Exception.Message)"
    # Exit with error code if the overall process fails significantly
    Exit 1
}

Write-Host "[Cleanup] System cleanup script finished."
Exit 0 # Ensure script exits cleanly with success code
