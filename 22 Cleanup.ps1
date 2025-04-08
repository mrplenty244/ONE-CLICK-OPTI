#Requires -RunAsAdministrator

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

#region Console Setup - Optional for silent operation, but keep for standalone runs
# $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
# $Host.UI.RawUI.BackgroundColor = "Black"
# $Host.PrivateData.ProgressBackgroundColor = "Black"
# $Host.PrivateData.ProgressForegroundColor = "White"
# Clear-Host # Remove Clear-Host for truly silent operation if desired when called by Python
#endregion

# Suppress non-terminating errors for silent operation
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Starting automated system cleanup..." # Log for console runs

# --- Step 1: Clear Temp Folders ---
Write-Host "[Cleanup] Clearing user temp folder..."
Remove-Item -Path "$env:USERPROFILE\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Write-Host "[Cleanup] Clearing system temp folder..."
Remove-Item -Path "$env:SystemDrive\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Write-Host "[Cleanup] Temp folders cleared."

# --- Step 2: Automate Disk Cleanup (cleanmgr) ---
$sagesetNum = 65535 # Use a high number for sageset/sagerun to avoid conflicts with user settings
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
$stateFlagName = "StateFlags{0:0000}" -f $sagesetNum # e.g., StateFlags65535

Write-Host "[Cleanup] Configuring Disk Cleanup options via registry (Set: $sagesetNum)..."
try {
    # Get all available cleanup handlers (subkeys under VolumeCaches)
    $handlers = Get-ChildItem -Path $registryPath -ErrorAction Stop

    # Iterate through each handler and set its StateFlags value to 2 (checked)
    foreach ($handler in $handlers) {
        try {
            Set-ItemProperty -Path $handler.PSPath -Name $stateFlagName -Value 2 -Type DWord -Force -ErrorAction Stop
            # Write-Host "  Set StateFlags for $($handler.PSChildName)" # Uncomment for verbose logging
        } catch {
            Write-Warning "  Could not set StateFlags for $($handler.PSChildName): $($_.Exception.Message)"
        }
    }
    Write-Host "[Cleanup] Disk Cleanup registry options configured."

    Write-Host "[Cleanup] Running Disk Cleanup silently (Set: $sagesetNum)..."
    # Run cleanmgr silently using the configured settings
    # Use -Wait to allow it time to process, although it might return before fully finished
    $process = Start-Process "cleanmgr.exe" -ArgumentList "/sagerun:$sagesetNum" -WindowStyle Hidden -Wait -PassThru -ErrorAction SilentlyContinue

    # Check exit code, though sagerun might return 0 even if cleanup is still running/fails later
    if ($process -ne $null -and $process.ExitCode -ne 0) {
         Write-Warning "[Cleanup] cleanmgr.exe /sagerun potentially exited with code $($process.ExitCode)."
    } else {
         Write-Host "[Cleanup] Disk Cleanup process initiated successfully."
         # Add a small sleep just in case, as sagerun can return very quickly
         Start-Sleep -Seconds 3
    }

} catch {
    Write-Error "An error occurred during Disk Cleanup automation: $($_.Exception.Message)"
    # Exit with error code if the overall process fails
    Exit 1
}

Write-Host "[Cleanup] System cleanup script finished."
Exit 0 # Ensure script exits cleanly with success code
