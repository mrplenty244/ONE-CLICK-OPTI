#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and runs NvCleanInstall silently.
.DESCRIPTION
    Downloads the latest NvCleanInstall.exe to the temporary directory
    and executes it. Requires Administrator privileges.
    Provides no console output on success. Outputs errors only if download
    or execution fails.
.NOTES
    Requires internet connectivity.
#>

# Ensure running as Administrator
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
{
    # Silently attempt to relaunch as admin if not already elevated
    try {
        Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs -ErrorAction Stop
    } catch {
        # If relaunch fails, exit silently. Can't proceed without Admin.
        Exit 1
    }
    Exit 0 # Exit the current non-admin process
}

# Define constants
$nvCleanInstallUrl = "https://github.com/FR33THYFR33THY/files/raw/main/NV%20Clean%20Install.exe"
$tempFilePath = Join-Path $env:TEMP "NV_Clean_Install_Temp.exe" # Use a distinct temp name

# Clean up previous temp file if it exists
Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue

# Download NvCleanInstall
try {
    Invoke-WebRequest -Uri $nvCleanInstallUrl -OutFile $tempFilePath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
} catch {
    # Log error (optional, could write to event log instead of console)
    Write-Error "Failed to download NvCleanInstall from $nvCleanInstallUrl : $($_.Exception.Message)"
    Exit 1 # Exit with error code
}

# Verify download
if (-not (Test-Path $tempFilePath) -or (Get-Item $tempFilePath).Length -lt 100KB) { # Basic size check
    Write-Error "NvCleanInstall download failed or file is too small."
    Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue # Clean up potentially corrupt file
    Exit 1
}

# Start NvCleanInstall
try {
    Start-Process -FilePath $tempFilePath -ErrorAction Stop
} catch {
    Write-Error "Failed to start NvCleanInstall from $tempFilePath : $($_.Exception.Message)"
    # Keep the downloaded file in case manual execution is needed
    Exit 1
}

# Optional: Clean up the downloaded file immediately after starting
# Uncomment the next line if you want to delete the EXE right away
# Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue

Exit 0 # Success