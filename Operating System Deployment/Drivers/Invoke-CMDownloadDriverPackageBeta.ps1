<#
.SYNOPSIS
    Download driver package (regular package) matching computer model, manufacturer and operating system.
.DESCRIPTION
    This script will determine the model of the computer, manufacturer and operating system being deployed and then query 
    the specified endpoint for ConfigMgr WebService for a list of Packages. It then sets the OSDDownloadDownloadPackages variable 
    to include the PackageID property of a package matching the computer model. If multiple packages are detect, it will select
    most current one by the creation date of the packages.
.PARAMETER URI
    Set the URI for the ConfigMgr WebService.
.PARAMETER SecretKey
    Specify the known secret key for the ConfigMgr WebService.
.PARAMETER Filter
    Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.
.EXAMPLE
    .\Invoke-CMDownloadDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers"
.NOTES
    FileName:    Invoke-CMDownloadDriverPackage.ps1
    Author:      Nickolaj Andersen / Maurice Daly
    Contact:     @NickolajA / @MoDaly_IT
    Created:     2017-03-27
	Updated:     2017-09-15
	
	Minimum required version of ConfigMgr WebService: 1.4.0
    
    Version history:
    1.0.0 - (2017-03-27) Script created
    1.0.1 - (2017-04-18) Updated script with better support for multiple vendor entries
    1.0.2 - (2017-04-22) Updated script with support for multiple operating systems driver packages, e.g. Windows 8.1 and Windows 10
    1.0.3 - (2017-05-03) Updated script with support for manufacturer specific Windows 10 versions for HP and Microsoft
    1.0.4 - (2017-05-04) Updated script to trim any white spaces trailing the computer model detection from WMI
    1.0.5 - (2017-05-05) Updated script to pull the model for Lenovo systems from the correct WMI class
    1.0.6 - (2017-05-22) Updated script to detect the proper package based upon OS Image version referenced in task sequence when multiple packages are detected
    1.0.7 - (2017-05-26) Updated script to filter OS when multiple model matches are found for different OS platforms
    1.0.8 - (2017-06-26) Updated script with improved computer name matching when filtering out packages returned from the web service
    1.0.9 - (2017-08-25) Updated script to read package description for Microsoft models in order to match the WMI value contained within
    1.1.0 - (2017-08-29) Updated script to only check for the OS build version instead of major, minor, build and revision for HP systems.
                         $OSImageVersion will now only contain the most recent version if multiple OS images is referenced in the Task Sequence.
    1.1.1 - (2017-09-12) Updated script to match the system SKU for Dell, Lenovo and HP models. Added architecture check for matching packages.
	1.1.2 - (2017-09-15) Rearranged detection to check SKU earlier
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[parameter(Mandatory = $true, HelpMessage = "Set the URI for the ConfigMgr WebService.")]
	[ValidateNotNullOrEmpty()]
	[string]$URI,
	[parameter(Mandatory = $true, HelpMessage = "Specify the known secret key for the ConfigMgr WebService.")]
	[ValidateNotNullOrEmpty()]
	[string]$SecretKey,
	[parameter(Mandatory = $false, HelpMessage = "Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.")]
	[ValidateNotNullOrEmpty()]
	[string]$Filter = [System.String]::Empty
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
			[string]$FileName = "DriverPackageDownload.log"
		)
		# Determine log file location
		$LogFilePath = Join-Path -Path $Script:TSEnvironment.Value("_SMSTSLogPath") -ChildPath $FileName
		
		# Construct time stamp for log entry
		$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
		
		# Construct date for log entry
		$Date = (Get-Date -Format "MM-dd-yyyy")
		
		# Construct context for log entry
		$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		
		# Construct final log entry
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""DriverPackageDownloader"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file
		try {
			Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to DriverPackageDownload.log file. Error message: $($_.Exception.Message)"
		}
	}
	
	# Write log file for script execution
	Write-CMLogEntry -Value "Driver download package process initiated" -Severity 1
	
	# Determine manufacturer
	$ComputerManufacturer = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer).Trim()
	Write-CMLogEntry -Value "Manufacturer determined as: $($ComputerManufacturer)" -Severity 1
	
	# Determine manufacturer name and computer model
	switch -Wildcard ($ComputerManufacturer) {
		"*Microsoft*" {
			$ComputerManufacturer = "Microsoft"
			$ComputerModel = Get-WmiObject -Namespace root\wmi -Class MS_SystemInformation | Select-Object Expand-Property SystemSKU
		}
		"*HP*" {
			$ComputerManufacturer = "Hewlett-Packard"
			$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
			$SystemSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).BaseBoardProduct
		}
		"*Hewlett-Packard*" {
			$ComputerManufacturer = "Hewlett-Packard"
			$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
			$SystemSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).BaseBoardProduct
		}
		"*Dell*" {
			$ComputerManufacturer = "Dell"
			$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
			$SystemSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).SystemSku
		}
		"*Lenovo*" {
			$ComputerManufacturer = "Lenovo"
			$ComputerModel = Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version
			$SystemSKU = ((Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model).SubString(0, 4)).Trim()
		}
		"*Acer*" {
			# Unconfirmed
			$ComputerManufacturer = "Acer"
			$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
		}
	}
	Write-CMLogEntry -Value "Computer model determined as: $($ComputerModel)" -Severity 1
	if (![string]::IsNullOrEmpty($SystemSKU)) {
		Write-CMLogEntry -Value "Computer SKU determined as: $($SystemSKU)" -Severity 1
	}
	
	# Construct array list for matching packages
	$PackageList = New-Object -TypeName System.Collections.ArrayList
	
	# Set script error preference variable
	$ErrorActionPreference = "Stop"
	
	# Construct new web service proxy
	try {
		$WebService = New-WebServiceProxy -Uri $URI -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "Unable to establish a connection to ConfigMgr WebService. Error message: $($_.Exception.Message)" -Severity 3; exit 1
	}
	
	# Call web service for a list of packages
	try {
		$Packages = $WebService.GetCMPackage($SecretKey, $Filter)
		Write-CMLogEntry -Value "Retrieved a total of $(($Packages | Measure-Object).Count) driver packages from web service" -Severity 1
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "An error occured while calling ConfigMgr WebService for a list of available packages. Error message: $($_.Exception.Message)" -Severity 3; exit 1
	}
	
	# Determine OS Image version for running task sequence from web service
	try {
		$TSPackageID = $TSEnvironment.Value("_SMSTSPackageID")
		$OSImageVersion = $WebService.GetCMOSImageVersionForTaskSequence($SecretKey, $TSPackageID) | Sort-Object -Descending | Select-Object -First 1
		Write-CMLogEntry -Value "Retrieved OS Image version from web service: $($OSImageVersion)" -Severity 1
		
		# Get operating system name from version
		switch -Wildcard ($OSImageVersion) {
			"10.0*" {
				$OSName = "Windows 10"
			}
			"6.3*" {
				$OSName = "Windows 8.1"
			}
			"6.1*" {
				$OSName = "Windows 7"
			}
		}
		Write-CMLogEntry -Value "Determined OS name from version: $($OSName)" -Severity 1
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "An error occured while calling ConfigMgr WebService to determine OS Image version. Error message: $($_.Exception.Message)" -Severity 3; exit 1
	}
	
	# Determine OS Image architecture for running task sequence from web service
	try {
		$OSImageArchitecture = $WebService.GetCMOSImageArchitectureForTaskSequence($SecretKey, $TSPackageID) | Sort-Object -Descending | Select-Object -First 1
		Write-CMLogEntry -Value "Retrieved OS Image architecture from web service: $($OSImageArchitecture)" -Severity 1
		
		# Translate operating system architecture from web service response
		switch ($OSImageArchitecture) {
			"9" {
				$OSImageArchitecture = "x64"
			}
			"0" {
				$OSImageArchitecture = "x86"
			}
		}
		Write-CMLogEntry -Value "Translated OS Image architecture: $($OSImageArchitecture)" -Severity 1
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "An error occured while calling ConfigMgr WebService to determine OS Image architecture. Error message: $($_.Exception.Message)" -Severity 3; exit 1
	}
	
	# Validate operating system name was detected
	if ($OSName -ne $null) {
		# Validate not virtual machine
		$ComputerSystemType = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty "Model"
		if ($ComputerSystemType -notin @("Virtual Machine", "VMware Virtual Platform", "VirtualBox", "HVM domU", "KVM")) {
			# Process packages returned from web service
			if ($Packages -ne $null) {
				foreach ($Package in $Packages) {
					
					# Match model, manufacturer criteria
					if (($Package.PackageDescription -match $SystemSKU) -and ($ComputerManufacturer -match $Package.PackageManufacturer) -and ($Package.PackageName -match $OSName) -and ($Package.PackageName -match $OSImageArchitecture)) {
						# Match operating system criteria per manufacturer for Windows 10 packages only
						if ($OSName -like "Windows 10") {
							switch ($ComputerManufacturer) {
								"Hewlett-Packard" {
									if ($Package.PackageName -match ([System.Version]$OSImageVersion).Build) {
										$MatchFound = $true
									}
								}
								"Microsoft" {
									if ($Package.PackageName -match $OSImageVersion) {
										$MatchFound = $true
									}
								}
								Default {
									if ($Package.PackageName -match $OSName) {
										$MatchFound = $true
									}
								}
							}
						}
						else {
							if ($Package.PackageName -match $OSName) {
								$MatchFound = $true
							}
						}
						# Match Microsoft Surface Models
						if (($ComputerManufacturer -eq "Microsoft") -and ($ComputerManufacturer -match $Package.PackageManufacturer) -and (($Package.PackageDescription.Split(":")[1]) -ne $null) -and ($Package.PackageName -match $OSName)) {
							if (($Package.PackageDescription.Split(":")[1].TrimEnd(")")) -match $ComputerModel) {
								Write-CMLogEntry -Value "Match found for computer model and manufacturer: $($Package.PackageName) ($($Package.PackageID))" -Severity 1
								$PackageList.Add($Package) | Out-Null
								$MatchFound = $true
							}
						}
					}
					else {
						$MatchFound = $false
					}
					
					# Add package to list if match is found
					if ($MatchFound -eq $true) {
						Write-CMLogEntry -Value "Match found for computer model, manufacturer and operating system: $($Package.PackageName) ($($Package.PackageID))" -Severity 1
						$PackageList.Add($Package) | Out-Null
					}
					else {
						Write-CMLogEntry -Value "Package does not meet computer model, manufacturer and operating system criteria: $($Package.PackageName) ($($Package.PackageID))" -Severity 2
					}
				}
				# Process matching items in package list and set task sequence variable
				if ($PackageList -ne $null) {
					# Determine the most current package from list
					if ($PackageList.Count -eq 1) {
						Write-CMLogEntry -Value "Driver package list contains a single match, attempting to set task sequence variable" -Severity 1
						# Attempt to set task sequence variable
						try {
							$TSEnvironment.Value("OSDDownloadDownloadPackages") = $($PackageList[0].PackageID)
							Write-CMLogEntry -Value "Successfully set OSDDownloadDownloadPackages variable with PackageID: $($PackageList[0].PackageID)" -Severity 1
						}
						catch [System.Exception] {
							Write-CMLogEntry -Value "An error occured while setting OSDDownloadDownloadPackages variable. Error message: $($_.Exception.Message)" -Severity 3; exit 1
						}
					}
					elseif ($PackageList.Count -ge 2) {
						Write-CMLogEntry -Value "Driver package list contains multiple matches, attempting to set task sequence variable" -Severity 1
						
						# Attempt to set task sequence variable
						try {
							if ($ComputerManufacturer -eq "Hewlett-Packard") {
								Write-CMLogEntry -Value "Attempting to match $ComputerManufacturer driver package based on OS build number $OSImageVersion" -Severity 1
								$Package = ($PackageList | Where-Object { $_.PackageName -match $OSImageVersion }) | Sort-Object -Property PackageCreated -Descending | Select-Object -First 1
							}
							else {
								$Package = $PackageList | Sort-Object -Property PackageCreated -Descending | Select-Object -First 1
							}
							$TSEnvironment.Value("OSDDownloadDownloadPackages") = $($Package[0].PackageID)
							Write-CMLogEntry -Value "Successfully set OSDDownloadDownloadPackages variable with PackageID: $($Package[0].PackageID)" -Severity 1
						}
						catch [System.Exception] {
							Write-CMLogEntry -Value "An error occured while setting OSDDownloadDownloadPackages variable. Error message: $($_.Exception.Message)" -Severity 3; exit 1
						}
					}
					else {
						Write-CMLogEntry -Value "Unable to determine a matching driver package from list since an unsupported count was returned from package list, bailing out" -Severity 2; exit 1
					}
				}
				else {
					Write-CMLogEntry -Value "Empty driver package list detected, bailing out" -Severity 2; exit 1
				}
			}
			else {
				Write-CMLogEntry -Value "Driver package list returned from web service did not contain any objects matching the computer model and manufacturer, bailing out" -Severity 2; exit 1
			}
		}
		else {
			Write-CMLogEntry -Value "Unsupported computer platform detected, bailing out" -Severity 2; exit 1
		}
	}
	else {
		Write-CMLogEntry -Value "Unable to detect current operating system name from task sequence reference, bailing out" -Severity 2; exit 1
	}
}
