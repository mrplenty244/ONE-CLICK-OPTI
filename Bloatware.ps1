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

# --- Step 1: Uninstall UWP Apps (Keep NVIDIA and CBS) ---
try {
    Get-AppXPackage -AllUsers | Where-Object { $_.Name -notlike '*NVIDIA*' -and $_.Name -notlike '*CBS*' } | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
} catch {
    # Ignore errors during bulk removal
}

# --- Step 2: Uninstall UWP Features (Capabilities) ---
$uwpFeaturesToRemove = @(
    "App.StepsRecorder~~~~0.0.1.0",
    "App.Support.QuickAssist~~~~0.0.1.0",
    "Browser.InternetExplorer~~~~0.0.11.0",
    "DirectX.Configuration.Database~~~~0.0.1.0",
    "Hello.Face.18967~~~~0.0.1.0", # Specific version might not exist on all systems
    "Hello.Face.20134~~~~0.0.1.0", # Specific version might not exist on all systems
    "MathRecognizer~~~~0.0.1.0",
    "Media.WindowsMediaPlayer~~~~0.0.12.0",
    "Microsoft.Wallpapers.Extended~~~~0.0.1.0", # Specific version might not exist
    "Microsoft.Windows.MSPaint~~~~0.0.1.0", # Removing Paint capability
    "Microsoft.Windows.Notepad.System~~~~0.0.1.0", # Removing Notepad capability
    "Microsoft.Windows.PowerShell.ISE~~~~0.0.1.0",
    "Microsoft.Windows.WordPad~~~~0.0.1.0",
    "OneCoreUAP.OneSync~~~~0.0.1.0",
    "OpenSSH.Client~~~~0.0.1.0",
    "Print.Fax.Scan~~~~0.0.1.0",
    "Print.Management.Console~~~~0.0.1.0",
    # "VBSCRIPT~~~~", # Commented as per original script note (breaks installers)
    "WMIC~~~~",
    # "Windows.Client.ShellComponents~~~~0.0.1.0", # Commented as per original script note (breaks UWP snipping tool W10)
    "Windows.Kernel.LA57~~~~0.0.1.0" # Specific version might not exist
)
# Add common driver capabilities if removal is desired (kept commented as per original script)
# $driverCapabilities = Get-WindowsCapability -Online | Where-Object { $_.Name -match 'Microsoft.Windows.(Wifi|Ethernet).Client' } | Select-Object -ExpandProperty Name
# $uwpFeaturesToRemove += $driverCapabilities

foreach ($feature in $uwpFeaturesToRemove) {
    try {
        # Check if capability exists before trying to remove
        if (Get-WindowsCapability -Online -Name $feature -ErrorAction SilentlyContinue) {
             Remove-WindowsCapability -Online -Name $feature -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        # Ignore errors removing capability
    }
}

# --- Step 3: Uninstall Legacy Features (DISM) ---
$legacyFeaturesToRemove = @(
    # "NetFx4-AdvSrvs", # Commented as per original
    "WCF-Services45",
    "WCF-TCP-PortSharing45",
    "MediaPlayback",
    "Printing-PrintToPDFServices-Features",
    "Printing-XPSServices-Features",
    "Printing-Foundation-Features",
    "Printing-Foundation-InternetPrinting-Client",
    "MSRDC-Infrastructure",
    # "SearchEngine-Client-Package", # Commented as per original (breaks search)
    "SMB1Protocol",
    "SMB1Protocol-Client",
    "SMB1Protocol-Deprecation",
    "SmbDirect",
    "Windows-Identity-Foundation",
    "MicrosoftWindowsPowerShellV2Root",
    "MicrosoftWindowsPowerShellV2",
    "WorkFolders-Client"
)
foreach ($feature in $legacyFeaturesToRemove) {
    try {
        # Check if feature is enabled before trying to disable
        $featureState = (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue).State
        if ($featureState -eq 'Enabled') {
             Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        # Ignore errors disabling feature
    }
}

# --- Step 4: Uninstall Legacy Apps (MSI/EXE) ---
$msiProductsToRemove = @(
    # Microsoft Update Health Tools (GUIDs may vary, using names if possible)
    # Using known GUIDs from original script:
    "{C6FD611E-7EFE-488C-A0E0-974C09EF6473}", # W11?
    "{1FC1A6C2-576E-489A-9B4A-92D21F542136}"  # W10?
    # Updates for Windows (GUIDs vary significantly)
    # Using known GUIDs from original script:
    # "{B9A7A138-BFD5-4C73-A269-F78CCA28150E}", # These are specific KBs, might not exist
    # "{85C69797-7336-4E83-8D97-32A7C8465A3B}"  # These are specific KBs, might not exist
)
foreach ($productCode in $msiProductsToRemove) {
    try {
        Start-Process "msiexec.exe" -ArgumentList "/X $productCode /qn /norestart" -Wait -WindowStyle Hidden -ErrorAction Stop | Out-Null
    } catch {
        # Ignore errors uninstalling MSI
    }
}

# Clean Microsoft Update Health Tools service registry key (W10 specific?)
Remove-Item "Registry::HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\uhssvc" -Recurse -Force -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "PLUGScheduler" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

# --- Step 5: Uninstall OneDrive ---
Stop-Process -Name "OneDrive*" -Force -ErrorAction SilentlyContinue | Out-Null # Stop OneDrive process(es)

$oneDriveSetupPaths = @(
    (Join-Path $env:SystemRoot "System32\OneDriveSetup.exe"), # W11 path
    (Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe")  # W10 path
)
foreach ($setupPath in $oneDriveSetupPaths) {
    if (Test-Path $setupPath) {
        try {
            Start-Process -FilePath $setupPath -ArgumentList "/uninstall" -Wait -WindowStyle Hidden -ErrorAction Stop | Out-Null
            # Give it a moment to potentially finish background tasks before next step
            Start-Sleep -Seconds 2
        } catch {
            # Ignore errors during OneDrive uninstall attempt
        }
    }
}
# Clean OneDrive scheduled tasks
Get-ScheduledTask | Where-Object { $_.TaskName -like '*OneDrive*' } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

# --- Step 6: Clean Adobe Type Manager Font Drivers (W10 specific?) ---
Remove-Item "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Font Drivers" -Recurse -Force -ErrorAction SilentlyContinue

# --- Step 7: Uninstall Old Snipping Tool (W10 only?) ---
$snippingToolPath = Join-Path $env:SystemRoot "System32\SnippingTool.exe"
if (Test-Path $snippingToolPath) {
    try {
        # This might pop a UI, no truly silent uninstall is documented
        Start-Process -FilePath $snippingToolPath -ArgumentList "/Uninstall" -WindowStyle Hidden -ErrorAction Stop | Out-Null
        # Attempt to close the process if it lingered (no guarantee)
        Start-Sleep -Seconds 1
        Stop-Process -Name "SnippingTool" -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {
         # Ignore errors
    }
}

# --- Step 8: Uninstall Remote Desktop Connection (mstsc) ---
$mstscPath = Join-Path $env:SystemRoot "System32\mstsc.exe"
if (Test-Path $mstscPath) {
    try {
        # This might pop a UI, no truly silent uninstall is documented
        Start-Process -FilePath $mstscPath -ArgumentList "/Uninstall" -WindowStyle Hidden -ErrorAction Stop | Out-Null
        # Attempt to close the process if it lingered
        Start-Sleep -Seconds 1
        Stop-Process -Name "mstsc" -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {
         # Ignore errors
    }
}

# --- Final Step: Exit ---
Exit 0

#endregion Main Script Logic