#Requires -RunAsAdministrator

<#
.SYNOPSIS
Applies "Clean" Start Menu and Taskbar settings (Recommended).
Modifies registry settings, recreates Quick Launch folders, pins File Explorer,
cleans Start Menu layouts for W10/W11, and removes various Taskbar buttons/features. Exits automatically.

.DESCRIPTION
This script performs the following actions directly, without user prompts:
1. Ensures it is running with Administrator privileges.
2. Cleans the Taskbar:
    - Unpins all existing items.
    - Recreates the Quick Launch folder structure.
    - Pins only File Explorer to the Taskbar.
    - Applies registry settings to hide Search, Task View, Chat, Copilot, Widgets, Meet Now, News/Interests.
    - Sets Taskbar alignment to Left (Windows 11).
    - Hides the Security taskbar icon startup entry.
    - (W10 Only) Configures tray icons setting (EnableAutoTray=0, might show more icons).
3. Cleans the Start Menu:
    - (W11 Only) Deletes existing Start Menu layout cache (start2.bin) and replaces it with a minimal version (File Explorer, Settings, potentially Edge).
    - (W11 Only) Hides the 'Recommended' section via policy registry keys.
    - (W10 Only) Applies a blank Start Menu layout using a temporary XML file and registry policies, then removes the policies and file.
4. Restarts Windows Explorer to apply most changes.
5. Outputs completion messages and exits automatically. A full system restart is recommended.

.NOTES
- Requires Administrator privileges.
- Modifies registry settings significantly (HKCU and HKLM).
- Restarts Windows Explorer multiple times, which will briefly hide the taskbar and desktop icons.
- Uses temporary files in %TEMP% (Taskbar_Clean.reg, start2.txt, start2.bin). These are cleaned up.
- (W10) The method to clear the Start Menu involves temporarily locking it, which might have side effects if interrupted.
- A full system restart is recommended after running the script.
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
        Write-Error "Failed to elevate script to Administrator privileges. Please run the script as Administrator manually."
        # Removed Read-Host for automatic exit in non-admin scenario after error
        Exit 1
    }
    # Exit the current non-elevated instance
    Exit 0
}
#endregion

#region Console Setup
Clear-Host
# Setting title only works reliably outside of ISE/VSCode integrated terminal
# try { $Host.UI.RawUI.WindowTitle = "Applying Clean Start Menu/Taskbar Settings (Administrator)" } catch {}
#endregion

#region Main Script Logic

Write-Host "Applying Clean Start Menu and Taskbar Settings..." -ForegroundColor Yellow

# --- Step 1: Clean Taskbar ---
Write-Host "[Taskbar] Unpinning existing items..." -ForegroundColor Cyan
try {
    # Using cmd for simplicity of deleting the entire key's contents, similar to original script
    cmd /c "reg delete HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband /f >nul 2>&1"

    # Recreate Quick Launch structure
    $quickLaunchPath = Join-Path $env:USERPROFILE "AppData\Roaming\Microsoft\Internet Explorer\Quick Launch"
    if (Test-Path $quickLaunchPath) {
        Remove-Item -Path $quickLaunchPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -Path (Split-Path $quickLaunchPath -Parent) -Name (Split-Path $quickLaunchPath -Leaf) -ItemType Directory -Force -ErrorAction SilentlyContinue
    $null = New-Item -Path $quickLaunchPath -Name "User Pinned" -ItemType Directory -Force -ErrorAction SilentlyContinue
    $null = New-Item -Path (Join-Path $quickLaunchPath "User Pinned") -Name "TaskBar" -ItemType Directory -Force -ErrorAction SilentlyContinue
    $null = New-Item -Path (Join-Path $quickLaunchPath "User Pinned") -Name "ImplicitAppShortcuts" -ItemType Directory -Force -ErrorAction SilentlyContinue

    Write-Host "[Taskbar] Recreated Quick Launch structure." -ForegroundColor Green
} catch {
    Write-Warning "[Taskbar] Error during unpinning or Quick Launch recreation: $($_.Exception.Message)"
}

Write-Host "[Taskbar] Pinning File Explorer..." -ForegroundColor Cyan
try {
    $WshShell = New-Object -comObject WScript.Shell
    $feShortcutPath = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\File Explorer.lnk"
    $Shortcut = $WshShell.CreateShortcut($feShortcutPath)
    $Shortcut.TargetPath = "explorer.exe" # Use explorer.exe for clarity
    $Shortcut.Save()
    Write-Host "[Taskbar] File Explorer pinned shortcut created." -ForegroundColor Green
} catch {
    Write-Warning "[Taskbar] Failed to create File Explorer pin shortcut: $($_.Exception.Message)"
}

Write-Host "[Taskbar] Applying registry settings..." -ForegroundColor Cyan
# Use a .reg file for the complex 'Favorites' key and other taskbar settings as in the original
$regFilePath = Join-Path $env:TEMP "Taskbar_Clean.reg"
$regContent = @"
Windows Registry Editor Version 5.00

; Force Pin File Explorer via Favorites (overwrites any existing)
[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband]
"Favorites"=hex:00,aa,01,00,00,3a,00,1f,80,c8,27,34,1f,10,5c,10,42,aa,03,2e,e4,\
  52,87,d6,68,26,00,01,00,26,00,ef,be,10,00,00,00,f4,7e,76,fa,de,9d,da,01,40,\
  61,5d,09,df,9d,da,01,19,b8,5f,09,df,9d,da,01,14,00,56,00,31,00,00,00,00,00,\
  a4,58,a9,26,10,00,54,61,73,6b,42,61,72,00,40,00,09,00,04,00,ef,be,a4,58,a9,\
  26,a4,58,a9,26,2e,00,00,00,de,9c,01,00,00,00,02,00,00,00,00,00,00,00,00,00,\
  00,00,00,00,00,00,0c,f4,85,00,54,00,61,00,73,00,6b,00,42,00,61,00,72,00,00,\
  00,16,00,18,01,32,00,8a,04,00,00,a4,58,b6,26,20,00,46,49,4c,45,45,58,7e,31,\
  2e,4c,4e,4b,00,00,54,00,09,00,04,00,ef,be,a4,58,b6,26,a4,58,b6,26,2e,00,00,\
  00,b7,a8,01,00,00,00,04,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,c0,5a,\
  1e,01,46,00,69,00,6c,00,65,00,20,00,45,00,78,00,70,00,6c,00,6f,00,72,00,65,\
  00,72,00,2e,00,6c,00,6e,00,6b,00,00,00,1c,00,22,00,00,00,1e,00,ef,be,02,00,\
  55,00,73,00,65,00,72,00,50,00,69,00,6e,00,6e,00,65,00,64,00,00,00,1c,00,12,\
  00,00,00,2b,00,ef,be,19,b8,5f,09,df,9d,da,01,1c,00,74,00,00,00,1d,00,ef,be,\
  02,00,7b,00,46,00,33,00,38,00,42,00,46,00,34,00,30,00,34,00,2d,00,31,00,44,\
  00,34,00,33,00,2d,00,34,00,32,00,46,00,32,00,2d,00,39,00,33,00,30,00,35,00,\
  2d,00,36,00,37,00,44,00,45,00,30,00,42,00,32,00,38,00,46,00,43,00,32,00,33,\
  00,7d,00,5c,00,65,00,78,00,70,00,6c,00,6f,00,72,00,65,00,72,00,2e,00,65,00,\
  78,00,65,00,00,00,1c,00,00,00,ff

; remove windows widgets from taskbar (HKLM Policy)
[HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Dsh]
"AllowNewsAndInterests"=dword:00000000

; left taskbar alignment (HKCU)
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]
"TaskbarAl"=dword:00000000

; remove search from taskbar (HKCU)
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search]
"SearchboxTaskbarMode"=dword:00000000

; remove task view from taskbar (HKCU)
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]
"ShowTaskViewButton"=dword:00000000

; remove chat from taskbar (HKCU)
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]
"TaskbarMn"=dword:00000000

; remove copilot from taskbar (HKCU)
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]
"ShowCopilotButton"=dword:00000000

; remove news and interests (HKLM Policy)
[HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\Windows Feeds]
"EnableFeeds"=dword:00000000

; remove meet now (HKCU Policy)
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer]
@=""
"HideSCAMeetNow"=dword:00000001

; disable security taskbar icon startup (HKLM)
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run]
"SecurityHealth"=hex:07,00,00,00,05,db,8a,69,8a,49,d9,01

; show all taskbar icons (EnableAutoTray=0, W10 only effect) (HKCU)
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer]
"EnableAutoTray"=dword:00000000
"@
try {
    Set-Content -Path $regFilePath -Value $regContent -Force -Encoding UTF8 # UTF8 is generally safe for regedit
    Write-Host "[Taskbar] Registry file created at $regFilePath" -ForegroundColor Green

    # Import the .reg file silently
    $process = Start-Process "regedit.exe" -ArgumentList "/S `"$regFilePath`"" -Wait -PassThru -ErrorAction Stop
    if ($process.ExitCode -eq 0) {
        Write-Host "[Taskbar] Registry settings imported successfully." -ForegroundColor Green
    } else {
        Write-Warning "[Taskbar] Regedit exited with code $($process.ExitCode). Import may have failed."
    }
} catch {
    Write-Error "[Taskbar] Failed to create or import registry file '$regFilePath'. Error: $($_.Exception.Message)"
} finally {
    # Clean up the reg file
    if (Test-Path $regFilePath) {
        Remove-Item $regFilePath -Force -ErrorAction SilentlyContinue
    }
}

# --- Step 2: Clean Start Menu ---

# == W11 Specific Start Menu Cleaning ==
Write-Host "[Start Menu W11] Applying settings..." -ForegroundColor Cyan
$startMenuPackagePath = Join-Path $env:USERPROFILE "AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy"
$startBinPath = Join-Path $startMenuPackagePath "LocalState\start2.bin"
$startBinTempTxt = Join-Path $env:TEMP "start2.txt"
$startBinTempBin = Join-Path $env:TEMP "start2.bin"

if (Test-Path $startMenuPackagePath) { # Basic check if it looks like W11 Start Menu is present
    try {
        # Remove existing layout cache
        if (Test-Path $startBinPath) {
            Remove-Item -Path $startBinPath -Force -ErrorAction Stop
            Write-Host "[Start Menu W11] Removed existing start2.bin." -ForegroundColor Green
        }

        # Minimal start2.bin content (Base64 encoded certificate)
        $certContent = @"
-----BEGIN CERTIFICATE-----
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
        TSz1QZdkum5Y3uC7wc7paXh1rm11nwluCC7jiA==
-----END CERTIFICATE-----
"@
        Set-Content -Path $startBinTempTxt -Value $certContent -Force -Encoding ASCII -ErrorAction Stop
        # Decode the cert to binary using certutil
        certutil.exe -decode $startBinTempTxt $startBinTempBin > $null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $startBinTempBin)) {
            throw "Certutil failed to decode start2.bin certificate."
        }
        # Copy the decoded file to the correct location
        Copy-Item $startBinTempBin -Destination $startBinPath -Force -ErrorAction Stop
        Write-Host "[Start Menu W11] Replaced start2.bin with minimal layout." -ForegroundColor Green

    } catch {
        Write-Warning "[Start Menu W11] Failed to apply minimal layout: $($_.Exception.Message)"
    } finally {
        # Clean up temp files for start2.bin
        if (Test-Path $startBinTempTxt) { Remove-Item $startBinTempTxt -Force -ErrorAction SilentlyContinue }
        if (Test-Path $startBinTempBin) { Remove-Item $startBinTempBin -Force -ErrorAction SilentlyContinue }
    }

    # Apply registry settings to hide Recommended section (W11) - Use native cmdlets
    Write-Host "[Start Menu W11] Hiding 'Recommended' section via registry..." -ForegroundColor Cyan
    $regPathsW11 = @(
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\current\device\Start",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\current\device\Education",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    )
    $regErrorsW11 = 0
    foreach ($regPath in $regPathsW11) {
        try {
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
            }
            if ($regPath -like "*device\Start*" -or $regPath -like "*Windows\Explorer*") {
                Set-ItemProperty -Path $regPath -Name "HideRecommendedSection" -Value 1 -Type DWord -Force -ErrorAction Stop
            }
            if ($regPath -like "*device\Education*") {
                Set-ItemProperty -Path $regPath -Name "IsEducationEnvironment" -Value 1 -Type DWord -Force -ErrorAction Stop
            }
        } catch {
            Write-Warning "[Start Menu W11] Failed to set registry key '$regPath': $($_.Exception.Message)"
            $regErrorsW11++
        }
    }
    if ($regErrorsW11 -eq 0) {
        Write-Host "[Start Menu W11] Registry settings for 'Recommended' section applied." -ForegroundColor Green
    }

} else {
     Write-Host "[Start Menu W11] StartMenuExperienceHost package not found, skipping W11 specific steps." -ForegroundColor Gray
}

# == W10 Specific Start Menu Cleaning ==
Write-Host "[Start Menu W10] Applying blank layout..." -ForegroundColor Cyan
# Check for a W10 characteristic if needed, e.g., absence of StartMenuExperienceHost or OS version.
# Assuming script runner knows if they are on W10 or if W11 steps failed.
$layoutXmlPath = "C:\Windows\StartMenuLayout.xml"
$policyBasePaths = @(
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows",
    "Registry::HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows"
)
$policyKeyName = "Explorer"

try {
    # Delete any existing custom layout file first
    if (Test-Path $layoutXmlPath) {
        Remove-Item -Path $layoutXmlPath -Force -ErrorAction SilentlyContinue
        Write-Host "[Start Menu W10] Removed existing $layoutXmlPath." -ForegroundColor Green
    }

    # Create blank Start Menu Layout XML
    $layoutXmlContent = @"
<LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification">
    <LayoutOptions StartTileGroupCellWidth="6" />
    <DefaultLayoutOverride>
        <StartLayoutCollection>
            <defaultlayout:StartLayout GroupCellWidth="6" />
        </StartLayoutCollection>
    </DefaultLayoutOverride>
</LayoutModificationTemplate>
"@
    Set-Content -Path $layoutXmlPath -Value $layoutXmlContent -Force -Encoding ASCII -ErrorAction Stop
    Write-Host "[Start Menu W10] Created blank $layoutXmlPath." -ForegroundColor Green

    # Apply registry policies to use the layout file and lock it
    foreach ($basePath in $policyBasePaths) {
        $keyPath = Join-Path $basePath $policyKeyName
        if (-not (Test-Path -Path $keyPath)) {
            New-Item -Path $basePath -Name $policyKeyName -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $keyPath -Name "LockedStartLayout" -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $keyPath -Name "StartLayoutFile" -Value $layoutXmlPath -Type String -Force -ErrorAction Stop
    }
    Write-Host "[Start Menu W10] Applied Start Layout policies." -ForegroundColor Green

    # Restart Explorer to apply locked layout
    Write-Host "[Explorer] Restarting to apply locked layout..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5 # Wait for Explorer to likely fully stop and restart

    # Remove the lock policies
    Write-Host "[Start Menu W10] Removing Start Layout lock policies..." -ForegroundColor Cyan
    foreach ($basePath in $policyBasePaths) {
        $keyPath = Join-Path $basePath $policyKeyName
        if (Test-Path $keyPath) {
            Set-ItemProperty -Path $keyPath -Name "LockedStartLayout" -Value 0 -Type DWord -Force -ErrorAction Stop
            # Optionally remove StartLayoutFile property too, or leave it pointing to non-existent file
             # Remove-ItemProperty -Path $keyPath -Name "StartLayoutFile" -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "[Start Menu W10] Removed Start Layout lock policies." -ForegroundColor Green

    # Restart Explorer again to unlock
    Write-Host "[Explorer] Restarting to finalize..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2 # Shorter wait might be okay here

    # Delete the temporary layout file
    if (Test-Path $layoutXmlPath) {
        Remove-Item $layoutXmlPath -Force -ErrorAction SilentlyContinue
        Write-Host "[Start Menu W10] Removed temporary $layoutXmlPath." -ForegroundColor Green
    }

} catch {
    Write-Warning "[Start Menu W10] Failed during W10 Start Menu cleaning process: $($_.Exception.Message)"
    # Attempt cleanup even on failure
    if (Test-Path $layoutXmlPath) { Remove-Item $layoutXmlPath -Force -ErrorAction SilentlyContinue }
    # Attempt to unlock if policy was set
    try {
         foreach ($basePath in $policyBasePaths) {
             $keyPath = Join-Path $basePath $policyKeyName
             if ((Get-ItemProperty -Path $keyPath -Name "LockedStartLayout" -ErrorAction SilentlyContinue).LockedStartLayout -eq 1) {
                Set-ItemProperty -Path $keyPath -Name "LockedStartLayout" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
             }
         }
         Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    } catch {}
}


# --- Final Step: Output Completion Message ---
#Clear-Host # Removed clear host here to keep logs visible
Write-Host "`nClean Start Menu and Taskbar settings applied." -ForegroundColor Green
Write-Host "Windows Explorer has been restarted." -ForegroundColor Green
Write-Host "A full system RESTART is recommended to ensure all changes take effect properly." -ForegroundColor Yellow

# Removed the "Press any key" prompt and ReadKey
# Write-Host "`nPress any key to exit." -ForegroundColor White
# $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

exit 0

#endregion Main Script Logic
