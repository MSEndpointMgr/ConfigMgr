<#
.SYNOPSIS
    Invoke Dell BIOS Update process.

.DESCRIPTION
    This script will invoke the Dell BIOS update process for the executable residing in the path specified for the Path parameter.

.PARAMETER Path
    Specify the path containing the Flash64W.exe and BIOS executable.

.PARAMETER Password
    Specify the BIOS password if necessary.

.PARAMETER LogFileName
    Set the name of the log file produced by the flash utility.

.EXAMPLE
    .\Invoke-DellBIOSUpdate.ps1 -Password "BIOSPassword" -LogFileName "LogFileName.log"

.NOTES
    FileName:    Invoke-DellBIOSUpdate.ps1
    Authors:     Maurice Daly & Nickolaj Andersen
    Contact:     @modaly_it
    Created:     2017-05-30
    Updated:     2019-05-14
    
    Version history:
    1.0.0 - (2017-05-30) Script created (Maurice Daly)
	1.0.1 - (2017-06-01) Additional checks for both in OSD and normal OS environments (Maurice Daly)
	1.0.2 - (2017-06-07) Fixed bug in legacy update method (Maurice Daly)
	1.0.3 - (2017-06-26) Added checks for Flash64W.exe utility and BIOS file presence including some additional logging (Nickolaj Andersen)
	1.0.4 - (2017-06-30) Fixed an issue where the password was not passed to Flash64W.exe utility. Added logging for this script to a separate file (Nickolaj Andersen)
	1.0.5 - (2017-07-04) Configured Flash64W.exe as the native update tool for 64-bit Full OS deployments
	1.0.6 - (2018-12-04) Variable name correction in example. No functional changes
	1.0.7 - (2019-02-05) Removed requirement for OSDBIOSPackage01 variable. Script will now default to this value.
						 Added registry stamping function
	1.0.8 - (2019-03-02) Updated path and task sequence handling
	1.0.9 - (2019-05-01) Removed the /f switch that bypasses the model check and could possibly incorrectly flash the system with a wrong BIOS package if Dell somehow messes up with the downloaded bits
	1.1.0 - (2019-05-14) Handle log output correctly if $Password is not specified
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$false, HelpMessage="Specify the path containing the Flash64W.exe and BIOS executable.")]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [parameter(Mandatory=$false, HelpMessage="Specify the BIOS password if necessary.")]
    [ValidateNotNullOrEmpty()]
    [string]$Password,

    [parameter(Mandatory=$false, HelpMessage="Set the name of the log file produced by the flash utility.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogFileName = "DellFlashBIOSUpdate.log"
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
		    [string]$FileName = "Invoke-DellBIOSUpdate.log"
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
	
	# Default to task sequence variable set in detection script
	if (-not([string]::IsNullOrEmpty($TSEnvironment.Value("OSDBIOSPackage01")))){
		Write-CMLogEntry -Value "Using BIOS package location set in OSDBIOSPackage01 TS variable" -Severity 1
		$Path = $TSEnvironment.Value("OSDBIOSPackage01")
	}
	
	# Run BIOS update process if BIOS package exists
	if (-not([string]::IsNullOrEmpty($Path))){

		# Write log file for script execution
		Write-CMLogEntry -Value "Initiating script to determine flashing capabilities for Dell BIOS updates" -Severity 1

		# Flash BIOS upgrade utility file name
		$FlashUtility = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "Flash64W.exe" } | Select-Object -ExpandProperty FullName
		Write-CMLogEntry -Value "Attempting to use flash utility: $($FlashUtility)" -Severity 1

		if ($FlashUtility -ne $null) {
			# Detect BIOS update executable
			$CurrentBIOSFile = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -notlike ($FlashUtility | Split-Path -leaf) } | Select-Object -ExpandProperty FullName
			Write-CMLogEntry -Value "Attempting to use BIOS update file: $($CurrentBIOSFile)" -Severity 1	

			if ($CurrentBIOSFile -ne $null) {
				# Set log file location
				$BIOSLogFile = Join-Path -Path $TSEnvironment.Value("_SMSTSLogPath") -ChildPath $LogFileName

				# Set required switches for silent upgrade of the bios and logging
				$FlashSwitches = "/b=$($CurrentBIOSFile) /s /l=$($BIOSLogFile)"

				# Add password to the Flash64W.exe switches
				if ($PSBoundParameters["Password"]) {
					if (-not([System.String]::IsNullOrEmpty($Password))) {
						$FlashSwitches = $FlashSwitches + " /p=$($Password)"
					}
				}	

				if (($TSEnvironment -ne $null) -and ($TSEnvironment.Value("_SMSTSinWinPE") -eq $true)) {
					Write-CMLogEntry -Value "Current environment is determined as WinPE" -Severity 1

					try {
						# Start flash update process
						if (-not([System.String]::IsNullOrEmpty($Password))) {
							Write-CMLogEntry -Value "Using the following switches for Flash64W.exe: $($FlashSwitches -replace $Password, "<password removed>")" -Severity 1
						}
						else {
							Write-CMLogEntry -Value "Using the following switches for Flash64W.exe: $($FlashSwitches)" -Severity 1
						}
						$FlashProcess = Start-Process -FilePath $FlashUtility -ArgumentList $FlashSwitches -Passthru -Wait -ErrorAction Stop
						
						# Set reboot flag if restart required determined (exit code 2)
						if ($FlashProcess.ExitCode -match "0|2") {
							# Set reboot required flag
							$TSEnvironment.Value("SMSTSBIOSUpdateRebootRequired") = "True"
							$TSEnvironment.Value("SMSTSBIOSInOSUpdateRequired") = "False"
						}
						elseif ($FlashProcess.ExitCode -eq "10") {
							Write-CMLogEntry -Value "Laptop is on battery power. The AC power must be connected to successfully flash the BIOS." -Severity 3; exit 1
						}
						else {
							Write-CMLogEntry -Value "An error occured while updating the system BIOS during OS offline phase. Please review the log file located at $($BIOSLogFile)" -Severity 3; exit 1
						}
						
					}
					catch [System.Exception] {
						Write-CMLogEntry -Value "An error occured while updating the system BIOS during OS offline phase. Error message: $($_.Exception.Message)" -Severity 3 ; exit 1
					}
				}
				else {
					# Used as a fall back for systems that do not support the Flash64w update tool
					# Used in a later section of the task sequence (after Setup Windows and ConfigMgr step)

					Write-CMLogEntry -Value "Current environment is determined as FullOS" -Severity 1
					
					# Detect Bitlocker Status
					$OSVolumeEncypted = if ((Manage-Bde -Status C:) -match "Protection On") { Write-Output $true } else { Write-Output $false }
					
					# Supend Bitlocker if $OSVolumeEncypted is $true, remember to re-enable BitLocker after the flashing has occurred
					if ($OSVolumeEncypted -eq $true) {
						Write-CMLogEntry -Value "Suspending BitLocker protected volume: C:" -Severity 1
						Manage-Bde -Protectors -Disable C:
					}
					
					# Start BIOS update process
					try {
						if (([Environment]::Is64BitOperatingSystem) -eq $true) {
							Write-CMLogEntry -Value "Starting 64-bit flash BIOS update process" -Severity 1
							if (-not([System.String]::IsNullOrEmpty($Password))) {
								Write-CMLogEntry -Value "Using the following switches for Flash64W.exe: $($FlashSwitches -replace $Password, "<password removed>")" -Severity 1
							}
							else {
								Write-CMLogEntry -Value "Using the following switches for Flash64W.exe: $($FlashSwitches)" -Severity 1
							}

							# Update BIOS using Flash64W.exe
							$FlashUpdate = Start-Process -FilePath $FlashUtility -ArgumentList $FlashSwitches -Passthru -Wait -ErrorAction Stop
						}
						else {
							# Set required switches for silent upgrade of the BIOS
							$FileSwitches = " /l=$($BIOSLogFile) /s"

							# Add password to switches
							if ($PSBoundParameters["Password"]) {
								if (-not([System.String]::IsNullOrEmpty($Password))) {
									$FileSwitches = $FileSwitches + " /p=$($Password)"
								}
							}

							Write-CMLogEntry -Value "Starting 32-bit flash BIOS update process" -Severity 1
							if (-not([System.String]::IsNullOrEmpty($Password))) {
								Write-CMLogEntry -Value "Using the following switches for BIOS file: $($FlashSwitches -replace $Password, "<password removed>")" -Severity 1
							}
							else {
								Write-CMLogEntry -Value "Using the following switches for BIOS file: $($FlashSwitches)" -Severity 1
							}

							# Update BIOS using update file
							$FileUpdate = Start-Process -FilePath $CurrentBIOSFile -ArgumentList $FileSwitches -PassThru -Wait -ErrorAction Stop
						}
						
					}
					catch [System.Exception] {
						Write-CMLogEntry -Value "An error occured while updating the system BIOS in OS online phase. Error message: $($_.Exception.Message)" -Severity 3; exit 1
					}
				}
			}
			else {
				Write-CMLogEntry -Value "Unable to locate the current BIOS update file" -Severity 2 ; exit 1
			}
		}
		else {
			Write-CMLogEntry -Value "Unable to locate the Flash64W.exe utility" -Severity 2 ; exit 1
		}
	}
	else {
		Write-CMLogEntry -Value "Unable to determine BIOS package path." -Severity 2 ; exit 1
	}
}