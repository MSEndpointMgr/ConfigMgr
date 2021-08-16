<#
.SYNOPSIS
    Clear the TPM ownership during OSD with ConfigMgr.

.DESCRIPTION
	This script can both detect the current ownership state of the TPM module and clear the ownership. The script has been designed to
	run as a two-step implementation. Firstly detecting the current state using the DetectState value for the Action parameter. If the TPM
	is owned, a task sequence parameter named IsTPMOwned is set with a value of TRUE. Second step is to clear the TPM module using the
	Clear value for the Action parameter. Once the script has completed, another task sequence variable named IsTPMRestartRequired is
	set to TRUE. This can then be used to determine if a Restart Computer step should be used to restart the computer.

.PARAMETER Action
	Specify an action to either detect the ownership state or clear the ownership information from the TPM module.

.EXAMPLE
	# Detect whether the TPM module is owned:
	.\Invoke-ManageTPMOwnership.ps1 -Action DetectState
	
	# Clear the TPM module:
    .\Invoke-ManageTPMOwnership.ps1 -Action Clear

.NOTES
    FileName:    Invoke-ManageTPMOwnership.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2018-01-30
    Updated:     2018-04-04
    
    Version history:
	1.0.0 - (2018-01-30) Script created
	1.0.1 - (2018-04-04) Updated script with vendor specific SetPhysicalPresence method execution
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Specify an action to either detect the ownership state or clear the ownership information from the TPM module.")]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("Clear", "DetectState")]
    [string]$Action
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
			[string]$FileName = "TPMManagement.log"
		)
		# Determine log file location
		$LogFilePath = Join-Path -Path $env:SystemRoot -ChildPath "\Temp\$($FileName)"
		
		# Construct time stamp for log entry
		$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
		
		# Construct date for log entry
		$Date = (Get-Date -Format "MM-dd-yyyy")
		
		# Construct context for log entry
		$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		
		# Construct final log entry
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""TPMManagement"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file
		try {
			Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to TPMManagement.log file. Error message: $($_.Exception.Message)"
		}
	}

	# Load TPM module class
	try {
		$TPMModule = Get-WmiObject -Namespace "root\cimv2\Security\MicrosoftTpm" -Class Win32_TPM -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "Unable to load TPM class. Error message: $($_.Exception.Message)" -Severity 2
	}

	# Check if TPM is present and enabled
	if ($TPMModule -ne $null) {
		switch ($Action) {
			"Clear" {
				# Check if TPM is enabled
				if (-not($TPMModule.IsEnabled())) {
					Write-CMLogEntry -Value "TPM module is not enabled, bailing out" -Severity 3; break
				}

				# Attempt to clear TPM ownership
				if ($TPMModule.IsOwned()) {
					Write-CMLogEntry -Value "Attempting to clear TPM ownership" -Severity 1

					# https://msdn.microsoft.com/en-us/library/windows/desktop/aa376478(v=vs.85).aspx
					$ComputerManufacturer = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer
					switch -Wildcard ($ComputerManufacturer) {
						"*Dell*" {
							$Invocation = $TPMModule.SetPhysicalPresenceRequest(14) # Enable, activate and clear TPM ownership
						}
						"*Hewlett-Packard*" {
							$Invocation = $TPMModule.SetPhysicalPresenceRequest(10) # Enable, activate and clear TPM ownership
						}
						"*HP*" {
							$Invocation = $TPMModule.SetPhysicalPresenceRequest(10) # Enable, activate and clear TPM ownership
						}
					}

					if ($Invocation.ReturnValue -eq 0) {
						Write-CMLogEntry -Value "Successfully cleared TPM ownership, restart required" -Severity 1
						$TSEnvironment.Value("IsTPMRestartRequired") = "TRUE"
					}
					else {
						Write-CMLogEntry -Value "Unhandled exception occurred, bailing out with exit code 1" -Severity 3; exit 1
					}
				}
			}
			"DetectState" {
				# Check if TPM is enabled
				if (-not($TPMModule.IsEnabled())) {
					Write-CMLogEntry -Value "TPM module is not enabled, bailing out" -Severity 3; break
				}

				# Set task sequence variable for TPM ownership state
				if ($TPMModule.IsOwned()) {
					$TSEnvironment.Value("IsTPMOwned") = "TRUE"
				}
				else {
					$TSEnvironment.Value("IsTPMOwned") = "FALSE"
				}
			}
		}
	}
	else {
		Write-CMLogEntry -Value "TPM module class was not found, empty list of instances was returned" -Severity 2
	}
}