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

# --- Step 1: Disable Widgets via Registry ---
$regPathsToSet = @(
    @{ Path = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests"; Name = "value"; Value = 0 },
    @{ Path = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0 }
)
$regValueType = [Microsoft.Win32.RegistryValueKind]::DWord

foreach ($regInfo in $regPathsToSet) {
    $regPath = $regInfo.Path
    $regName = $regInfo.Name
    $regValue = $regInfo.Value
    try {
        # Ensure the key path exists, creating if necessary, suppressing output/errors
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        # Set the value, suppressing output/errors
        Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Type $regValueType -Force -ErrorAction SilentlyContinue
    } catch {
        # Ignore errors during registry modification
    }
}

# --- Step 2: Stop Widgets Processes ---
$processesToStop = @(
    "Widgets",
    "WidgetService"
)
$processesToStop | ForEach-Object {
    # Silently attempt to stop processes. Ignore errors if not found or access denied.
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}

# --- Final Step: Exit ---
# No pause or message needed, the script will exit automatically here.
Exit 0

#endregion Main Script Logic