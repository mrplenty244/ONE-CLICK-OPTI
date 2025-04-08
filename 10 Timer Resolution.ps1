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
$ErrorActionPreference = 'SilentlyContinue' # Also suppress non-terminating errors globally

# Define paths and service name
$csFilePath = Join-Path $env:SystemDrive "Windows\SetTimerResolutionService.cs"
$exeFilePath = Join-Path $env:SystemDrive "Windows\SetTimerResolutionService.exe"
$serviceName = "Set Timer Resolution Service" # Match display name used later
$serviceInternalName = "STR" # Internal service name from C# code

# --- Step 1: Create C# Source File ---
$csSourceCode = @"
using System;
using System.Runtime.InteropServices;
using System.ServiceProcess;
using System.ComponentModel;
using System.Configuration.Install;
using System.Collections.Generic;
using System.Reflection;
using System.IO;
using System.Management;
using System.Threading;
using System.Diagnostics;
[assembly: AssemblyVersion("2.1")]
[assembly: AssemblyProduct("Set Timer Resolution service")]
namespace WindowsService
{
    class WindowsService : ServiceBase
    {
        public WindowsService()
        {
            this.ServiceName = "STR"; // Internal name
            this.EventLog.Log = "Application";
            this.CanStop = true;
            this.CanHandlePowerEvent = false;
            this.CanHandleSessionChangeEvent = false;
            this.CanPauseAndContinue = false;
            this.CanShutdown = false;
        }
        static void Main()
        {
            ServiceBase.Run(new WindowsService());
        }
        protected override void OnStart(string[] args)
        {
            base.OnStart(args);
            ReadProcessList();
            NtQueryTimerResolution(out this.MininumResolution, out this.MaximumResolution, out this.DefaultResolution);
            if(null != this.EventLog)
                try { this.EventLog.WriteEntry(String.Format("Minimum={0}; Maximum={1}; Default={2}; Processes='{3}'", this.MininumResolution, this.MaximumResolution, this.DefaultResolution, null != this.ProcessesNames ? String.Join("','", this.ProcessesNames) : "")); }
                catch {}
            if(null == this.ProcessesNames)
            {
                SetMaximumResolution();
                return;
            }
            if(0 == this.ProcessesNames.Count)
            {
                return;
            }
            this.ProcessStartDelegate = new OnProcessStart(this.ProcessStarted);
            try
            {
                String query = String.Format("SELECT * FROM __InstanceCreationEvent WITHIN 0.5 WHERE (TargetInstance isa \"Win32_Process\") AND (TargetInstance.Name=\"{0}\")", String.Join("\" OR TargetInstance.Name=\"", this.ProcessesNames));
                this.startWatch = new ManagementEventWatcher(query);
                this.startWatch.EventArrived += this.startWatch_EventArrived;
                this.startWatch.Start();
            }
            catch(Exception ee)
            {
                if(null != this.EventLog)
                    try { this.EventLog.WriteEntry(ee.ToString(), EventLogEntryType.Error); }
                    catch {}
            }
        }
        protected override void OnStop()
        {
            if(null != this.startWatch)
            {
                this.startWatch.Stop();
            }

            base.OnStop();
        }
        ManagementEventWatcher startWatch;
        void startWatch_EventArrived(object sender, EventArrivedEventArgs e)
        {
            try
            {
                ManagementBaseObject process = (ManagementBaseObject)e.NewEvent.Properties["TargetInstance"].Value;
                UInt32 processId = (UInt32)process.Properties["ProcessId"].Value;
                this.ProcessStartDelegate.BeginInvoke(processId, null, null);
            }
            catch(Exception ee)
            {
                if(null != this.EventLog)
                    try { this.EventLog.WriteEntry(ee.ToString(), EventLogEntryType.Warning); }
                    catch {}

            }
        }
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern Int32 WaitForSingleObject(IntPtr Handle, Int32 Milliseconds);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern IntPtr OpenProcess(UInt32 DesiredAccess, Int32 InheritHandle, UInt32 ProcessId);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern Int32 CloseHandle(IntPtr Handle);
        const UInt32 SYNCHRONIZE = 0x00100000;
        delegate void OnProcessStart(UInt32 processId);
        OnProcessStart ProcessStartDelegate = null;
        void ProcessStarted(UInt32 processId)
        {
            SetMaximumResolution();
            IntPtr processHandle = IntPtr.Zero;
            try
            {
                processHandle = OpenProcess(SYNCHRONIZE, 0, processId);
                if(processHandle != IntPtr.Zero)
                    WaitForSingleObject(processHandle, -1);
            }
            catch(Exception ee)
            {
                if(null != this.EventLog)
                    try { this.EventLog.WriteEntry(ee.ToString(), EventLogEntryType.Warning); }
                    catch {}
            }
            finally
            {
                if(processHandle != IntPtr.Zero)
                    CloseHandle(processHandle);
            }
            SetDefaultResolution();
        }
        List<String> ProcessesNames = null;
        void ReadProcessList()
        {
            String iniFilePath = Assembly.GetExecutingAssembly().Location + ".ini";
            if(File.Exists(iniFilePath))
            {
                this.ProcessesNames = new List<String>();
                String[] iniFileLines = File.ReadAllLines(iniFilePath);
                foreach(var line in iniFileLines)
                {
                    String[] names = line.Split(new char[] {',', ' ', ';'} , StringSplitOptions.RemoveEmptyEntries);
                    foreach(var name in names)
                    {
                        String lwr_name = name.ToLower();
                        if(!lwr_name.EndsWith(".exe"))
                            lwr_name += ".exe";
                        if(!this.ProcessesNames.Contains(lwr_name))
                            this.ProcessesNames.Add(lwr_name);
                    }
                }
            }
        }
        [DllImport("ntdll.dll", SetLastError=true)]
        static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);
        [DllImport("ntdll.dll", SetLastError=true)]
        static extern int NtQueryTimerResolution(out uint MinimumResolution, out uint MaximumResolution, out uint ActualResolution);
        uint DefaultResolution = 0;
        uint MininumResolution = 0;
        uint MaximumResolution = 0;
        long processCounter = 0;
        void SetMaximumResolution()
        {
            long counter = Interlocked.Increment(ref this.processCounter);
            if(counter <= 1)
            {
                uint actual = 0;
                NtSetTimerResolution(this.MaximumResolution, true, out actual);
                if(null != this.EventLog)
                    try { this.EventLog.WriteEntry(String.Format("Actual resolution = {0}", actual)); }
                    catch {}
            }
        }
        void SetDefaultResolution()
        {
            long counter = Interlocked.Decrement(ref this.processCounter);
            if(counter < 1)
            {
                uint actual = 0;
                NtSetTimerResolution(this.DefaultResolution, true, out actual);
                if(null != this.EventLog)
                    try { this.EventLog.WriteEntry(String.Format("Actual resolution = {0}", actual)); }
                    catch {}
            }
        }
    }
    [RunInstaller(true)]
    public class WindowsServiceInstaller : Installer
    {
        public WindowsServiceInstaller()
        {
            ServiceProcessInstaller serviceProcessInstaller =
                               new ServiceProcessInstaller();
            ServiceInstaller serviceInstaller = new ServiceInstaller();
            serviceProcessInstaller.Account = ServiceAccount.LocalSystem;
            serviceProcessInstaller.Username = null;
            serviceProcessInstaller.Password = null;
            serviceInstaller.DisplayName = "Set Timer Resolution Service"; // Display Name
            serviceInstaller.StartType = ServiceStartMode.Automatic;
            serviceInstaller.ServiceName = "STR"; // Internal Name
            this.Installers.Add(serviceProcessInstaller);
            this.Installers.Add(serviceInstaller);
        }
    }
}
"@
try {
    Set-Content -Path $csFilePath -Value $csSourceCode -Force -Encoding UTF8 # UTF8 is generally fine for C#
} catch {
    # Failed to write source file, cannot proceed
    Exit 2
}

# --- Step 2: Compile C# Code ---
# Determine CSC path dynamically - prefer Framework64 but fallback to Framework
$cscPath = ""
$frameworkPaths = @(
    (Join-Path $env:SystemRoot "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:SystemRoot "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
foreach ($path in $frameworkPaths) {
    if (Test-Path $path) {
        $cscPath = $path
        break
    }
}

if (-not $cscPath) {
    # CSC not found, cannot compile
    if (Test-Path $csFilePath) { Remove-Item $csFilePath -Force -ErrorAction SilentlyContinue }
    Exit 3
}

try {
    # Compile silently
    $process = Start-Process -FilePath $cscPath -ArgumentList "-nologo -out:`"$exeFilePath`" `"$csFilePath`"" -Wait -WindowStyle Hidden -PassThru -ErrorAction Stop
    if ($process.ExitCode -ne 0) {
        # Compilation failed
        throw "CSC compilation failed with exit code $($process.ExitCode)"
    }
} catch {
    # Handle compilation failure
    if (Test-Path $csFilePath) { Remove-Item $csFilePath -Force -ErrorAction SilentlyContinue }
    Exit 4
}

# --- Step 3: Delete Source File ---
if (Test-Path $csFilePath) {
    Remove-Item $csFilePath -Force -ErrorAction SilentlyContinue
}

# --- Step 4: Install and Start Service ---
# Check if service exists first to decide between New-Service and ensuring it's running
$service = Get-Service -Name $serviceInternalName -ErrorAction SilentlyContinue

if (-not $service) {
    try {
        # Use DisplayName matching the one in C# installer code
        New-Service -Name $serviceInternalName -BinaryPathName $exeFilePath -DisplayName $serviceName -StartupType Automatic -ErrorAction Stop | Out-Null
        Start-Service -Name $serviceInternalName -ErrorAction SilentlyContinue # Attempt to start after creation
    } catch {
        # Failed to create/start service
        if (Test-Path $exeFilePath) { Remove-Item $exeFilePath -Force -ErrorAction SilentlyContinue }
        Exit 5
    }
} else {
    # Service exists, ensure it's configured correctly and running
    try {
        Set-Service -Name $serviceInternalName -StartupType Automatic -ErrorAction Stop
        # Only start if not already running or starting
        if ($service.Status -ne 'Running' -and $service.Status -ne 'StartPending') {
             Start-Service -Name $serviceInternalName -ErrorAction SilentlyContinue
        }
    } catch {
         # Failed to configure/start existing service
         Exit 6
    }
}

# --- Final Step: Exit ---
Exit 0

#endregion Main Script Logic