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

.PARAMETER DeploymentType
	Define a different deployment scenario other than the default behavior. Choose between BareMetal (default), OSUpgrade or DriverUpdate.	
	
.PARAMETER Filter
	Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.

.PARAMETER UseDriverFallback
	Specify if the script is to be used with a driver fallback package.

.EXAMPLE
	# Detect, download and apply drivers during OS deployment with ConfigMgr:
	.\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers"

	# Detect, download and apply drivers during OS deployment with ConfigMgr and use a driver fallback package:
	.\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers" -UseDriverFallback	

	# Detect and download drivers during OS upgrade with ConfigMgr:
    .\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers" -DeploymentType OSUpgrade
    
	# Detect, download and update with latest drivers for an existing operating system using ConfigMgr:
	.\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers" -DeploymentType DriverUpdate
	
.NOTES
    FileName:    Invoke-CMApplyDriverPackage.ps1
    Author:      Nickolaj Andersen / Maurice Daly
    Contact:     @NickolajA / @MoDaly_IT
    Created:     2017-03-27
    Updated:     2018-01-29
	
    Minimum required version of ConfigMgr WebService: 1.5.0
    
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
    1.1.0 - (2017-08-29) Updated script to only check for the OS build version instead of major, minor, build and revision for HP systems. $OSImageVersion will now only contain the most recent version if multiple OS images is referenced in the Task Sequence
    1.1.1 - (2017-09-12) Updated script to match the system SKU for Dell, Lenovo and HP models. Added architecture check for matching packages
    1.1.2 - (2017-09-15) Replaced computer model matching with SystemSKU. Added script with support for different exit codes
    1.1.3 - (2017-09-18) Added support for downloading package content instead of setting OSDDownloadDownloadPackages variable
    1.1.4 - (2017-09-19) Added support for installing driver package directly from this script instead of running a seperate DISM command line step
    1.1.5 - (2017-10-12) Added support for in full OS driver maintenance updates
    1.1.6 - (2017-10-29) Fixed an issue when detecting Microsoft manufacturer information
    1.1.7 - (2017-10-29) Changed the OSMaintenance parameter from a string to a switch object, make sure that your implementation of this is amended in any task sequence steps
    1.1.8 - (2017-11-07) Added support for driver fallback packages when the UseDriverFallback param is used
	1.1.9 - (2017-12-12) Added additional output for failure to detect system SKU value from WMI
    1.2.0 - (2017-12-14) Fixed an issue where the HP packages would not properly be matched against the OS image version returned by the web service
    1.2.1 - (2018-01-03) IMPORTANT - OSMaintenance switch has been replaced by the DeploymentType parameter. In order to support the default behavior (BareMetal), OSUpgrade and DriverUpdate operational
                         modes for the script, this change was required. Update your task sequence configuration before you use this update.
	2.0.0 - (2018-01-10) Updates include support for machines with blank system SKU values and the ability to run BIOS & driver updates in the FULL OS
	2.0.1 - (2018-01-18) Fixed a regex issue when attempting to fallback to computer model instead of SystemSKU
	2.0.2 - (2018-01-24) Re-constructed the logic for matching driver package to begin with computer model or SystemSKU (SystemSKU takes precedence before computer model) and improved the logging when matching for driver packages
	2.0.3 - (2018-01-25) Added a fix for multiple manufacturer package matches not working for Windows 7. Fixed an issue where SystemSKU was used and multiple driver packages matched. Added script line logging when the script cought an exception.
	2.0.4 - (2018-01-26) Changed from using a foreach loop to a for loop in reverse to remove driver packages that was matched by SystemSKU but does not match the computer model
	2.0.5 - (2018-01-29) Replaced Add-Content with Out-File for issue with file lock causing not all log entries to be written to the ApplyDriverPackage.log file
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[parameter(Mandatory = $true, HelpMessage = "Set the URI for the ConfigMgr WebService.")]
	[ValidateNotNullOrEmpty()]
	[string]$URI,

	[parameter(Mandatory = $true, HelpMessage = "Specify the known secret key for the ConfigMgr WebService.")]
	[ValidateNotNullOrEmpty()]
	[string]$SecretKey,

	[parameter(Mandatory = $false, HelpMessage = "Define a different deployment scenario other than the default behavior. Choose between BareMetal (default), OSUpgrade or DriverUpdate.")]
	[ValidateSet("BareMetal", "OSUpgrade", "DriverUpdate")]
	[string]$DeploymentType = "BareMetal",

	[parameter(Mandatory = $false, HelpMessage = "Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.")]
	[ValidateNotNullOrEmpty()]
	[string]$Filter = ([System.String]::Empty),

	[parameter(Mandatory = $false, HelpMessage = "Specify if the script is to be used with a driver fallback package")]
	[switch]$UseDriverFallback
)
Begin {
	# Load Microsoft.SMS.TSEnvironment COM object
	try {
		$TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Continue
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object"; break
	}
}
Process {
	# Set Log Path
	switch ($DeploymentType) {
		"OSUpgrade" {
			$LogsDirectory = Join-Path $env:SystemRoot "Temp"
		}
		"DriverUpdate" {
			$LogsDirectory = Join-Path $env:SystemRoot "Temp"
		}
		default {
			$LogsDirectory = $Script:TSEnvironment.Value("_SMSTSLogPath")
		}
	}
	
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
			[string]$FileName = "ApplyDriverPackage.log"
		)
		# Determine log file location
		$LogFilePath = Join-Path -Path $LogsDirectory -ChildPath $FileName
		
		# Construct time stamp for log entry
		$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
		
		# Construct date for log entry
		$Date = (Get-Date -Format "MM-dd-yyyy")
		
		# Construct context for log entry
		$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		
		# Construct final log entry
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""ApplyDriverPackage"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file
		try {
			Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to ApplyDriverPackage.log file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
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
	
	function Invoke-CMDownloadContent {
		param (
			[parameter(Mandatory = $true, ParameterSetName = "NoPath", HelpMessage = "Specify a PackageID that will be downloaded.")]
			[Parameter(ParameterSetName = "CustomPath")]
			[ValidateNotNullOrEmpty()]
			[ValidatePattern("^[A-Z0-9]{3}[A-F0-9]{5}$")]
			[string]$PackageID,
			[parameter(Mandatory = $true, ParameterSetName = "NoPath", HelpMessage = "Specify the download location type.")]
			[Parameter(ParameterSetName = "CustomPath")]
			[ValidateNotNullOrEmpty()]
			[ValidateSet("Custom", "TSCache", "CCMCache")]
			[string]$DestinationLocationType,
			[parameter(Mandatory = $true, ParameterSetName = "NoPath", HelpMessage = "Save the download location to the specified variable name.")]
			[Parameter(ParameterSetName = "CustomPath")]
			[ValidateNotNullOrEmpty()]
			[string]$DestinationVariableName,
			[parameter(Mandatory = $true, ParameterSetName = "CustomPath", HelpMessage = "When location type is specified as Custom, specify the custom path.")]
			[ValidateNotNullOrEmpty()]
			[string]$CustomLocationPath
		)
		# Set OSDDownloadDownloadPackages
		Write-CMLogEntry -Value "Setting task sequence variable OSDDownloadDownloadPackages to: $($PackageID)" -Severity 1
		$TSEnvironment.Value("OSDDownloadDownloadPackages") = "$($PackageID)"
		
		# Set OSDDownloadDestinationLocationType
		Write-CMLogEntry -Value "Setting task sequence variable OSDDownloadDestinationLocationType to: $($DestinationLocationType)" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationLocationType") = "$($DestinationLocationType)"
		
		# Set OSDDownloadDestinationVariable
		Write-CMLogEntry -Value "Setting task sequence variable OSDDownloadDestinationVariable to: $($DestinationVariableName)" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationVariable") = "$($DestinationVariableName)"
		
		# Set OSDDownloadDestinationPath
		if ($DestinationLocationType -like "Custom") {
			Write-CMLogEntry -Value "Setting task sequence variable OSDDownloadDestinationPath to: $($CustomLocationPath)" -Severity 1
			$TSEnvironment.Value("OSDDownloadDestinationPath") = "$($CustomLocationPath)"
		}
		
		# Invoke download of package content
		try {
			Write-CMLogEntry -Value "Starting package content download process, this might take some time" -Severity 1
			
			if (Test-Path -Path "C:\Windows\CCM\OSDDownloadContent.exe") {
				Write-CMLogEntry -Value "Starting package content download process (FullOS), this might take some time" -Severity 1
				$ReturnCode = Invoke-Executable -FilePath "C:\Windows\CCM\OSDDownloadContent.exe"
			}
			else {
				Write-CMLogEntry -Value "Starting package content download process (WinPE), this might take some time" -Severity 1
				$ReturnCode = Invoke-Executable -FilePath "OSDDownloadContent.exe"
			}
			
			# Match on return code
			if ($ReturnCode -eq 0) {
				Write-CMLogEntry -Value "Successfully downloaded package content with PackageID: $($PackageID)" -Severity 1
			}
			else {
				Write-CMLogEntry -Value "Package content download process failed with return code $($ReturnCode)" -Severity 2
			}
		}
		catch [System.Exception] {
			Write-CMLogEntry -Value "An error occurred while attempting to download package content. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 12
		}
		
		return $ReturnCode
	}
	
	function Invoke-CMResetDownloadContentVariables {
		# Set OSDDownloadDownloadPackages
		Write-CMLogEntry -Value "Setting task sequence variable OSDDownloadDownloadPackages to a blank value" -Severity 1
		$TSEnvironment.Value("OSDDownloadDownloadPackages") = [System.String]::Empty
		
		# Set OSDDownloadDestinationLocationType
		Write-CMLogEntry -Value "Setting task sequence variable OSDDownloadDestinationLocationType to a blank value" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationLocationType") = [System.String]::Empty
		
		# Set OSDDownloadDestinationVariable
		Write-CMLogEntry -Value "Setting task sequence variable OSDDownloadDestinationVariable to a blank value" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationVariable") = [System.String]::Empty
		
		# Set OSDDownloadDestinationPath
		Write-CMLogEntry -Value "Setting task sequence variable OSDDownloadDestinationPath to a blank value" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationPath") = [System.String]::Empty
	}
	
	function Get-OSDataFromWebService {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Specify the OS data to retrieve.")]
			[ValidateNotNullOrEmpty()]
			[ValidateSet("OSImageVersion", "OSImageArchitecture")]
			[string]$OSData
		)
		$TSPackageID = $TSEnvironment.Value("_SMSTSPackageID")
		switch ($OSData) {
			"OSImageVersion" {
				# Determine OS Image version for running task sequence from web service
				Write-CMLogEntry -Value "Attempting to detect OSImageVersion property from task sequence, running in DeploymentType: $($DeploymentType)" -Severity 1
				try {
					$OSImageVersion = $WebService.GetCMOSImageVersionForTaskSequence($SecretKey, $TSPackageID) | Sort-Object -Descending | Select-Object -First 1
					Write-CMLogEntry -Value "Retrieved OSImageVersion from web service: $($OSImageVersion)" -Severity 1
					
					# Handle return value from function
					return $OSImageVersion
				}
				catch [System.Exception] {
					Write-CMLogEntry -Value "An error occured while calling ConfigMgr WebService to determine OSImageVersion. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 3
				}
			}
			"OSImageArchitecture" {
				# Determine OS Image architecture for running task sequence from web service
				Write-CMLogEntry -Value "Attempting to detect OSImageArchitecture property from task sequence, running in DeploymentType: $($DeploymentType)" -Severity 1
				try {
					$OSImageArchitecture = $WebService.GetCMOSImageArchitectureForTaskSequence($SecretKey, $TSPackageID) | Sort-Object -Descending | Select-Object -First 1
					Write-CMLogEntry -Value "Retrieved OSImageArchitecture from web service: $($OSImageArchitecture)" -Severity 1
					
					# Handle return value from function
					return $OSImageArchitecture
				}
				catch [System.Exception] {
					Write-CMLogEntry -Value "An error occured while calling ConfigMgr WebService to determine OSImageArchitecture. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 4
				}
			}
		}
	}
	
	function Get-OSArchitecture {
		param (
			[parameter(Mandatory = $true, HelpMessage = "OS architecture data to be translated.")]
			[ValidateNotNullOrEmpty()]
			[string]$InputObject
		)
		switch ($InputObject) {
			"9" {
				$OSImageArchitecture = "x64"
			}
			"0" {
				$OSImageArchitecture = "x86"
			}
			"64-bit" {
				$OSImageArchitecture = "x64"
			}
			"32-bit" {
				$OSImageArchitecture = "x86"
			}
		}
		Write-CMLogEntry -Value "Translated OSImageArchitecture: $($OSImageArchitecture)" -Severity 1
		
		# Handle return value from function
		return $OSImageArchitecture
	}
	
	function Get-OSName {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Windows build version must be provided")]
			[ValidateNotNullOrEmpty()]
			[string]$InputObject
		)
		
		# Get operating system name from version
		switch -Wildcard ($InputObject) {
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
		Write-CMLogEntry -Value "Translated OSName from OSImageVersion: $($OSName)" -Severity 1
		
		# Handle return value from function
		return $OSName
	}
	
	# Write log file for script execution
	Write-CMLogEntry -Value "Driver download package process initiated" -Severity 1
	
	# Determine manufacturer
	$ComputerManufacturer = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer).Trim()
	
	# Determine manufacturer name and hardware information
	switch -Wildcard ($ComputerManufacturer) {
		"*Microsoft*" {
			$ComputerManufacturer = "Microsoft"
			$ComputerModel = Get-WmiObject -Namespace root\wmi -Class MS_SystemInformation | Select-Object -ExpandProperty SystemSKU
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
	}
	Write-CMLogEntry -Value "Manufacturer determined as: $($ComputerManufacturer)" -Severity 1
	Write-CMLogEntry -Value "Computer model determined as: $($ComputerModel)" -Severity 1
	if (-not ([string]::IsNullOrEmpty($SystemSKU))) {
		Write-CMLogEntry -Value "Computer SKU determined as: $($SystemSKU)" -Severity 1
	}
	else {
		Write-CMLogEntry -Value "Unable to determine system SKU value" -Severity 2
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
		Write-CMLogEntry -Value "Unable to establish a connection to ConfigMgr WebService. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 1
	}
	
	# Call web service for a list of packages
	try {
		$Packages = $WebService.GetCMPackage($SecretKey, $Filter)
		Write-CMLogEntry -Value "Retrieved a total of $(($Packages | Measure-Object).Count) driver packages from web service" -Severity 1
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "An error occured while calling ConfigMgr WebService for a list of available packages. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 2
	}
	
	# Based upon deployment type, determine how to detect the OS image version property, either from the OS defined in the running task sequence or from the running operating system
	switch ($DeploymentType) {
		"BareMetal" {
			# Get OS data
			$OSImageVersion = Get-OSDataFromWebService -OSData OSImageVersion
			$OSArchitecture = Get-OSDataFromWebService -OSData OSImageArchitecture
			
			# Translate operating system name from version
			$OSName = Get-OSName -InputObject $OSImageVersion
			
			# Translate operating system architecture from web service response
			$OSImageArchitecture = Get-OSArchitecture -InputObject $OSArchitecture
		}
		"OSUpgrade" {
			# Get OS data
			$OSImageVersion = Get-OSDataFromWebService -OSData OSImageVersion
			$OSArchitecture = Get-OSDataFromWebService -OSData OSImageArchitecture
			
			# Translate operating system name from version
			$OSName = Get-OSName -InputObject $OSImageVersion
			
			# Translate operating system architecture from web service response
			$OSImageArchitecture = Get-OSArchitecture -InputObject $OSArchitecture
		}
		"DriverUpdate" {
			# Get OS data
			$OSImageVersion = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty Version
			$OSArchitecture = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty OSArchitecture
			
			# Translate operating system name from version
			$OSName = Get-OSName -InputObject $OSImageVersion
			
			# Translate operating system architecture from running operating system
			$OSImageArchitecture = Get-OSArchitecture -InputObject $OSArchitecture
		}
	}
	
	# Validate operating system name was detected
	if ($OSName -ne $null) {
		# Validate not virtual machine
		$ComputerSystemType = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty "Model"
		if ($ComputerSystemType -notin @("Virtual Machine", "VMware Virtual Platform", "VirtualBox", "HVM domU", "KVM")) {
			# Process packages returned from web service
			if ($Packages -ne $null) {
				if ([System.String]::IsNullOrEmpty($SystemSKU)) {
					$ComputerDetectionMethod = "ComputerModel"
				}
				else {
					$ComputerDetectionMethod = "SystemSKU"
				}
				foreach ($Package in $Packages) {
					Write-CMLogEntry -Value "Attempting to find a match for driver package: $($Package.PackageName) ($($Package.PackageID))" -Severity 1

					# Computer detection method matching
					$ComputerDetectionResult = $false
					switch ($ComputerDetectionMethod) {
						"ComputerModel" {
							if ($Package.PackageName.Split("-").Replace($ComputerManufacturer, "").Trim()[1] -match $ComputerModel) {
								Write-CMLogEntry -Value "Match found for computer model using detection method: $($ComputerDetectionMethod) ($($ComputerModel))" -Severity 1
								$ComputerDetectionResult = $true
							}
						}
						"SystemSKU" {
							if ($Package.PackageDescription -match $SystemSKU) {
								Write-CMLogEntry -Value "Match found for computer model using detection method: $($ComputerDetectionMethod) ($($SystemSKU))" -Severity 1
								$ComputerDetectionResult = $true
							}
						}
					}

					# Match manufacturer, operating system name and architecture criteria
					if ($ComputerDetectionResult -eq $true) {
						if (($ComputerManufacturer -match $Package.PackageManufacturer) -and ($Package.PackageName -match $OSName) -and ($Package.PackageName -match $OSImageArchitecture)) {
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
								$MatchFound = $true
							}
							
							# Add package to list if match is found
							if ($MatchFound -eq $true) {
								Write-CMLogEntry -Value "Match found for manufacturer, operating system and architecture: $($Package.PackageName) ($($Package.PackageID))" -Severity 1
								$PackageList.Add($Package) | Out-Null
							}
						}
						else {
							Write-CMLogEntry -Value "Driver package does not meet computer model, manufacturer and operating system and architecture criteria: $($Package.PackageName) ($($Package.PackageID))" -Severity 2
						}
					}
					else {
						Write-CMLogEntry -Value "Driver package does not meet computer model criteria: $($Package.PackageName) ($($Package.PackageID))" -Severity 2
					}
				}
				# Process matching items in package list
				if ($PackageList -ne $null) {
					# Handle multiple matches when the computer detection method SystemSKU is used
					if (($ComputerDetectionMethod -like "SystemSKU") -and ($PackageList.Count -ge 2)) {
						Write-CMLogEntry -Value "Driver package list contains $($PackageList.Count) matches. Atempting to remove driver packages that do not match the computer model." -Severity 1

						# Process driver package list in reverse
						for ($i = ($PackageList.Count-1); $i -ge 0; $i--) {
							if ($PackageList[$i].PackageName.Split("-").Replace($ComputerManufacturer, "").Trim()[1] -notmatch $ComputerModel) {
								Write-CMLogEntry -Value "Removing driver package matching SystemSKU but not computer model: $($PackageList[$i].PackageName)" -Severity 1
								$PackageList.RemoveAt($i)
							}
						}
					}

					# Determine the most current package from list
					if ($PackageList.Count -eq 1) {
						try {
							# Attempt to download driver package content
							Write-CMLogEntry -Value "Driver package list contains a single match, attempting to download driver package content" -Severity 1
							$DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageList[0].PackageID -DestinationLocationType Custom -DestinationVariableName "OSDDriverPackage" -CustomLocationPath "%_SMSTSMDataPath%\DriverPackage"
							Write-CMLogEntry -Value "Attempting to download driver package $($Package.PackageID) content from Distribution Point" -Severity 1
							
							try {
								if ($DownloadInvocation -eq 0) {
									if ($DeploymentType -match "BareMetal") {
										# Apply drivers recursively from downloaded driver package location
										Write-CMLogEntry -Value "Driver package content downloaded successfully, attempting to apply drivers using dism.exe located in: $($TSEnvironment.Value('OSDDriverPackage01'))" -Severity 1
										$ApplyDriverInvocation = Invoke-Executable -FilePath "Dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDisk'))\ /Add-Driver /Driver:$($TSEnvironment.Value('OSDDriverPackage01')) /Recurse"
										
										# Validate driver injection
										if ($ApplyDriverInvocation -eq 0) {
											Write-CMLogEntry -Value "Successfully applied drivers using dism.exe" -Severity 1
										}
										else {
											Write-CMLogEntry -Value "An error occurred while applying drivers (single package match). Exit code: $($ApplyDriverInvocation). See DISM.log for more details." -Severity 3; exit 14
										}
									}
									else {
										# Apply drivers recursively from downloaded driver package location
										Write-CMLogEntry -Value "Driver package content downloaded successfully, attempting to apply drivers using pnputil.exe" -Severity 1
										Write-CMLogEntry -Value "Reading drivers from $($TSEnvironment.Value('OSDDriverPackage01')) " -Severity 1
										$ApplyDriverInvocation = Invoke-Executable -FilePath "powershell.exe" -Arguments "pnputil /add-driver $(Join-Path $TSEnvironment.Value('OSDDriverPackage01') '*.inf') /subdirs /install | Out-File -FilePath (Join-Path $LogsDirectory 'Install-Drivers.txt') -Force"
									}
								}
								else {
									Write-CMLogEntry -Value "Driver package content download process returned an unhandled exit code: $($DownloadInvocation)" -Severity 3; exit 13
								}
							}
							catch [System.Exception] {
								Write-CMLogEntry -Value "An error occurred while applying drivers (single package match). Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 14
							}
						}
						catch [System.Exception] {
							Write-CMLogEntry -Value "An error occurred while downloading driver package content (single package match). Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 5
						}
					}
					elseif ($PackageList.Count -ge 2) {
						try {
							Write-CMLogEntry -Value "Driver package list contains multiple matches, attempting to download driver package content based up latest package creation date" -Severity 1
							
							# Determine matching driver package from array list with vendor specific solutions
							if (($ComputerManufacturer -like "Hewlett-Packard") -and ($OSName -like "Windows 10")) {
								Write-CMLogEntry -Value "Vendor specific matching required before downloading content. Attempting to match $($ComputerManufacturer) driver package based on OS build number: $($OSImageVersion)" -Severity 1
								$Package = ($PackageList | Where-Object { $_.PackageName -match ([System.Version]$OSImageVersion).Build }) | Sort-Object -Property PackageCreated -Descending | Select-Object -First 1
							}
							else {
								$Package = $PackageList | Sort-Object -Property PackageCreated -Descending | Select-Object -First 1
							}
							
							# Validate that there's a package available for download
							if ($Package -ne $null) {
								# Attempt to download driver package content
								$DownloadInvocation = Invoke-CMDownloadContent -PackageID $Package.PackageID -DestinationLocationType Custom -DestinationVariableName "OSDDriverPackage" -CustomLocationPath "%_SMSTSMDataPath%\DriverPackage"
								Write-CMLogEntry -Value "Attempting to download driver package $($Package.PackageID) content from Distribution Point" -Severity 1
								
								try {
									if ($DownloadInvocation -eq 0) {
										if ($DeploymentType -match "BareMetal") {
											# Apply drivers recursively from downloaded driver package location
											Write-CMLogEntry -Value "Driver package content downloaded successfully, attempting to apply drivers using dism.exe located in: $($TSEnvironment.Value('OSDDriverPackage01'))" -Severity 1
											$ApplyDriverInvocation = Invoke-Executable -FilePath "Dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDisk'))\ /Add-Driver /Driver:$($TSEnvironment.Value('OSDDriverPackage01')) /Recurse"
											
											# Validate driver injection
											if ($ApplyDriverInvocation -eq 0) {
												Write-CMLogEntry -Value "Successfully applied drivers using dism.exe" -Severity 1
												
											}
											else {
												Write-CMLogEntry -Value "An error occurred while applying drivers (multiple package match). Exit code: $($ApplyDriverInvocation). See DISM.log for more details." -Severity 3; exit 15
											}
										}
										else {
											# Apply drivers recursively from downloaded driver package location
											Write-CMLogEntry -Value "Driver package content downloaded successfully, attempting to apply drivers using pnputil.exe" -Severity 1
											Write-CMLogEntry -Value "Reading drivers from $($TSEnvironment.Value('OSDDriverPackage01')) " -Severity 1
											$ApplyDriverInvocation = Invoke-Executable -FilePath "powershell.exe" -Arguments "pnputil /add-driver $(Join-Path -Path $TSEnvironment.Value('OSDDriverPackage01') -ChildPath '*.inf') /subdirs /install | Out-File -FilePath (Join-Path -Path $LogsDirectory -ChildPath 'Install-Drivers.txt') -Force"
										}
									}
									else {
										Write-CMLogEntry -Value "Driver package content download process returned an unhandled exit code: $($DownloadInvocation)" -Severity 3; exit 13
									}
								}
								catch [System.Exception] {
									Write-CMLogEntry -Value "An error occurred while applying drivers (multiple package match). Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 15
								}
							}
							else {
								Write-CMLogEntry -Value "An error occurred while selecting manufacturer specific driver packages from list, empty list of packages detected" -Severity 3; exit 21
							}
						}
						catch [System.Exception] {
							Write-CMLogEntry -Value "An error occurred while downloading driver package content (multiple package matches). Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 6
						}
					}
					else {
						Write-CMLogEntry -Value "Unable to determine a matching driver package from package list array, unhandled amount of matches" -Severity 2; exit 7
					}
				}
				elseif ($PSBoundParameters.ContainsKey("UseDriverFallback") -eq $true) {
					Write-CMLogEntry -Value "Driver fallback parameter specified and no matching driver packages found" -Severity 1
					
					# Process packages returned from web service
					if ($Packages -ne $null) {
						Write-CMLogEntry -Value "Attempting to match a driver fallback package" -Severity 1
						foreach ($Package in $Packages) {
							Write-CMLogEntry -Value "Processing $($Package.PackageName)" -Severity 1
							if (($Package.PackageName -match "Driver Fallback") -and ($Package.PackageName -match $OSName) -and ($Package.PackageName -match $OSImageArchitecture)) {
								$PackageList.Add($Package) | Out-Null
							}
							
							if ($PackageList.Count -eq 1) {
								try {
									# Attempt to download driver fallback package content
									Write-CMLogEntry -Value "Attempting to download driver fallback package content" -Severity 1
									$DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageList[0].PackageID -DestinationLocationType Custom -DestinationVariableName "OSDDriverPackage" -CustomLocationPath "%_SMSTSMDataPath%\DriverPackage"
									
									try {
										if ($DownloadInvocation -eq 0) {
											if ($PSBoundParameters.ContainsKey("DriverUpdate") -eq $false) {
												# Apply drivers recursively from downloaded driver package location
												Write-CMLogEntry -Value "Driver fallback package content downloaded successfully, attempting to apply drivers using dism.exe located in: $($TSEnvironment.Value('OSDDriverPackage01'))" -Severity 1
												$ApplyDriverInvocation = Invoke-Executable -FilePath "Dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDisk'))\ /Add-Driver /Driver:$($TSEnvironment.Value('OSDDriverPackage01')) /Recurse"
												
												# Validate driver injection
												if ($ApplyDriverInvocation -eq 0) {
													Write-CMLogEntry -Value "Successfully applied drivers using dism.exe" -Severity 1
												}
												else {
													Write-CMLogEntry -Value "An error occurred while applying fallback drivers. Exit code: $($ApplyDriverInvocation)" -Severity 3; exit 19
												}
											}
											elseif ($PSBoundParameters.ContainsKey("DriverUpdate") -eq $true) {
												# Apply drivers recursively from downloaded driver package location
												Start-Process "$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -WorkingDirectory $OSDriverPackage01 -ArgumentList "pnputil /add-driver *.inf /subdirs /install | Out-File -FilePath (Join-Path C: 'Install-Drivers.txt') -Append" -NoNewWindow -Wait
											}
										}
										else {
											Write-CMLogEntry -Value "Fallback driver package content download process returned an unhandled exit code: $($DownloadInvocation)" -Severity 3; exit 20
										}
									}
									catch [System.Exception] {
										Write-CMLogEntry -Value "An error occurred while applying fallback drivers. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 18
									}
								}
								catch [System.Exception] {
									Write-CMLogEntry -Value "An error occurred while downloading fallback driver package content. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 17
								}
							}
							else {
								Write-CMLogEntry -Value "Either empty or an unsupported count of fallback package content detected" -Severity 3; exit 16
							}
						}
					}
					else {
						Write-CMLogEntry -Value "Empty driver package list detected, unable to determine matching driver fallback package" -Severity 2; exit 8
					}
				}
				else {
					Write-CMLogEntry -Value "Call to web service for package objects returned empty" -Severity 2; exit 9
				}
			}
			else {
				Write-CMLogEntry -Value "Unsupported computer platform detected, virtual machines are not supported" -Severity 2; exit 10
			}
		}
	}
	else {
		Write-CMLogEntry -Value "Unable to detect current operating system name from task sequence reference objects" -Severity 2; exit 11
	}
}
End {
	# Reset OSDDownloadContent.exe dependant variables for further use of the task sequence step
	Invoke-CMResetDownloadContentVariables
}