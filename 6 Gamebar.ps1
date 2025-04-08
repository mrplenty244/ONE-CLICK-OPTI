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

# --- Step 1: Disable Game Bar/DVR via Registry (HKCU) ---
$regSettingsHKCU = @(
    @{ Path = "Registry::HKEY_CURRENT_USER\System\GameConfigStore"; Name = "GameDVR_Enabled"; Value = 0 },
    @{ Path = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\GameDVR"; Name = "AppCaptureEnabled"; Value = 0 },
    @{ Path = "Registry::HKEY_CURRENT_USER\Software\Microsoft\GameBar"; Name = "UseNexusForGameBarEnabled"; Value = 0 }
)
$regValueTypeDWord = [Microsoft.Win32.RegistryValueKind]::DWord

foreach ($setting in $regSettingsHKCU) {
    $regPath = $setting.Path
    $regName = $setting.Name
    $regValue = $setting.Value
    try {
        # Ensure the key path exists, creating if necessary
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        # Set the value
        Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Type $regValueTypeDWord -Force -ErrorAction SilentlyContinue
    } catch {
        # Ignore errors
    }
}

# --- Step 2: Disable Related Services via Registry (HKLM) ---
$servicesToDisable = @(
    "GameInputSvc",
    "BcastDVRUserService",
    "XboxGipSvc",
    "XblAuthManager",
    "XblGameSave",
    "XboxNetApiSvc"
)
$serviceRegBasePath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\" # Using ControlSet001 as per original
$serviceValueName = "Start"
$serviceValueDataDisabled = 4 # 4 = Disabled

foreach ($serviceName in $servicesToDisable) {
    $regPath = Join-Path $serviceRegBasePath $serviceName
    try {
        # Check if the service key exists before trying to set property
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name $serviceValueName -Value $serviceValueDataDisabled -Type $regValueTypeDWord -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # Ignore errors
    }
}

# --- Step 3: Disable ms-gamebar URI Scheme via Registry ---
$regFilePath = Join-Path $env:TEMP "MsGamebarNotiOff.reg"
$regContent = @"
Windows Registry Editor Version 5.00

[HKEY_CLASSES_ROOT\ms-gamebar]
"URL Protocol"=""
"NoOpenWith"=""
@="URL:ms-gamebar"

[HKEY_CLASSES_ROOT\ms-gamebar\shell\open\command]
@="\"%SystemRoot%\\System32\\systray.exe\""

[HKEY_CLASSES_ROOT\ms-gamebarservices]
"URL Protocol"=""
"NoOpenWith"=""
@="URL:ms-gamebarservices"

[HKEY_CLASSES_ROOT\ms-gamebarservices\shell\open\command]
@="\"%SystemRoot%\\System32\\systray.exe\""

[HKEY_CLASSES_ROOT\ms-gamingoverlay]
"URL Protocol"=""
"NoOpenWith"=""
@="URL:ms-gamingoverlay"

[HKEY_CLASSES_ROOT\ms-gamingoverlay\shell\open\command]
@="\"%SystemRoot%\\System32\\systray.exe\""
"@

try {
    # Use UTF8 which regedit usually handles fine for ASCII content
    Set-Content -Path $regFilePath -Value $regContent -Force -Encoding UTF8 -ErrorAction SilentlyContinue
    # Import the .reg file silently
    Start-Process "regedit.exe" -ArgumentList "/S `"$regFilePath`"" -Wait -ErrorAction SilentlyContinue | Out-Null
} catch {
    # Ignore errors during reg file creation/import
} finally {
    # Clean up the reg file
    if (Test-Path $regFilePath) {
        Remove-Item $regFilePath -Force -ErrorAction SilentlyContinue
    }
}

# --- Step 4: Stop GameBar Process ---
Stop-Process -Name "GameBar*" -Force -ErrorAction SilentlyContinue | Out-Null # Use wildcard to catch variants like GameBar.exe

# --- Step 5: Uninstall Related AppX Packages ---
$appxPatternsToRemove = @(
    "*Microsoft.GamingApp*",
    "*Microsoft.Xbox.TCUI*",
    "*Microsoft.XboxApp*",
    "*Microsoft.XboxGameOverlay*",
    "*Microsoft.XboxGamingOverlay*",
    "*Microsoft.XboxIdentityProvider*",
    "*Microsoft.XboxSpeechToTextOverlay*"
)
foreach ($pattern in $appxPatternsToRemove) {
    try {
        Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
    } catch {
        # Ignore errors during AppX removal
    }
}

# --- Final Step: Exit ---
Exit 0

#endregion Main Script Logic