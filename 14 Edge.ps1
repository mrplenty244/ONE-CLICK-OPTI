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
        # Start the process elevated and immediately exit the non-elevated one.
        Start-Process PowerShell.exe -ArgumentList $ArgumentList -Verb RunAs -ErrorAction Stop
    } catch {
        # If elevation fails, exit with an error code (no console output)
        Exit 1
    }
    # Exit the current non-elevated instance
    Exit 0
}
#endregion

#region Main Script Logic

# Suppress progress bars and errors globally for silent operation
$progressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

# --- Step 1: Stop Edge and related processes ---
$processesToStop = @(
    "MicrosoftEdgeUpdate",
    "OneDrive",             # Included in original, might be desired by user
    "WidgetService",        # Included in original
    "Widgets",              # Included in original
    "msedge",
    "msedgewebview2"
)
$processesToStop | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }

# --- Step 2: Uninstall Copilot (Included in original 'Edge Off') ---
try {
    Get-AppxPackage -AllUsers -Name "*Microsoft.Windows.Ai.Copilot.Provider*" -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxPackage -AllUsers -Name "*Microsoft.Copilot*" -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
} catch {
    # Ignore AppX removal errors
}

# --- Step 3: Set Registry keys for Edge update prevention and uninstall ---
$regKeyEdgeUpdate = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\EdgeUpdate"
$regKeyEdgeUpdateDev = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev" # Use native path

try {
    # Prevent updates via Chromium channel
    if (-not (Test-Path $regKeyEdgeUpdate)) { New-Item -Path $regKeyEdgeUpdate -Force | Out-Null }
    Set-ItemProperty -Path $regKeyEdgeUpdate -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Type DWord -Force
} catch {
    # Ignore errors
} # <<< CORRECTED: Added missing brace

try {
    # Allow uninstall (Note: This key might not always exist or work)
    if (-not (Test-Path $regKeyEdgeUpdateDev)) { New-Item -Path $regKeyEdgeUpdateDev -Force | Out-Null }
    Set-ItemProperty -Path $regKeyEdgeUpdateDev -Name "AllowUninstall" -Value 1 -Type DWord -Force # Set as DWORD 1, original used SZ without value
} catch {
    # Ignore errors
} # <<< CORRECTED: Added missing brace

# --- Step 4: Attempt Edge Uninstall via its UninstallString ---
$edgeUninstallKeyPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
$uninstallStringRaw = $null
$uninstallArgs = $null
$exePath = $null # Initialize exePath

try {
    if (Test-Path $edgeUninstallKeyPath) {
        $uninstallStringRaw = Get-ItemPropertyValue -Path $edgeUninstallKeyPath -Name "UninstallString" -ErrorAction SilentlyContinue
    }

    if ($uninstallStringRaw) {
        # Extract executable and arguments, append force flag
        # This assumes the path might be quoted
        if ($uninstallStringRaw -match '^"(.+?)"\s*(.*)') {
            $exePath = $matches[1]
            $existingArgs = $matches[2]
            $uninstallArgs = "$existingArgs --force-uninstall"
        } elseif ($uninstallStringRaw -match '^([^\s]+)\s*(.*)') {
             $exePath = $matches[1]
             $existingArgs = $matches[2]
             $uninstallArgs = "$existingArgs --force-uninstall"
        } else {
            # Path likely doesn't have args, just append force
            $exePath = $uninstallStringRaw
            $uninstallArgs = "--force-uninstall"
        }

        if ($exePath -and (Test-Path $exePath)) { # Check if exePath was assigned and exists
            Start-Process -FilePath $exePath -ArgumentList $uninstallArgs -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
        }
    }
} catch {
    # Ignore errors finding or running uninstall string
}

# --- Step 5: Attempt to Uninstall/Unregister Edge Update ---
$edgeUpdatePaths = @()
$searchFolders = @("LocalApplicationData", "ProgramFilesX86", "ProgramFiles")
foreach ($folderType in $searchFolders) {
    $folderPath = [Environment]::GetFolderPath($folderType)
    # Check if folder path exists before trying Get-ChildItem
    if ($folderPath -and (Test-Path $folderPath)) {
        $edgeUpdatePaths += Get-ChildItem (Join-Path $folderPath "Microsoft\EdgeUpdate\*.*.*.*\MicrosoftEdgeUpdate.exe") -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }
}
$edgeUpdatePaths = $edgeUpdatePaths | Get-Unique

# Remove EdgeUpdate registry keys first
$edgeUpdateRegRoots = @(
    "HKCU:\SOFTWARE", "HKLM:\SOFTWARE", "HKCU:\SOFTWARE\Policies", "HKLM:\SOFTWARE\Policies",
    "HKCU:\SOFTWARE\WOW6432Node", "HKLM:\SOFTWARE\WOW6432Node",
    "HKCU:\SOFTWARE\WOW6432Node\Policies", "HKLM:\SOFTWARE\WOW6432Node\Policies"
)
foreach ($root in $edgeUpdateRegRoots) {
    $keyPath = Join-Path $root "Microsoft\EdgeUpdate"
    if (Test-Path $keyPath) {
        Remove-Item -Path $keyPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Run unregister/uninstall commands for found Edge Update executables
foreach ($path in $edgeUpdatePaths) {
    if (Test-Path $path) {
        # Try unregistering service first
        Start-Process -FilePath $path -ArgumentList "/unregsvc" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
        # Then try uninstalling
        Start-Process -FilePath $path -ArgumentList "/uninstall" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
    }
}

# --- Step 6: Remove Edge WebView Uninstall Registry Keys ---
$webViewUninstallPaths = @(
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView",
    "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView"
)
foreach ($keyPath in $webViewUninstallPaths) {
    if (Test-Path $keyPath) {
        Remove-Item -Path $keyPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Step 7: Remove Specific Edge Folders ---
# **Revised from original to be less destructive**
$edgeFoldersToRemove = @(
    (Join-Path $env:ProgramFiles "Microsoft\Edge"),
    (Join-Path $env:ProgramFiles "Microsoft\EdgeUpdate"),
    (Join-Path $env:ProgramFiles "Microsoft\EdgeCore"),
    (Join-Path $env:ProgramFiles "Microsoft\EdgeWebView"), # Less common here
    (Join-Path $env:ProgramFilesX86 "Microsoft\Edge"),
    (Join-Path $env:ProgramFilesX86 "Microsoft\EdgeUpdate"),
    (Join-Path $env:ProgramFilesX86 "Microsoft\EdgeCore"),
    (Join-Path $env:ProgramFilesX86 "Microsoft\EdgeWebView")
)
foreach ($folder in $edgeFoldersToRemove) {
    if (Test-Path $folder) {
        Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
# Also try removing temp folders if they exist
Remove-Item -Path (Join-Path $env:LOCALAPPDATA "Microsoft\Edge") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $env:LOCALAPPDATA "Microsoft\EdgeUpdate") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $env:LOCALAPPDATA "Microsoft\EdgeCore") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $env:LOCALAPPDATA "Microsoft\EdgeWebView") -Recurse -Force -ErrorAction SilentlyContinue

# --- Step 8: Remove Edge Shortcuts ---
$edgeShortcutsToRemove = @(
    (Join-Path ([Environment]::GetFolderPath('System')) "config\systemprofile\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk"),
    (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk"),
    (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk"),
    (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Tombstones\Microsoft Edge.lnk"), # Tombstones likely not present but included for consistency
    (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"),
    (Join-Path ([Environment]::GetFolderPath('PublicDesktop')) "Microsoft Edge.lnk")
)
foreach ($shortcut in $edgeShortcutsToRemove) {
    if (Test-Path $shortcut) {
        Remove-Item -Path $shortcut -Force -ErrorAction SilentlyContinue
    }
}

# --- Final Step: Exit ---
Exit 0

#endregion Main Script Logic
