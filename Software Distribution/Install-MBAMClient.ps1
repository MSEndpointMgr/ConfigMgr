# Functions
function Write-CMLogEntry {
    param (
        [parameter(Mandatory = $true, HelpMessage = "Value added to the log file.")]
        [ValidateNotNullOrEmpty()]
        [string]$Value,
        [parameter(Mandatory = $true, HelpMessage = "Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("1", "2", "3")]
        [string]$Severity,
        [parameter(Mandatory = $false, HelpMessage = "Name of the log file that the entry will written to.")]
        [ValidateNotNullOrEmpty()]
        [string]$FileName = "AppInstallation.log"
    )
    # Determine log file location
    $LogFilePath = Join-Path -Path $env:SystemRoot -ChildPath ("\Temp\" + $FileName)
    
    # Construct time stamp for log entry
    $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
    
    # Construct date for log entry
    $Date = (Get-Date -Format "MM-dd-yyyy")
    
    # Construct context for log entry
    $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    
    # Construct final log entry
    $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""AppInstallation"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
    
    # Add value to log file
    try {
        Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to append log entry to AppInstallation.log file. Error message: $($_.Exception.Message)"
    }
}

function Invoke-Executable {
    param(
        [parameter(Mandatory=$true, HelpMessage="Specify the file name or path of the executable to be invoked, including the extension")]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [parameter(Mandatory=$false, HelpMessage="Specify arguments that will be passed to the executable")]
        [ValidateNotNull()]
        [string]$Arguments
    )

    # Construct a hash-table for default parameter splatting
    $SplatArgs = @{
        FilePath = $FilePath
        NoNewWindow = $true
        Passthru = $true
        ErrorAction = "Stop"
    }

    # Add ArgumentList param if present
    if (-not([System.String]::IsNullOrEmpty($Arguments))) {
        $SplatArgs.Add("ArgumentList", $Arguments)
    }

    # Invoke executable and wait for process to exit
    try {
        $Invocation = Start-Process @SplatArgs
        $Handle = $Invocation.Handle
        $Invocation.WaitForExit()
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message ; break
    }

    return $Invocation.ExitCode
}

# Detect OS architecture
$OSArchitecture = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty OSArchitecture
switch ($OSArchitecture) {
    "64-bit" {
        $OSArch = "x64"
    }
    "32-bit" {
        $OSArch = "x86"
    }
}

# Application details
$ApplicationName = "Microsoft MBAM 2.5 SP1 Client with KB4018510"
$MSIFileName = "MbamClientSetup-2.5.1100.0_$($OSArch).msi"
$MSPFileName = "MBAM2.5_Client_$($OSArch)_KB4018510.msp"

# Initiate application installation logging
Write-CMLogEntry -Value "Initiating application installation" -Severity 1

# Get current working directory
$CurrentWorkingDir = $PSScriptRoot
Write-CMLogEntry -Value "Current working directory: $($CurrentWorkingDir)" -Severity 1

# Check if MBAM Client is installed
$MBAMClientInstallState = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\MBAM" -Name Installed -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Installed

# Build arguments for install command
if ($MBAMClientInstallState -eq 1) {
    $ArgumentList = "/p $(Join-Path -Path $CurrentWorkingDir -ChildPath $MSPFileName) /qn REBOOT=ReallySuppress"
}
else {
    $ArgumentList = "/i $(Join-Path -Path $CurrentWorkingDir -ChildPath $MSIFileName) /update $(Join-Path -Path $CurrentWorkingDir -ChildPath $MSPFileName) /qn REBOOT=ReallySuppress"
}
Write-CMLogEntry -Value "Command line arguments for msiexec.exe: $($ArgumentList)" -Severity 1

# Invoke command line for installation
Write-CMLogEntry -Value "Starting installation of $($ApplicationName)" -Severity 1
$Invocation = Invoke-Executable -FilePath msiexec.exe -Arguments $ArgumentList

# Exit with return code from invocation
Write-CMLogEntry -Value "Return code from installation was '$($Invocation)'" -Severity 1
exit $Invocation