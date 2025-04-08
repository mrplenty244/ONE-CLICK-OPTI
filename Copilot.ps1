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

# Suppress progress bars for cmdlets that support it
$progressPreference = 'SilentlyContinue'

# --- Step 1: Stop potentially related processes ---
$processesToStop = @(
    "MicrosoftEdgeUpdate",
    "OneDrive",
    "WidgetService",
    "Widgets",
    "msedge",
    "msedgewebview2"
)
$processesToStop | ForEach-Object {
    # Silently attempt to stop processes. Ignore errors if not found or access denied.
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}

# --- Step 2: Uninstall Copilot AppX Packages ---
$copilotPackages = @(
    "*Microsoft.Windows.Ai.Copilot.Provider*",
    "*Microsoft.Copilot*"
)
foreach ($packagePattern in $copilotPackages) {
    try {
        Get-AppxPackage -AllUsers -Name $packagePattern -ErrorAction SilentlyContinue | ForEach-Object {
             Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
    } catch {
        # Ignore errors during AppX removal
    }
}

# --- Step 3: Disable Copilot via Registry Policies ---
$regPaths = @(
    "Registry::HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\WindowsCopilot",
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
)
$regValueName = "TurnOffWindowsCopilot"
$regValueData = 1 # 1 = Disable Copilot
$regValueType = [Microsoft.Win32.RegistryValueKind]::DWord

foreach ($regPath in $regPaths) {
    try {
        # Ensure the key path exists, creating if necessary, suppressing output/errors
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        # Set the value, suppressing output/errors
        Set-ItemProperty -Path $regPath -Name $regValueName -Value $regValueData -Type $regValueType -Force -ErrorAction SilentlyContinue
    } catch {
        # Ignore errors during registry modification
    }
}

# --- Final Step: Exit ---
# No pause or message needed, the script will exit automatically here.
Exit 0

#endregion Main Script Logic