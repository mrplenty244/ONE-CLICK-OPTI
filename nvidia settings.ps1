#Requires -RunAsAdministrator

<#
.SYNOPSIS
Applies recommended NVIDIA Profile settings using Nvidia Profile Inspector.
Downloads the inspector, creates a profile config, imports it, and applies registry tweaks.

.DESCRIPTION
This script performs the following actions:
1. Ensures it is running with Administrator privileges.
2. Downloads Nvidia Profile Inspector if needed.
3. Unblocks NVIDIA DRS files.
4. Creates a specific Nvidia Profile Inspector (.nip) configuration file with recommended settings.
5. Imports the configuration using Nvidia Profile Inspector.
6. Applies registry changes related to NVIDIA legacy sharpening.
7. Attempts to open the NVIDIA Control Panel.

.NOTES
Requires an active internet connection to download Nvidia Profile Inspector.
Modifies system registry settings related to NVIDIA drivers.
Uses files stored temporarily in %TEMP%.
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
        # Pause for user to see the error before exiting
        if (-not $env:CI) { Read-Host "Press Enter to exit" }
        Exit 1
    }
    # Exit the current non-elevated instance
    Exit 0
}
#endregion

#region Console Setup (Optional - can be removed if visual feedback is not desired)
Clear-Host
# Setting title only works reliably outside of ISE/VSCode integrated terminal
# try { $Host.UI.RawUI.WindowTitle = "Applying NVIDIA Recommended Settings (Administrator)" } catch {}
#endregion

#region Helper Functions

function Get-FileFromWeb {
    param (
        [Parameter(Mandatory)]
        [string]$URL,
        [Parameter(Mandatory)]
        [string]$File
    )

    # Nested function for progress display
    function Show-Progress {
        param (
            [Parameter(Mandatory)]
            [Single]$TotalValue,
            [Parameter(Mandatory)]
            [Single]$CurrentValue,
            [Parameter(Mandatory)]
            [string]$ProgressText,
            [int]$BarSize = 30, # Increased bar size for better visibility
            [switch]$Complete
        )

        # Avoid division by zero if ContentLength is not provided or zero
        if ($TotalValue -le 0) {
             # Show indeterminate progress or just activity text if total size is unknown
            Write-Host -NoNewLine "`r$ProgressText (Size Unknown) | Downloaded: $($CurrentValue / 1MB -as [string] -f 'N2') MB"
            return
        }

        $percent = $CurrentValue / $TotalValue
        $percentComplete = $percent * 100
        $completedBlocks = [math]::Floor($BarSize * $percent)
        $remainingBlocks = $BarSize - $completedBlocks
        $progressBar = ('#' * $completedBlocks) + ('-' * $remainingBlocks) # Use # and - for clarity

        # Use Write-Progress in ISE/compatible hosts, custom bar otherwise
        if ($psISE -or $Host.Name -match 'Visual Studio Code') {
            $status = "$ProgressText - $($percentComplete.ToString('F2'))%"
            Write-Progress -Activity "Downloading File" -Status $status -Id 1 -PercentComplete $percentComplete
        } else {
            # Pad the text to avoid leftover characters from previous shorter lines
            $output = "`r$ProgressText [$progressBar] $($percentComplete.ToString('F2').PadLeft(6)) % ".PadRight(80) # Pad to clear previous line
             Write-Host -NoNewLine $output
        }
    }

    $StartTime = Get-Date
    Write-Host "Starting download: $($File | Split-Path -Leaf) from $URL"

    # Ensure target directory exists
    $fileDirectory = Split-Path $File -Parent
    if (-not (Test-Path $fileDirectory)) {
        try {
            New-Item -ItemType Directory -Path $fileDirectory -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Error "Failed to create directory: $fileDirectory. Error: $($_.Exception.Message)"
            return $false # Indicate failure
        }
    }

    $reader = $null
    $writer = $null
    $response = $null

    try {
        # Use WebClient for simplicity and better progress handling integration potential
        $webClient = New-Object System.Net.WebClient

        # Optional: Configure Proxy if needed
        # $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        # $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        # $webClient.Proxy = $proxy

        # Event handler for download progress
        $script:downloadTotalBytes = 0
        $script:downloadCurrentBytes = 0
        $progressBlock = {
            param($sender, $e)
            $script:downloadTotalBytes = $e.TotalBytesToReceive
            $script:downloadCurrentBytes = $e.BytesReceived
            Show-Progress -TotalValue $script:downloadTotalBytes -CurrentValue $script:downloadCurrentBytes -ProgressText "Downloading $($File | Split-Path -Leaf)"
        }
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action $progressBlock -SourceIdentifier "WebClientProgress" | Out-Null

        # Event handler for download completion
        $completionBlock = {
             # Clean up the progress display
            if ($psISE -or $Host.Name -match 'Visual Studio Code') {
                Write-Progress -Activity "Downloading File" -Status "Completed" -Id 1 -Completed
            } else {
                # Ensure the final 100% is shown and then clear the line with spaces before the newline
                Show-Progress -TotalValue $script:downloadTotalBytes -CurrentValue $script:downloadTotalBytes -ProgressText "Downloading $($File | Split-Path -Leaf)" -Complete
                Write-Host ("`r".PadRight(81)) # Clear the progress line
                Write-Host "" # Move to the next line
            }
            $duration = (Get-Date) - $StartTime
            Write-Host "Download complete: $($File | Split-Path -Leaf) ($($script:downloadTotalBytes / 1MB -as [string] -f 'N2') MB) in $($duration.ToString('hh\:mm\:ss'))"
        }
        Register-ObjectEvent -InputObject $webClient -EventName DownloadFileCompleted -Action $completionBlock -SourceIdentifier "WebClientComplete" | Out-Null

        # Start the download asynchronously to allow event handling
        $downloadTask = $webClient.DownloadFileTaskAsync($URL, $File)

        # Wait for the download task to complete
        while (-not $downloadTask.IsCompleted) {
            # Wait briefly to allow events to process without busy-waiting
            Start-Sleep -Milliseconds 100
        }

        # Check for errors during download
        if ($downloadTask.IsFaulted) {
            throw $downloadTask.Exception.InnerException
        }

        return $true # Indicate success

    } catch [System.Net.WebException] {
        $statusCode = if ($_.Exception.Response -ne $null) {
            [int]$_.Exception.Response.StatusCode
        } else {
            'N/A'
        }
        Write-Error "Web Error downloading '$($File | Split-Path -Leaf)': $($_.Exception.Message) (Status Code: $statusCode)"
        return $false # Indicate failure
    } catch {
        Write-Error "General Error downloading '$($File | Split-Path -Leaf)': $($_.Exception.Message)"
        return $false # Indicate failure
    } finally {
        # Unregister events and dispose WebClient
        Get-EventSubscriber -SourceIdentifier "WebClientProgress" | Unregister-Event -Force
        Get-EventSubscriber -SourceIdentifier "WebClientComplete" | Unregister-Event -Force
        if ($webClient -ne $null) {
            $webClient.Dispose()
        }
        # Ensure progress is marked as complete in ISE/VSCode if download was interrupted
         if (($psISE -or $Host.Name -match 'Visual Studio Code') -and (Get-Progress -Id 1 -EA SilentlyContinue)) {
             Write-Progress -Activity "Downloading File" -Status "Finalizing" -Id 1 -Completed
         } elseif (-not ($psISE -or $Host.Name -match 'Visual Studio Code')) {
            # Add a newline if not in ISE/VSCode to ensure next output is clean
             Write-Host ""
         }
    }
}

#endregion Helper Functions

#region Main Script Logic

# --- Step 1: Unblock NVIDIA DRS Files ---
Write-Host "Unblocking NVIDIA DRS files..." -ForegroundColor Yellow
$drsPath = "C:\ProgramData\NVIDIA Corporation\Drs"
if (Test-Path $drsPath) {
    try {
        Get-ChildItem -Path $drsPath -Recurse -File -ErrorAction Stop | Unblock-File -ErrorAction SilentlyContinue # Continue if some files fail
        Write-Host "DRS files unblocked (if any were blocked)." -ForegroundColor Green
    } catch {
        Write-Warning "Could not access or unblock files in '$drsPath'. Error: $($_.Exception.Message)"
    }
} else {
    Write-Host "NVIDIA DRS path '$drsPath' not found. Skipping unblock step." -ForegroundColor Cyan
}

# --- Step 2: Download Nvidia Profile Inspector ---
Write-Host "Checking/Downloading Nvidia Profile Inspector..." -ForegroundColor Yellow
$inspectorUrl = "https://github.com/FR33THYFR33THY/files/raw/main/Inspector.exe"
$inspectorExePath = Join-Path $env:TEMP "Inspector.exe"
$downloadSuccess = $false

# Check if file exists and is reasonably sized (e.g., > 100KB) to avoid re-downloading corrupted/empty files
if (Test-Path $inspectorExePath -PathType Leaf) {
    $fileInfo = Get-Item $inspectorExePath
    if ($fileInfo.Length -gt 100KB) {
        Write-Host "Inspector.exe already exists in TEMP. Skipping download." -ForegroundColor Green
        $downloadSuccess = $true
    } else {
        Write-Host "Existing Inspector.exe seems small/corrupt. Re-downloading." -ForegroundColor Yellow
        Remove-Item $inspectorExePath -Force -ErrorAction SilentlyContinue
        $downloadSuccess = Get-FileFromWeb -URL $inspectorUrl -File $inspectorExePath
    }
} else {
    $downloadSuccess = Get-FileFromWeb -URL $inspectorUrl -File $inspectorExePath
}

if (-not $downloadSuccess) {
    Write-Error "Failed to obtain Nvidia Profile Inspector. Cannot proceed."
    if (-not $env:CI) { Read-Host "Press Enter to exit" }
    Exit 1
}

# --- Step 3: Create Nvidia Profile Inspector Config ---
Write-Host "Creating profile configuration (Inspector_Recommended.nip)..." -ForegroundColor Yellow
$nipFilePath = Join-Path $env:TEMP "Inspector_Recommended.nip"
# XML configuration content
$nipContent = @"
<?xml version="1.0" encoding="utf-16"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName>Base Profile</ProfileName>
    <Executeables />
    <Settings>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>390467</SettingID>
        <SettingValue>2</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Negative LOD bias</SettingNameInfo>
        <SettingID>1686376</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Trilinear optimization</SettingNameInfo>
        <SettingID>3066610</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync Tear Control</SettingNameInfo>
        <SettingID>5912412</SettingID>
        <SettingValue>2525368439</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Preferred refresh rate</SettingNameInfo>
        <SettingID>6600001</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Maximum pre-rendered frames</SettingNameInfo>
        <SettingID>8102046</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Anisotropic filter optimization</SettingNameInfo>
        <SettingID>8703344</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync</SettingNameInfo>
        <SettingID>11041231</SettingID>
        <SettingValue>138504007</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Shader disk cache maximum size</SettingNameInfo>
        <SettingID>11306135</SettingID>
        <SettingValue>4294967295</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Quality</SettingNameInfo>
        <SettingID>13510289</SettingID>
        <SettingValue>20</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Anisotropic sample optimization</SettingNameInfo>
        <SettingID>15151633</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Display the VRR Indicator</SettingNameInfo>
        <SettingID>268604728</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Flag to control smooth AFR behavior</SettingNameInfo>
        <SettingID>270198627</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic filtering setting</SettingNameInfo>
        <SettingID>270426537</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Power management mode</SettingNameInfo>
        <SettingID>274197361</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Gamma correction</SettingNameInfo>
        <SettingID>276652957</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Mode</SettingNameInfo>
        <SettingID>276757595</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>FRL Low Latency</SettingNameInfo>
        <SettingID>277041152</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Frame Rate Limiter</SettingNameInfo>
        <SettingID>277041154</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Frame Rate Limiter for NVCPL</SettingNameInfo>
        <SettingID>277041162</SettingID>
        <SettingValue>357</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Toggle the VRR global feature</SettingNameInfo>
        <SettingID>278196567</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>VRR requested state</SettingNameInfo>
        <SettingID>278196727</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>G-SYNC</SettingNameInfo>
        <SettingID>279476687</SettingID>
        <SettingValue>4</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic filtering mode</SettingNameInfo>
        <SettingID>282245910</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Setting</SettingNameInfo>
        <SettingID>282555346</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>CUDA Sysmem Fallback Policy</SettingNameInfo>
        <SettingID>283962569</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable G-SYNC globally</SettingNameInfo>
        <SettingID>294973784</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>OpenGL GDI compatibility</SettingNameInfo>
        <SettingID>544392611</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Threaded optimization</SettingNameInfo>
        <SettingID>549528094</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <!-- Note: Preferred OpenGL GPU might need manual adjustment based on system -->
        <SettingNameInfo>Preferred OpenGL GPU</SettingNameInfo>
        <SettingID>550564838</SettingID>
        <SettingValue>id,2.0:268410DE,00000100,GF - (400,2,161,24564) @ (0)</SettingValue>
        <ValueType>String</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vulkan/OpenGL present method</SettingNameInfo>
        <SettingID>550932728</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
    </Settings>
  </Profile>
</ArrayOfProfile>
"@
try {
    # Use UTF16 encoding as specified in the XML declaration
    Set-Content -Path $nipFilePath -Value $nipContent -Encoding Unicode -Force -ErrorAction Stop
    Write-Host "Profile configuration saved." -ForegroundColor Green
} catch {
    Write-Error "Failed to save profile configuration '$nipFilePath'. Error: $($_.Exception.Message)"
    if (-not $env:CI) { Read-Host "Press Enter to exit" }
    Exit 1
}

# --- Step 4: Import Config using Inspector ---
Write-Host "Importing profile using Inspector..." -ForegroundColor Yellow
try {
    # Enclose argument path in quotes for safety
    $arguments = """$nipFilePath"""
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $inspectorExePath
    $processInfo.Arguments = $arguments
    $processInfo.UseShellExecute = $true # Use ShellExecute for .exe files

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $process.WaitForExit() # Wait for the inspector to finish

    if ($process.ExitCode -ne 0) {
        Write-Warning "Nvidia Profile Inspector exited with code $($process.ExitCode). Profile import might have failed."
    } else {
        Write-Host "Profile imported successfully." -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to run Nvidia Profile Inspector '$inspectorExePath' with '$nipFilePath'. Error: $($_.Exception.Message)"
    if (-not $env:CI) { Read-Host "Press Enter to exit" }
    Exit 1
}

# --- Step 5: Apply Registry Settings ---
Write-Host "Applying registry settings for legacy sharpen (EnableGR535 = 0)..." -ForegroundColor Yellow
$regValueName = "EnableGR535"
$regValueData = 0 # 0 = Enabled for legacy sharpen
$regValueType = [Microsoft.Win32.RegistryValueKind]::DWord

# Define registry paths relative to HKLM:\SYSTEM
$relativeRegPaths = @(
    "CurrentControlSet\Services\nvlddmkm\FTS",
    "CurrentControlSet\Services\nvlddmkm\Parameters\FTS",
    "ControlSet001\Services\nvlddmkm\Parameters\FTS" # Also attempt ControlSet001 for robustness
)

$regErrors = 0
foreach ($relPath in $relativeRegPaths) {
    $fullRegPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\$relPath"
    try {
        # Ensure the parent key exists
        $parentPath = Split-Path $fullRegPath
        if (-not (Test-Path $parentPath)) {
            Write-Host "Parent key '$parentPath' not found, skipping setting for '$fullRegPath'." -ForegroundColor Cyan
            continue
        }
        # Ensure the key itself exists (create if not)
        if (-not (Test-Path $fullRegPath)) {
            Write-Host "Creating registry key '$fullRegPath'..."
            New-Item -Path $fullRegPath -Force -ErrorAction Stop | Out-Null
        }
        # Set the value
        Set-ItemProperty -Path $fullRegPath -Name $regValueName -Value $regValueData -Type $regValueType -Force -ErrorAction Stop
        Write-Host "Successfully set '$regValueName' in '$fullRegPath'." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to set registry value '$regValueName' in '$fullRegPath'. Error: $($_.Exception.Message)"
        $regErrors++
    }
}

if ($regErrors -eq 0) {
    Write-Host "Registry settings applied successfully." -ForegroundColor Green
} else {
    Write-Warning "One or more registry settings failed to apply. Check warnings above."
}

# --- Step 6: Open NVIDIA Control Panel (Optional) ---
Write-Host "Attempting to open NVIDIA Control Panel..." -ForegroundColor Yellow
$nvidiaAppId = "NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel"
try {
    # Check if the UWP app exists first (requires Win10+)
    if (Get-AppxPackage -Name "NVIDIACorp.NVIDIAControlPanel") {
       Start-Process "shell:appsFolder\$nvidiaAppId" -ErrorAction Stop
       Write-Host "NVIDIA Control Panel launched." -ForegroundColor Green
    } else {
         Write-Warning "NVIDIA Control Panel (UWP version) not found. Cannot launch automatically."
    }
} catch {
    Write-Warning "Could not automatically open NVIDIA Control Panel. Error: $($_.Exception.Message). Please open it manually to verify settings."
}

# --- Step 7: Cleanup Temporary Files (Optional) ---
Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
Remove-Item $inspectorExePath -Force -ErrorAction SilentlyContinue
Remove-Item $nipFilePath -Force -ErrorAction SilentlyContinue
Write-Host "Temporary files removed." -ForegroundColor Green


Write-Host "`nScript finished. Recommended NVIDIA settings have been applied." -ForegroundColor White
# No explicit exit needed, script ends here.

#endregion Main Script Logic