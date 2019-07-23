<#
.SYNOPSIS
    Invoke Microsoft Update process.

.DESCRIPTION
    This script will invoke the Microsoft BIOS update process for the executable residing in the path specified for the Path parameter.

.PARAMETER Path
    Specify the path containing the Flash64W.exe and BIOS executable.

.PARAMETER LogFileName
    Set the name of the log file produced by the flash utility.

.EXAMPLE
    .\Invoke-MicrosoftBIOSUpdate.ps1 -LogFileName "LogFileName.log"

.NOTES
    FileName:    Invoke-MicrosoftBIOSUpdate.ps1
    Authors:     Maurice Daly
    Contact:     @modaly_it
    Created:     2019-07-11
    Updated:     2019-07-22
    
    Version history:
    1.0.0 - (2019-07-11) Script created (Maurice Daly)
	1.0.1 - (2019-07-22) Minor fixes
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$false, HelpMessage="Specify the path containing the Flash64W.exe and BIOS executable.")]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [parameter(Mandatory=$false, HelpMessage="Set the name of the log file produced by the flash utility.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogFileName = "MicrosoftBIOSUpdate.log"
)
Begin {
	# Load Microsoft.SMS.TSEnvironment COM object
	try {
		$TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object"
	}
}
Process {
	# Set Log Path
	$LogsDirectory = Join-Path $env:SystemRoot "Temp"
	
    # Functions
    function Write-CMLogEntry {
	    param(
		    [parameter(Mandatory=$true, HelpMessage="Value added to the log file.")]
		    [ValidateNotNullOrEmpty()]
		    [string]$Value,

		    [parameter(Mandatory=$true, HelpMessage="Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		    [ValidateNotNullOrEmpty()]
            [ValidateSet("1", "2", "3")]
		    [string]$Severity,

		    [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
		    [ValidateNotNullOrEmpty()]
		    [string]$FileName = "Invoke-MicrosoftBIOSUpdate.log"
	    )
	    # Determine log file location
        $LogFilePath = Join-Path -Path $TSEnvironment.Value("_SMSTSLogPath") -ChildPath $FileName

        # Construct time stamp for log entry
        $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))

        # Construct date for log entry
        $Date = (Get-Date -Format "MM-dd-yyyy")

        # Construct context for log entry
        $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)

        # Construct final log entry
        $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""DellBIOSUpdate.log"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
	
	    # Add value to log file
        try {
	        Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop 
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to append log entry to Invoke-DellBIOSUpdate.log file. Error message: $($_.Exception.Message)"
        }
    }
	
	function Invoke-Executable {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Specify the file name or path of the executable to be invoked, including the extension")]
			[ValidateNotNullOrEmpty()]
			[string]$FilePath,
			[parameter(Mandatory = $false, HelpMessage = "Specify arguments that will be passed to the executable")]
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
		if (-not ([System.String]::IsNullOrEmpty($Arguments))) {
			$SplatArgs.Add("ArgumentList", $Arguments)
		}
		
		# Invoke executable and wait for process to exit
		try {
			$Invocation = Start-Process @SplatArgs
			$Handle = $Invocation.Handle
			$Invocation.WaitForExit()
		}
		catch [System.Exception] {
			Write-Warning -Message $_.Exception.Message; break
		}
		
		return $Invocation.ExitCode
	}
	
	# Default to task sequence variable set in detection script
	if (-not([string]::IsNullOrEmpty($TSEnvironment.Value("OSDBIOSPackage01")))){
		Write-CMLogEntry -Value "Using BIOS package location set in OSDBIOSPackage01 TS variable" -Severity 1
		$OSDFirmwarePackageLocation = $TSEnvironment.Value("OSDBIOSPackage01")
	}
	
	# Run BIOS update process if BIOS package exists
	if (-not([string]::IsNullOrEmpty($OSDFirmwarePackageLocation))){
		# Write log file for script execution
		Write-CMLogEntry -Value "Initiating pnputil to apply firmware updates" -Severity 1
		$ApplyFirmwareInvocation = Invoke-Executable -FilePath "powershell.exe" -Arguments "pnputil /add-driver $(Join-Path -Path $OSDFirmwarePackageLocation -ChildPath '*.inf') /subdirs /install | Out-File -FilePath (Join-Path -Path $($LogsDirectory) -ChildPath 'Install-MicrosoftFirmware.txt') -Force"											
		}
	}
	else {
		Write-CMLogEntry -Value "Unable to determine BIOS package path." -Severity 2 ; exit 1
	}
}