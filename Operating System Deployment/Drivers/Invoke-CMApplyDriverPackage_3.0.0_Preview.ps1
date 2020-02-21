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
	Define a different deployment scenario other than the default behavior. Choose between BareMetal (default), OSUpgrade, DriverUpdate or PreCache (Same as OSUpgrade but only downloads the package content).
	
.PARAMETER Filter
	Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.

.PARAMETER OperationalMode
	Define the operational mode, either Production or Pilot, for when calling ConfigMgr WebService to only return objects matching the selected operational mode.

.PARAMETER UseDriverFallback
	Specify if the script is to be used with a driver fallback package.

.PARAMETER DriverInstallMode
	Specify whether to install drivers using DISM.exe with recurse option or spawn a new process for each driver.

.PARAMETER DebugMode
	Use this switch when running script outside of a Task Sequence.

.PARAMETER TSPackageID
	Specify the Task Sequence PackageID when running in debug mode.

.PARAMETER OSImageTSVariableName
	Specify a Task Sequence variable name that should contain a value for an OS Image package ID that will be used to override automatic detection.

.PARAMETER TargetOSVersion
	Define the value that will be used as the target operating system version e.g. 18363.

.EXAMPLE
	# Detect, download and apply drivers during OS deployment with ConfigMgr:
	.\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers"

	# Detect, download and apply drivers during OS deployment with ConfigMgr and use a driver fallback package:
	.\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers" -UseDriverFallback	

	# Detect and download drivers during OS upgrade with ConfigMgr:
    .\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers" -DeploymentType OSUpgrade
    
	# Detect, download and update with latest drivers for an existing operating system using ConfigMgr:
	.\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers" -DeploymentType DriverUpdate

	# Detect, download and apply drivers during OS deployment with ConfigMgr when using multiple Apply Operating System steps in the task sequence:
	.\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers" -OSImageTSVariableName "OSImageVariable"

	# Detect and download (pre-caching content) during OS upgrade with ConfigMgr:
	.\Invoke-CMApplyDriverPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "Drivers" -DeploymentType "PreCache"

.NOTES
    FileName:    Invoke-CMApplyDriverPackage.ps1
	Author:      Nickolaj Andersen / Maurice Daly
    Contact:     @NickolajA / @MoDaly_IT
    Created:     2017-03-27
    Updated:     2020-02-11
	
	Minimum required version of ConfigMgr WebService: 1.6.0
	Contributors: @CodyMathis123, @JamesMcwatty
    
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
	2.0.6 - (2018-02-21) Updated to cater for the presence of underscores in Microsoft Surface models
	2.0.7 - (2018-02-25) Added support for a DebugMode switch for running script outside of a task sequence for driver package detection
	2.0.8 - (2018-02-25) Added a check to bail out the script if computer model and SystemSKU are null or an empty string
	2.0.9 - (2018-05-07) Removed exit code 34 event. DISM will now continue to process drivers if a single or multiple failures occur in order to proceed with the task sequence
	2.1.0 - (2018-06-01) IMPORTANT: From this version, ConfigMgr WebService 1.6 is required. Added a new parameter named OSImageTSVariableName that accepts input of a task sequence variable. This task sequence variable should contain the OS Image package ID of 
						 the desired Operating System Image selected in an Apply Operating System step. This new functionality allows for using multiple Apply Operating System steps in a single task sequence. Added Panasonic for manufacturer detection.
						 Improved logic with fallback from SystemSKU to computer model. Script will now fall back to computer model if there was no match to the SystemSKU. This still requires that the SystemSKU contains a value and is not null or empty, otherwise 
						 the logic will directly fall back to computer model. A new parameter named DriverInstallMode has been added to control how drivers are installed for BareMetal deployment. Valid inputs are Single or Recurse.
	2.1.1 - (2018-08-28) Code tweaks and changes for Windows build to version switch in the Driver Automation Tool. Improvements to the SystemSKU reverse section for HP models and multiple SystemSKU values from WMI
	2.1.2 - (2018-08-29) Added code to handle Windows 10 version specific matching and also support matching for the name only
	2.1.3 - (2018-09-03) Code tweak to Windows 10 version matching process
	2.1.4 - (2018-09-18) Added support to override the task sequence package ID retrieved from _SMSTSPackageID when the Apply Operating System step is in a child task sequence
	2.1.5 - (2018-09-18) Updated the computer model detection logic that replaces parts of the string from the PackageName property to retrieve the computer model only
	2.1.6 - (2019-01-28) Fixed an issue with the recurse injection of drivers for a single detected driver package that was using an unassigned variable
	2.1.7 - (2019-02-13) Added support for Windows 10 version 1809 in the Get-OSDetails function
	2.1.8 - (2019-02-13) Added trimming of manufacturer and models data gathering from WMI
	2.1.9 - (2019-03-06) Added support for non-terminating error when no matching driver packages where detected for OSUpgrade and DriverUpdate deployment types
	2.2.0 - (2019-03-08) Fixed an issue when attempting to run the script with -DebugMode switch that would cause it to break when it couldn't load the TS environment
	2.2.1 - (2019-03-29) New deployment type named 'PreCache' that allows the script to run in a pre-caching mode in a content pre-cache task sequence. When this deployment type is used, content will only be downloaded if it doesn't already
						 exist in the CCMCache. New parameter OperationalMode (defaults to Production) for better handling driver packages set for Pilot or Production deployment.
	2.2.2 - (2019-05-14) Improved the Surface model detection from WMI
	2.2.3 - (2019-05-14) Fixed an issue when multiple matching driver packages for a given model would only attempt to format the computer model name correctly for HP computers
	2.2.4 - (2019-08-09) Fixed an issue on OperationalMode Production to filter out pilot and retired packages
	2.2.5 - (2019-12-02) Added support for Windows 10 1903, 1909 and additional matching for Microsoft Surface devices (DAT 6.4.0 or neweer)
	2.2.6 - (2020-02-06) Fixed an issue where the single driver injection mode for BareMetal deployments would fail if there was a space in the driver inf name
	2.2.7 - (2020-02-10) Added a new parameter named TargetOSVersion. Use this parameter when DeploymentType is OSUpgrade and you don't want to rely on the OS version detected from the imported Operating System Upgrade Package or Operating System Image objects.
						 This parameter should mainly be used as an override and was implemented due to drivers for Windows 10 1903 were incorrectly detected when deploying or upgrading to Windows 10 1909 using imported source files, not for a 
                         reference image for Windows 10 1909 as the Enablement Package would have flipped the build change to 18363 in such an image.
    3.0.0 - (2020-02-11) ..........
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Execute")]
param (
	[parameter(Mandatory = $true, ParameterSetName = "Execute", HelpMessage = "Set the URI for the ConfigMgr WebService.")]
	[parameter(Mandatory = $true, ParameterSetName = "Debug")]
	[ValidateNotNullOrEmpty()]
	[string]$URI,
	
	[parameter(Mandatory = $true, ParameterSetName = "Execute", HelpMessage = "Specify the known secret key for the ConfigMgr WebService.")]
	[parameter(Mandatory = $true, ParameterSetName = "Debug")]
	[ValidateNotNullOrEmpty()]
	[string]$SecretKey,
	
	[parameter(Mandatory = $false, ParameterSetName = "Execute", HelpMessage = "Define a different deployment scenario other than the default behavior. Choose between BareMetal (default), OSUpgrade, DriverUpdate or PreCache (Same as OSUpgrade but only downloads the package content).")]
	[parameter(Mandatory = $false, ParameterSetName = "Debug")]
	[ValidateSet("BareMetal", "OSUpgrade", "DriverUpdate", "PreCache")]
	[string]$DeploymentType = "BareMetal",
	
	[parameter(Mandatory = $false, ParameterSetName = "Execute", HelpMessage = "Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.")]
	[parameter(Mandatory = $false, ParameterSetName = "Debug")]
	[ValidateNotNullOrEmpty()]
	[string]$Filter = "Driver",

	[parameter(Mandatory = $false, ParameterSetName = "Execute", HelpMessage = "Define the operational mode, either Production or Pilot, for when calling ConfigMgr WebService to only return objects matching the selected operational mode.")]
	[parameter(Mandatory = $false, ParameterSetName = "Debug")]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("Production", "Pilot")]
	[string]$OperationalMode = "Production",
	
	[parameter(Mandatory = $false, ParameterSetName = "Execute", HelpMessage = "Specify if the script is to be used with a driver fallback package.")]
	[parameter(Mandatory = $false, ParameterSetName = "Debug")]
	[switch]$UseDriverFallback,
	
	[parameter(Mandatory = $false, ParameterSetName = "Execute", HelpMessage = "Specify whether to install drivers using DISM.exe with recurse option or spawn a new process for each driver.")]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("Single", "Recurse")]
	[string]$DriverInstallMode = "Recurse",
	
	[parameter(Mandatory = $true, ParameterSetName = "Debug", HelpMessage = "Use this switch when running script outside of a Task Sequence.")]
	[switch]$DebugMode,
	
	[parameter(Mandatory = $true, ParameterSetName = "Debug", HelpMessage = "Specify the Task Sequence PackageID when running in debug mode.")]
	[ValidateNotNullOrEmpty()]
	[string]$TSPackageID,
	
	[parameter(Mandatory = $false, ParameterSetName = "Execute", HelpMessage = "Specify a Task Sequence variable name that should contain a value for an OS Image package ID that will be used to override automatic detection.")]
	[ValidateNotNullOrEmpty()]
	[string]$OSImageTSVariableName,

	[parameter(Mandatory = $false, ParameterSetName = "Execute", HelpMessage = "Specify a task sequence package ID for a child task sequence. Should only be used when the Apply Operating System step is in a child task sequence.")]
	[ValidateNotNullOrEmpty()]
	[string]$OverrideTSPackageID,

	[parameter(Mandatory = $false, ParameterSetName = "Execute", HelpMessage = "Define the value that will be used as the target operating system version e.g. 18363.")]
	[ValidateNotNullOrEmpty()]
	[string]$TargetOSVersion
)
Begin {
	# Load Microsoft.SMS.TSEnvironment COM object
	if ($PSCmdLet.ParameterSetName -like "Execute") {
		try {
			$TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Continue
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object"
		}
	}
}
Process {
	# Set Log Path
	switch ($DeploymentType) {
		"OSUpgrade" {
			$LogsDirectory = Join-Path -Path $env:SystemRoot -ChildPath "Temp"
		}
		"DriverUpdate" {
			$LogsDirectory = Join-Path -Path $env:SystemRoot -ChildPath "Temp"
		}
		Default {
			if (-not($PSCmdLet.ParameterSetName -like "Execute")) {
				$LogsDirectory = Join-Path -Path $env:SystemRoot -ChildPath "Temp"
			}
			else {
				$LogsDirectory = $Script:TSEnvironment.Value("_SMSTSLogPath")
			}
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
		if (-not(Test-Path -Path 'variable:global:TimezoneBias')) {
			[string]$global:TimezoneBias = [System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes
			if ($TimezoneBias -match "^-") {
				$TimezoneBias = $TimezoneBias.Replace('-', '+')
			}
			else {
				$TimezoneBias = '-' + $TimezoneBias
			}
		}
		$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), $TimezoneBias)
		
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
		Write-CMLogEntry -Value " - Setting task sequence variable OSDDownloadDownloadPackages to: $($PackageID)" -Severity 1
		$TSEnvironment.Value("OSDDownloadDownloadPackages") = "$($PackageID)"
		
		# Set OSDDownloadDestinationLocationType
		Write-CMLogEntry -Value " - Setting task sequence variable OSDDownloadDestinationLocationType to: $($DestinationLocationType)" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationLocationType") = "$($DestinationLocationType)"
		
		# Set OSDDownloadDestinationVariable
		Write-CMLogEntry -Value " - Setting task sequence variable OSDDownloadDestinationVariable to: $($DestinationVariableName)" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationVariable") = "$($DestinationVariableName)"
		
		# Set OSDDownloadDestinationPath
		if ($DestinationLocationType -like "Custom") {
			Write-CMLogEntry -Value " - Setting task sequence variable OSDDownloadDestinationPath to: $($CustomLocationPath)" -Severity 1
			$TSEnvironment.Value("OSDDownloadDestinationPath") = "$($CustomLocationPath)"
		}
		
		# Invoke download of package content
		try {
			Write-CMLogEntry -Value " - Starting package content download process, this might take some time" -Severity 1
			
			if ($TSEnvironment.Value("_SMSTSInWinPE") -eq $false) {
				Write-CMLogEntry -Value " - Starting package content download process (FullOS), this might take some time" -Severity 1
				$ReturnCode = Invoke-Executable -FilePath (Join-Path -Path $env:windir -ChildPath "CCM\OSDDownloadContent.exe")
			}
			else {
				Write-CMLogEntry -Value " - Starting package content download process (WinPE), this might take some time" -Severity 1
				$ReturnCode = Invoke-Executable -FilePath "OSDDownloadContent.exe"
			}
			
			# Match on return code
			if ($ReturnCode -eq 0) {
				Write-CMLogEntry -Value " - Successfully downloaded package content with PackageID: $($PackageID)" -Severity 1
			}
			else {
				Write-CMLogEntry -Value " - Package content download process failed with return code $($ReturnCode)" -Severity 2
			}
		}
		catch [System.Exception] {
            Write-CMLogEntry -Value " - An error occurred while attempting to download package content. Error message: $($_.Exception.Message)" -Severity 3
            
            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
		}
		
		return $ReturnCode
	}
	
	function Invoke-CMResetDownloadContentVariables {
		# Set OSDDownloadDownloadPackages
		Write-CMLogEntry -Value " - Setting task sequence variable OSDDownloadDownloadPackages to a blank value" -Severity 1
		$TSEnvironment.Value("OSDDownloadDownloadPackages") = [System.String]::Empty
		
		# Set OSDDownloadDestinationLocationType
		Write-CMLogEntry -Value " - Setting task sequence variable OSDDownloadDestinationLocationType to a blank value" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationLocationType") = [System.String]::Empty
		
		# Set OSDDownloadDestinationVariable
		Write-CMLogEntry -Value " - Setting task sequence variable OSDDownloadDestinationVariable to a blank value" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationVariable") = [System.String]::Empty
		
		# Set OSDDownloadDestinationPath
		Write-CMLogEntry -Value " - Setting task sequence variable OSDDownloadDestinationPath to a blank value" -Severity 1
		$TSEnvironment.Value("OSDDownloadDestinationPath") = [System.String]::Empty
	}
	
	function Get-OSImageData {
		# Determine how to get the SMSTSPackageID value
		if ($PSCmdLet.ParameterSetName -eq "Execute") {
			if ($Script:PSBoundParameters["OverrideTSPackageID"]) {
				$SMSTSPackageID = $OverrideTSPackageID
			}
			else {
				$SMSTSPackageID = $TSEnvironment.Value("_SMSTSPackageID")
			}
		}
		else {
			$SMSTSPackageID = $TSPackageID
		}
		
		try {
			# Determine OS Image information for running task sequence from web service
			Write-CMLogEntry -Value " - Attempting to detect OS Image data from task sequence with PackageID: $($SMSTSPackageID)" -Severity 1
			$OSImages = $WebService.GetCMOSImageForTaskSequence($SecretKey, $SMSTSPackageID)
			if ($OSImages -ne $null) {
				if (($OSImages | Measure-Object).Count -ge 2) {
					# Determine behavior when detecting OS Image data
					if ($Script:PSBoundParameters["OSImageTSVariableName"]) {
						# Select OS Image object matching the value from the task sequence variable passed to the OSImageTSVariableName parameter
						Write-CMLogEntry -Value " - Multiple OS Image objects detected. Objects will be matched against provided task sequence variable name '$($OSImageTSVariableName)' to determine the correct object" -Severity 1
						$OSImageTSVariableValue = $TSEnvironment.Value("$($OSImageTSVariableName)")
						foreach ($OSImage in $OSImages) {
							if ($OSImage.PackageID -like $OSImageTSVariableValue) {
								# Handle support for target OS version override from parameter input
								if ($Script:PSBoundParameters["TargetOSVersion"]) {
									$OSBuild = "10.0.$($TargetOSVersion).1"
								}
								else {
									$OSBuild = $OSImage.Version
								}

								# Create custom object for return value
								$PSObject = [PSCustomObject]@{
									OSVersion  = $OSBuild
									OSArchitecture = $OSImage.Architecture
								}

								# Handle return value
								return $PSObject
							}
						}
					}
					else {
						# Select the first object returned from web service call
						Write-CMLogEntry -Value " - Multiple OS Image objects detected and OSImageTSVariableName was not specified. Selecting the first OS Image object from web service call" -Severity 1
						$OSImage = $OSImages | Sort-Object -Descending | Select-Object -First 1
						
						# Handle support for target OS version override from parameter input
						if ($Script:PSBoundParameters["TargetOSVersion"]) {
							$OSBuild = "10.0.$($TargetOSVersion).1"
						}
						else {
							$OSBuild = $OSImage.Version
						}

						# Create custom object for return value
						$PSObject = [PSCustomObject]@{
							OSVersion  = $OSBuild
							OSArchitecture = $OSImage.Architecture
						}

						# Handle return value
						return $PSObject
					}
				}
				else {
					# Handle support for target OS version override from parameter input
					if ($Script:PSBoundParameters["TargetOSVersion"]) {
						$OSBuild = "10.0.$($TargetOSVersion).1"
					}
					else {
						$OSBuild = $OSImages.Version
					}

					# Create custom object for return value
					$PSObject = [PSCustomObject]@{
						OSVersion  = $OSBuild
						OSArchitecture = $OSImages.Architecture
					}

					# Handle return value
					return $PSObject
				}
			}
			else {
                Write-CMLogEntry -Value " - Call to ConfigMgr WebService returned empty OS Image data. Error message: $($_.Exception.Message)" -Severity 3
                
                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
		}
		catch [System.Exception] {
            Write-CMLogEntry -Value " - An error occured while calling ConfigMgr WebService to get OS Image data. Error message: $($_.Exception.Message)" -Severity 3
            
            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
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
			default {
				Write-CMLogEntry -Value " - Unable to translate OS architecture using input object: $($InputObject)" -Severity 3

				# Throw terminating error
				$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
				$PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
		}
		
		# Handle return value from function
		return $OSImageArchitecture
	}
	
	function Get-OSDetails {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Windows build number must be provided")]
			[ValidateNotNullOrEmpty()]
			[string]$InputObject
		)
		
		# Get operating system name and from build number
		switch -Wildcard ($InputObject) {
			"10.0*" {
				$OSName = "Windows 10"
				switch (([System.Version]$InputObject).Build) {
					"18363" {
						$OSVersion = 1909
					}
					"18362" {
						$OSVersion = 1903
					}
					"17763" {
						$OSVersion = 1809
					}
					"17134" {
						$OSVersion = 1803
					}
					"16299" {
						$OSVersion = 1709
					}
					"15063" {
						$OSVersion = 1703
					}
					"14393" {
						$OSVersion = 1607
					}
				}
			}
			default {
				Write-CMLogEntry -Value " - Unable to translate OS name and version using input object: $($InputObject)" -Severity 3

				# Throw terminating error
				$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
				$PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
		}
		
		# Handle return value from function
		if (($OSName -ne $null) -and ($OSVersion -ne $null)) {
			$PSObject = [PSCustomObject]@{
				OSName = $OSName
				OSVersion = $OSVersion
			}
			return $PSObject
		}
		else {
			Write-CMLogEntry -Value " - Unable to translate OS name and version. Both properties did not contain any values" -Severity 3

			# Throw terminating error
			$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
			$PSCmdlet.ThrowTerminatingError($ErrorRecord)
		}
	}

    function New-TerminatingErrorRecord {
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the exception message details.")]
            [ValidateNotNullOrEmpty()]
            [string]$Message,

            [parameter(Mandatory=$false, HelpMessage="Specify the violation exception causing the error.")]
            [ValidateNotNullOrEmpty()]
            [string]$Exception = "System.Management.Automation.RuntimeException",

            [parameter(Mandatory=$false, HelpMessage="Specify the error category of the exception causing the error.")]
            [ValidateNotNullOrEmpty()]
            [System.Management.Automation.ErrorCategory]$ErrorCategory = [System.Management.Automation.ErrorCategory]::NotImplemented,
            
            [parameter(Mandatory=$false, HelpMessage="Specify the target object causing the error.")]
            [ValidateNotNullOrEmpty()]
            [string]$TargetObject = ([string]::Empty)
        )
        # Construct new error record to be returned from function based on parameter inputs
        $SystemException = New-Object -TypeName $Exception -ArgumentList $Message
        $ErrorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList @($SystemException, $ErrorID, $ErrorCategory, $TargetObject)

        # Handle return value
        return $ErrorRecord
    }

    function Connect-WebService {
        # Construct new web service proxy
        try {
			$WebService = New-WebServiceProxy -Uri $URI -ErrorAction Stop
			Write-CMLogEntry -Value " - Successfully connected to ConfigMgr WebService at URI: $($URI)" -Severity 1

			# Handle return value
			return $WebService
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Unable to establish a connection to ConfigMgr WebService. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }        
    }

    function Get-OSImageDetails {
		$OSImageDetails = [PSCustomObject]@{
			Architecture = $null
			Name = $null
			Version = $null
		}

        switch ($DeploymentType) {
            "BareMetal" {
                # Get OS Image data
                $OSImageData = Get-OSImageData
                
                # Get OS data
                $OSImageVersion = $OSImageData.OSVersion
                $OSArchitecture = $OSImageData.OSArchitecture
                
                # Translate operating system name from version
                $OSDetails = Get-OSDetails -InputObject $OSImageVersion
                $OSImageDetails.Name = $OSDetails.OSName
                $OSImageDetails.Version = $OSDetails.OSVersion
                
                # Translate operating system architecture from web service response
                $OSImageDetails.Architecture = Get-OSArchitecture -InputObject $OSArchitecture
            }
            "OSUpgrade" {
                # Get OS Image data
                $OSImageData = Get-OSImageData
                
                # Get OS data
                $OSImageVersion = $OSImageData.OSVersion
                $OSArchitecture = $OSImageData.OSArchitecture
                
                # Translate operating system name from version
                $OSDetails = Get-OSDetails -InputObject $OSImageVersion
                $OSImageDetails.Name = $OSDetails.OSName
                $OSImageDetails.Version = $OSDetails.OSVersion
                
                # Translate operating system architecture from web service response
                $OSImageDetails.Architecture = Get-OSArchitecture -InputObject $OSArchitecture
            }
            "DriverUpdate" {
                # Get OS data
                $OSImageVersion = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty Version
                $OSArchitecture = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty OSArchitecture
                
                # Translate operating system name from version
                $OSDetails = Get-OSDetails -InputObject $OSImageVersion
                $OSImageDetails.Name = $OSDetails.OSName
                $OSImageDetails.Version = $OSDetails.OSVersion
                
                # Translate operating system architecture from running operating system
                $OSImageDetails.Architecture = Get-OSArchitecture -InputObject $OSArchitecture
            }
            "PreCache" {
                # Get OS Image data
                $OSImageData = Get-OSImageData
                
                # Get OS data
                $OSImageVersion = $OSImageData.OSVersion
                $OSArchitecture = $OSImageData.OSArchitecture
                
                # Translate operating system name from version
                $OSDetails = Get-OSDetails -InputObject $OSImageVersion
                $OSImageDetails.Name = $OSDetails.OSName
                $OSImageDetails.Version = $OSDetails.OSVersion
                
                # Translate operating system architecture from web service response
                $OSImageDetails.Architecture = Get-OSArchitecture -InputObject $OSArchitecture
            }		
		}
		
		# Handle output to log file for OS image details
        Write-CMLogEntry -Value " - Target operating system name detected as: $($OSImageDetails.Name)" -Severity 1
        Write-CMLogEntry -Value " - Target operating system architecture detected as: $($OSImageDetails.Architecture)" -Severity 1
        Write-CMLogEntry -Value " - Target operating system build version detected as: $($OSImageVersion)" -Severity 1
		Write-CMLogEntry -Value " - Target operating system translated version detected as: $($OSImageDetails.Version)" -Severity 1
		
		# Handle return value
		return $OSImageDetails
    }    

    function Get-DriverPackages {
		param(
			[parameter(Mandatory = $true, HelpMessage = "Specify the web service object returned from Connect-WebService function.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$WebService
		)        
        try {
            # Retrieve driver packages but filter out matches depending on script operational mode
            switch ($OperationalMode) {
                "Production" {
                    $Packages = $WebService.GetCMPackage($SecretKey, $Filter) | Where-Object { $_.PackageName -notmatch "Pilot" -and $_.PackageName -notmatch "Retired" }
                }
                "Pilot" {
                    $Packages = $WebService.GetCMPackage($SecretKey, $Filter) | Where-Object { $_.PackageName -match "Pilot" }
                }
            }
		
			# Handle return value
			if ($Packages -ne $null) {
				Write-CMLogEntry -Value " - Retrieved a total of '$(($Packages | Measure-Object).Count)' driver packages from web service matching operational mode: $($OperationalMode)" -Severity 1
				return $Packages
			}
			else {
				Write-CMLogEntry -Value " - Retrieved a total of '0' driver packages from web service matching operational mode: $($OperationalMode)" -Severity 3

				# Throw terminating error
				$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
				$PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - An error occurred while calling ConfigMgr WebService for a list of available driver packages. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }        
	}

    function Get-ComputerData {
		# Create a custom object for computer details gathered from local WMI
		$ComputerDetails = [PSCustomObject]@{
			Manufacturer = $null
			Model = $null
			SystemSKU = $null
			FallbackSKU = $null
		}

        # Gather computer details based upon specific computer manufacturer
        $ComputerManufacturer = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Manufacturer).Trim()
        switch -Wildcard ($ComputerManufacturer) {
            "*Microsoft*" {
				$ComputerDetails.Manufacturer = "Microsoft"
                $ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
                $ComputerDetails.SystemSKU = Get-WmiObject -Namespace "root\wmi" -Class "MS_SystemInformation" | Select-Object -ExpandProperty SystemSKU
            }
            "*HP*" {
                $ComputerDetails.Manufacturer = "Hewlett-Packard"
                $ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
                $ComputerDetails.SystemSKU = (Get-CIMInstance -ClassName "MS_SystemInformation" -NameSpace "root\WMI").BaseBoardProduct.Trim()
            }
            "*Hewlett-Packard*" {
                $ComputerDetails.Manufacturer = "Hewlett-Packard"
                $ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
                $ComputerDetails.SystemSKU = (Get-CIMInstance -ClassName "MS_SystemInformation" -NameSpace "root\WMI").BaseBoardProduct.Trim()
            }
            "*Dell*" {
                $ComputerDetails.Manufacturer = "Dell"
                $ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
                $ComputerDetails.SystemSKU = (Get-CIMInstance -ClassName "MS_SystemInformation" -NameSpace "root\WMI").SystemSku.Trim()
                [string]$OEMString = Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty OEMStringArray
                $ComputerDetails.FallbackSKU = [regex]::Matches($OEMString, '\[\S*]')[0].Value.TrimStart("[").TrimEnd("]")                
            }
            "*Lenovo*" {
                $ComputerDetails.Manufacturer = "Lenovo"
                $ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystemProduct" | Select-Object -ExpandProperty Version).Trim()
                $ComputerDetails.SystemSKU = ((Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).SubString(0, 4)).Trim()
            }
            "*Panasonic*" {
                $ComputerDetails.Manufacturer = "Panasonic Corporation"
                $ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
                $ComputerDetails.SystemSKU = (Get-CIMInstance -ClassName "MS_SystemInformation" -NameSpace "root\WMI").BaseBoardProduct.Trim()
            }
            "*Viglen*" {
                $ComputerDetails.Manufacturer = "Viglen"
                $ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
                $ComputerDetails.SystemSKU = (Get-WmiObject -Class "Win32_BaseBoard" | Select-Object -ExpandProperty SKU).Trim()
            }
        }
        
        # Handle output to log file for computer details
        Write-CMLogEntry -Value " - Computer manufacturer determined as: $($ComputerDetails.Manufacturer)" -Severity 1
        Write-CMLogEntry -Value " - Computer model determined as: $($ComputerDetails.Model)" -Severity 1

        # Handle output to log file for computer SystemSKU
        if (-not([string]::IsNullOrEmpty($ComputerDetails.SystemSKU))) {
            Write-CMLogEntry -Value " - Computer SystemSKU determined as: $($ComputerDetails.SystemSKU)" -Severity 1
        }
        else {
            Write-CMLogEntry -Value " - Computer SystemSKU determined as: <null>" -Severity 2
        }

        # Handle output to log file for Fallback SKU
        if (-not([string]::IsNullOrEmpty($ComputerDetails.FallBackSKU))) {
            Write-CMLogEntry -Value " - Computer Fallback SystemSKU determined as: $($ComputerDetails.FallBackSKU)" -Severity 1
		}
		
		# Handle return value from function
		return $ComputerDetails
    }

    function Get-ComputerSystemType {
        $ComputerSystemType = Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty "Model"
        if ($ComputerSystemType -notin @("Virtual Machine", "VMware Virtual Platform", "VirtualBox", "HVM domU", "KVM")) {
            Write-CMLogEntry -Value " - Supported computer platform detected, script execution allowed to continue" -Severity 1
        }
        else {
            Write-CMLogEntry -Value " - Unsupported computer platform detected, virtual machines are not supported" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Test-ComputerDetails {
		param(
			[parameter(Mandatory = $true, HelpMessage = "Specify the computer details object from Get-ComputerDetails function.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$InputObject
		)
        # Construct custom object for computer details validation
        $Script:ComputerDetection = [PSCustomObject]@{
            "ModelDetected" = $false
            "SystemSKUDetected" = $false
        }

        if (($InputObject.Model -ne $null) -and (-not([System.String]::IsNullOrEmpty($InputObject.Model)))) {
            Write-CMLogEntry -Value " - Computer model detection was successful" -Severity 1
            $ComputerDetection.ModelDetected = $true
        }

        if (($InputObject.SystemSKU -ne $null) -and (-not([System.String]::IsNullOrEmpty($InputObject.SystemSKU)))) {
            Write-CMLogEntry -Value " - Computer SystemSKU detection was successful" -Severity 1
            $ComputerDetection.SystemSKUDetected = $true
        }

        if (($ComputerDetection.ModelDetected -eq $false) -and ($ComputerDetection.SystemSKUDetected -eq $false)) {
            Write-CMLogEntry -Value " - Computer model and SystemSKU values are missing, script execution is not allowed since required values to continue could not be gathered" -Severity 3
            
            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
        else {
            Write-CMLogEntry -Value " - Computer details successfully verified" -Severity 1
        }
    }

    function Set-ComputerDetectionMethod {
        if ($ComputerDetection.SystemSKUDetected -eq $true) {
            $Script:ComputerDetectionMethod = "SystemSKU"
            Write-CMLogEntry -Value " - Determined primary computer detection method: $($ComputerDetectionMethod)" -Severity 1
        }
        else {
            $Script:ComputerDetectionMethod = "ComputerModel"
            Write-CMLogEntry -Value " - Determined fallback computer detection method: $($ComputerDetectionMethod)" -Severity 1
        }
	}
	
	function Confirm-DriverPackage {
		param(
			[parameter(Mandatory = $true, HelpMessage = "Specify the computer details object from Get-ComputerDetails function.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$ComputerData,

			[parameter(Mandatory = $true, HelpMessage = "Specify the OS Image details object from Get-OSImageDetails function.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$OSImageData,

			[parameter(Mandatory = $true, HelpMessage = "Specify the driver package object to be validated.")]
			[ValidateNotNullOrEmpty()]
			[System.Object[]]$DriverPackage
		)
		# Sort all driver package objects by package name property
		$DriverPackages = $DriverPackage | Sort-Object -Property PackageName

		Write-CMLogEntry -Value "- Limiting driver package results to detected computer manufacturer: $($ComputerData.Manufacturer)" -Severity 1
		$DriverPackages = $DriverPackages | Where-Object { $_.PackageManufacturer -like $ComputerData.Manufacturer }

		foreach ($DriverPackageItem in $DriverPackages) {
			Write-CMLogEntry -Value "[DriverPackage:$($DriverPackageItem.PackageID)]: Processing driver package: $($DriverPackageItem.PackageName)" -Severity 1

			# Construct custom object to hold values for current driver package properties used for matching with current computer details
			$DriverPackageDetails = [PSCustomObject]@{
				PackageID = $DriverPackageItem.PackageID
				PackageVersion = $DriverPackageItem.PackageVersion
				DateCreated = $DriverPackageItem.PackageCreated
				Manufacturer = $DriverPackageItem.PackageManufacturer
				Model = $null
				SystemSKU = $DriverPackageItem.PackageDescription.Split(":").Replace("(", "").Replace(")", "")[1]
				OSName = $null
				OSVersion = $null
				Architecture = $null 
			}
			
			# Add driver package model details depending on manufacturer to custom driver package details object
			# - Hewlett-Packard computer models include 'HP' in the model property and requires special attention for detecting the proper model value from the driver package name property
			switch ($DriverPackageItem.PackageManufacturer) {
				"Hewlett-Packard" {
					$DriverPackageDetails.Model = $DriverPackageItem.PackageName.Replace("Hewlett-Packard", "HP").Replace(" - ", ":").Split(":").Trim()[1]
				}
				Default {
					$DriverPackageDetails.Model = $DriverPackageItem.PackageName.Replace($DriverPackageItem.PackageManufacturer, "").Replace(" - ", ":").Split(":").Trim()[1]
				}
			}

			# Add driver package OS architecture details to custom driver package details object
			if ($DriverPackageItem.PackageName -match "^.*(?<Architecture>(x86|x64)).*") {
				$DriverPackageDetails.Architecture = $Matches.Architecture
			}

			# Add driver package OS name details to custom driver package details object
			if ($DriverPackageItem.PackageName -match "^.*Windows.*(?<OSName>(10)).*") {
				$DriverPackageDetails.OSName = -join@("Windows ", $Matches.OSName)
			}

			# Add driver package OS version details to custom driver package details object
			if ($DriverPackageItem.PackageName -match "^.*Windows.*(?<OSVersion>(\d){4}).*") {
				$DriverPackageDetails.OSVersion = $Matches.OSVersion
			}

			switch ($ComputerDetectionMethod) {
				"SystemSKU" {
					# Attempt to match against SystemSKU
					$ComputerDetectionMethodResult = Confirm-SystemSKU -DriverPackageInput $DriverPackageDetails.SystemSKU -ComputerData $ComputerData

					# Fall back to using computer model as the detection method instead of SystemSKU
					if ($ComputerDetectionMethodResult -eq $false) {
						$ComputerDetectionMethodResult = Confirm-ComputerModel -DriverPackageInput $DriverPackageDetails.Model -ComputerData $ComputerData
					}
				}
				"ComputerModel" {
					# Attempt to match against computer model
					$ComputerDetectionMethodResult = Confirm-ComputerModel -DriverPackageInput $DriverPackageDetails.Model -ComputerData $ComputerData
				}
			}

			if ($ComputerDetectionMethodResult -eq $true) {
				# Attempt to match against OS name
				$OSNameDetectionResult = Confirm-OSName -DriverPackageInput $DriverPackageDetails.OSName -OSImageData $OSImageData
				if ($OSNameDetectionResult -eq $true) {
					$OSArchitectureDetectionResult = Confirm-Architecture -DriverPackageInput $DriverPackageDetails.Architecture -OSImageData $OSImageData
					if ($OSArchitectureDetectionResult -eq $true) {
						if ($DriverPackageDetails.OSVersion -ne $null) {
							$OSVersionDetectionResult = Confirm-OSVersion -DriverPackageInput $DriverPackageDetails.OSVersion -OSImageData $OSImageData
							if ($OSVersionDetectionResult -eq $true) {
								# Match found for all critiera including OS version
								Write-CMLogEntry -Value "[DriverPackage:$($DriverPackageItem.PackageID)]: Match found between driver package and computer, adding to list for post-processing matched driver packages" -Severity 1
								$DriverPackageList.Add($DriverPackageDetails) | Out-Null
							}
						}
						else {
							# Match found for all critiera except for OS version, assuming here that the vendor does not provide OS version specific driver packages
							Write-CMLogEntry -Value "[DriverPackage:$($DriverPackageItem.PackageID)]: Match found between driver package and computer, adding to list for post-processing matched driver packages" -Severity 1
							$DriverPackageList.Add($DriverPackageDetails) | Out-Null
						}
					}
				}
			}
		}
	}

	function Confirm-OSVersion {
		param(
			[parameter(Mandatory = $true, HelpMessage = "Specify the OS version value from the driver package object.")]
			[ValidateNotNullOrEmpty()]
			[string]$DriverPackageInput,

			[parameter(Mandatory = $true, HelpMessage = "Specify the computer data object.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$OSImageData
		)
		if ($DriverPackageInput -like $OSImageData.Version) {
			# Computer model match found
			Write-CMLogEntry -Value " - Matched operating system version: $($OSImageData.Version)" -Severity 1
			return $true
		}
		else {
			# Computer model match was not found
			return $false
		}
	}	

	function Confirm-Architecture {
		param(
			[parameter(Mandatory = $true, HelpMessage = "Specify the Architecture value from the driver package object.")]
			[ValidateNotNullOrEmpty()]
			[string]$DriverPackageInput,

			[parameter(Mandatory = $true, HelpMessage = "Specify the computer data object.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$OSImageData
		)
		if ($DriverPackageInput -like $OSImageData.Architecture) {
			# Computer model match found
			Write-CMLogEntry -Value " - Matched operating system architecture: $($OSImageData.Architecture)" -Severity 1
			return $true
		}
		else {
			# Computer model match was not found
			return $false
		}
	}

	function Confirm-OSName {
		param(
			[parameter(Mandatory = $true, HelpMessage = "Specify the OS name value from the driver package object.")]
			[ValidateNotNullOrEmpty()]
			[string]$DriverPackageInput,

			[parameter(Mandatory = $true, HelpMessage = "Specify the computer data object.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$OSImageData
		)
		if ($DriverPackageInput -like $OSImageData.Name) {
			# Computer model match found
			Write-CMLogEntry -Value " - Matched operating system name: $($OSImageData.Name)" -Severity 1
			return $true
		}
		else {
			# Computer model match was not found
			return $false
		}
	}

	function Confirm-ComputerModel {
		param(
			[parameter(Mandatory = $true, HelpMessage = "Specify the computer model value from the driver package object.")]
			[ValidateNotNullOrEmpty()]
			[string]$DriverPackageInput,

			[parameter(Mandatory = $true, HelpMessage = "Specify the computer data object.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$ComputerData
		)
		if ($DriverPackageInput -like $ComputerData.Model) {
			# Computer model match found
			Write-CMLogEntry -Value " - Matched computer model: $($ComputerData.Model)" -Severity 1
			return $true
		}
		else {
			# Computer model match was not found
			return $false
		}
	}

	function Confirm-SystemSKU {
		param(
			[parameter(Mandatory = $true, HelpMessage = "Specify the SystemSKU value from the driver package object.")]
			[ValidateNotNullOrEmpty()]
			[string]$DriverPackageInput,

			[parameter(Mandatory = $true, HelpMessage = "Specify the computer data object.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$ComputerData
		)

		# Handle multiple SystemSKU's from driver package input and determine the proper delimiter
		if ($ComputerData.SystemSKU -match ",") {
			$SystemSKUDelimiter = ","
		}
		if ($ComputerData.SystemSKU -match ";") {
			$SystemSKUDelimiter = ";"
		}

		# Attempt to determine if the driver package input matches with the computer data input and account for multiple SystemSKU's by separating them with the detected delimiter
		if (-not([string]::IsNullOrEmpty($SystemSKUDelimiter))) {
			# Attempt to match for each SystemSKU item based on computer data input
			foreach ($SystemSKUItem in ($ComputerData.SystemSKU -split $SystemSKUDelimiter)) {
				if ($DriverPackageInput -match $SystemSKUItem) {
					$SystemSKUDetectionResult = $true
				}
				else {
					$SystemSKUDetectionResult = $false	
				}
			}
			if ($SystemSKUDetectionResult -eq $true) {
				# SystemSKU match found based upon multiple items detected in computer data input
				Write-CMLogEntry -Value " - Matched SystemSKU: $($ComputerData.SystemSKU)" -Severity 1
				return $true
			}
			else {
				# SystemSKU match was not found based upon multiple items detected in computer data input
				return $false
			}
		}
		elseif ($DriverPackageInput -match $ComputerData.SystemSKU) {
			# SystemSKU match found based upon single item detected in computer data input
			Write-CMLogEntry -Value " - Matched SystemSKU: $($ComputerData.SystemSKU)" -Severity 1
			return $true
		}
		elseif ((-not([string]::IsNullOrEmpty($ComputerData.FallbackSKU))) -and ($DriverPackageInput -match $ComputerData.FallbackSKU)) {
			# SystemSKU match found using FallbackSKU value using detection method OEMString, this should only be valid for Dell
			Write-CMLogEntry -Value " - Matched SystemSKU: $($ComputerData.FallbackSKU)" -Severity 1
			return $true
		}
		else {
			# None of the above methods worked to match SystemSKU from driver package input with computer data input
			return $false
		}
	}

    Write-CMLogEntry -Value "[ApplyDriverPackage]: Apply Driver Package process initiated" -Severity 1

	# Set script error preference variable
	$ErrorActionPreference = "Stop"

    # Construct array list for matched drivers packages
	$DriverPackageList = New-Object -TypeName "System.Collections.ArrayList"

	if ($PSCmdLet.ParameterSetName -eq "Execute") {
		Write-CMLogEntry -Value " - Driver download package process initiated" -Severity 1
	}
	elseif ($PSCmdLet.ParameterSetName -eq "Debug") {
		Write-CMLogEntry -Value " - Driver download package process initiated in debug mode" -Severity 1
	}

    try {
        Write-CMLogEntry -Value "[PrerequisiteChecker]: Starting environment prerequisite checker" -Severity 1

        # Determine if running on supported computer system type
        Get-ComputerSystemType

        # Determine computer manufacturer, model, SystemSKU and FallbackSKU
        $ComputerData = Get-ComputerData

        # Validate required computer details have successfully been gathered from WMI
        Test-ComputerDetails -InputObject $ComputerData

        # Determine the computer detection method to be used for matching against driver packages
        Set-ComputerDetectionMethod

        Write-CMLogEntry -Value "[PrerequisiteChecker]: Completed environment prerequisite checker" -Severity 1
        Write-CMLogEntry -Value "[WebService]: Starting ConfigMgr WebService phase" -Severity 1

        # Connect and establish connection to ConfigMgr WebService
        $WebService = Connect-WebService

        # Retrieve available driver packages from web service
        $DriverPackages = Get-DriverPackages -WebService $WebService

        # Determine the OS image version and architecture values based upon deployment type
        # Detection are performed according to the following rules:
        # - BareMetal: From the Operating System Image defined in the running task sequence
        # - OSUpgrade: From the Operating System Upgrade Package defined in the running task sequence
        # - DriverUpdate: From the running operating system
        # OS image version can be overriden by using the TargetOSVersion parameter for BareMetal and OSUpgrade deployment types and is handled within the functions dependant to the executed function below
		$OSImageDetails = Get-OSImageDetails

		Write-CMLogEntry -Value "[WebService]: Completed ConfigMgr WebService phase" -Severity 1
		Write-CMLogEntry -Value "[DriverPackage]: Starting driver package matching phase" -Severity 1

		# Match detected driver packages from web service call with computer details and OS image details gathered previously
		Confirm-DriverPackage -ComputerData $ComputerData -OSImageData $OSImageDetails -DriverPackage $DriverPackages

		Write-CMLogEntry -Value "[DriverPackage]: Completed driver package matching phase" -Severity 1
		Write-CMLogEntry -Value "[DriverPackagePreparation]: Starting driver package preparation phase" -Severity 1


		$DriverPackageList


		Write-CMLogEntry -Value "[DriverPackagePreparation]: Completed driver package preparation phase" -Severity 1

		# TESTING ONLY - REMOVE
		$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
		$PSCmdlet.ThrowTerminatingError($ErrorRecord)
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "[ApplyDriverPackage]: Apply Driver Package process failed, please refer to previous error or warning messages" -Severity 3
	}
	


	# Handle log output for matched driver package properties
	#Write-CMLogEntry -Value "[DriverPackage:$($DriverPackageItem.PackageID)]: Manufacturer: $($DriverPackageDetails.Manufacturer)" -Severity 1
	#Write-CMLogEntry -Value "[DriverPackage:$($DriverPackageItem.PackageID)]: Model: $($DriverPackageDetails.Model)" -Severity 1
	#Write-CMLogEntry -Value "[DriverPackage:$($DriverPackageItem.PackageID)]: SystemSKU: $($DriverPackageDetails.SystemSKU)" -Severity 1
	#Write-CMLogEntry -Value "[DriverPackage:$($DriverPackageItem.PackageID)]: OSName: $($DriverPackageDetails.OSName)" -Severity 1
	#Write-CMLogEntry -Value "[DriverPackage:$($DriverPackageItem.PackageID)]: OSVersion: $($DriverPackageDetails.OSVersion)" -Severity 1
	#Write-CMLogEntry -Value "[DriverPackage:$($DriverPackageItem.PackageID)]: Architecture: $($DriverPackageDetails.Architecture)" -Severity 1



    ##### END for 3.0.0 Preview
	
	# Validate operating system name was detected
	if ($OSName -ne $null) {
		# Validate not virtual machine
		
		if ($ComputerSystemType -notin @("Virtual Machine", "VMware Virtual Platform", "VirtualBox", "HVM domU", "KVM")) {
			if ($Packages -ne $null) {
				if (($ComputerModel -ne $null) -and (-not([System.String]::IsNullOrEmpty($ComputerModel))) -or (($SystemSKU -ne $null) -and (-not([System.String]::IsNullOrEmpty($SystemSKU))))) {

					
					# Process each package returned from web service
					foreach ($Package in $Packages) {
					
						if ($DetectionContinue -eq $true) {


							
							
							# Match manufacturer, operating system name and architecture criteria
							if ($ComputerDetectionResult -eq $true) {
								if (($Package.PackageManufacturer -match $ComputerManufacturer) -and ($Package.PackageName -match $OSName) -and ($Package.PackageName -match $OSImageArchitecture) -and ($Package.PackageDescription -match $SystemSKU)) {
									# Match operating system criteria per manufacturer for Windows 10 packages only
									if ($OSName -match "Windows 10") {
										if ($Package.PackageName -match $OSVersion) {
											Write-CMLogEntry -Value "Attempting to match driver package name with OS name '$($OSName)' and version $($OSVersion) for $($ComputerManufacturer)" -Severity 1
											$Package | Add-Member -NotePropertyName "OSVersionDetected" -NotePropertyValue $true
											$MatchFound = $true
										}
										else {
											Write-CMLogEntry -Value "Unable to match driver package name with OS version '$($OSVersion)', falling back to match found for '$($OSName)'" -Severity 1
											$Package | Add-Member -NotePropertyName "OSVersionDetected" -NotePropertyValue $false
											$MatchFound = $true
										}
									}
									else {
										Write-CMLogEntry -Value "Match found between driver package and legacy operating system" -Severity 1
										$MatchFound = $true
									}
									
									# Add package to list if match is found
									if ($MatchFound -eq $true) {
										Write-CMLogEntry -Value "Match found for manufacturer, operating system and architecture: $($Package.PackageName) ($($Package.PackageID))" -Severity 1
										Write-CMLogEntry -Value "Adding driver package to list of packages to process" -Severity 1
										$PackageList.Add($Package) | Out-Null
									}
									else {
										Write-CMLogEntry -Value "Unable to find a match for all criteria for driver package, driver package will not be added to list of matching packages" -Severity 2
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
					}
					
					# Process matching items in package list
					if ($PackageList -ne $null) {
						# Determine the most current package from list
						if (-not ($PSCmdLet.ParameterSetName -eq "Debug")) {
							if ($PackageList.Count -eq 1) {
								try {
									# Attempt to download driver package content
									Write-CMLogEntry -Value "Driver package list contains a single match, attempting to download driver package content - $($PackageList[0].PackageID)" -Severity 1
									switch ($DeploymentType) {
										"PreCache" {
											$DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageList[0].PackageID -DestinationLocationType CCMCache -DestinationVariableName "OSDDriverPackage"
										}
										Default {
											$DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageList[0].PackageID -DestinationLocationType Custom -DestinationVariableName "OSDDriverPackage" -CustomLocationPath "%_SMSTSMDataPath%\DriverPackage"
										}
									}
									
									try {
										if ($DownloadInvocation -eq 0) {
											$OSDDriverPackageLocation = $($TSEnvironment.Value('OSDDriverPackage01'))
											Write-CMLogEntry -Value "Driver files storage location set to $($OSDDriverPackageLocation)" -Severity 1
											
											switch ($DeploymentType) {
												"BareMetal" {
													# Apply drivers recursively from downloaded driver package location
													Write-CMLogEntry -Value "Driver package content downloaded successfully, attempting to apply drivers using dism.exe located in: $($OSDDriverPackageLocation)" -Severity 1
													
													# Determine driver injection method from parameter input
													switch ($DriverInstallMode) {
														"Single" {
															try {
																# Get driver full path and install each driver seperately
																$DriverINFs = Get-ChildItem -Path $OSDDriverPackageLocation -Recurse -Filter "*.inf" -ErrorAction Stop | Select-Object -Property FullName, Name
																if ($DriverINFs -ne $null) {
																	foreach ($DriverINF in $DriverINFs) {
																		# Install specific driver
																		Write-CMLogEntry -Value "Attempting to install driver: $($DriverINF.FullName)" -Severity 1
																		$ApplyDriverInvocation = Invoke-Executable -FilePath "Dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDTargetSystemDrive'))\ /Add-Driver /Driver:`"$($DriverINF.FullName)`""
																		
																		# Validate driver injection
																		if ($ApplyDriverInvocation -eq 0) {
																			Write-CMLogEntry -Value "Successfully applied driver using dism.exe" -Severity 1
																		}
																		else {
																			Write-CMLogEntry -Value "An error occurred while applying driver. Continuing with warning code: $($ApplyDriverInvocation). See DISM.log for more details" -Severity 2
																		}
																	}
																}
																else {
																	Write-CMLogEntry -Value "An error occurred while enumerating driver paths, downloaded driver package does not contain any INF files" -Severity 3; exit 22
																}
															}
															catch [System.Exception] {
																Write-CMLogEntry -Value "An error occurred while installing drivers. See DISM.log for more details" -Severity 2
															}
														}
														"Recurse" {
															# Apply drivers recursively
															$ApplyDriverInvocation = Invoke-Executable -FilePath "Dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDTargetSystemDrive'))\ /Add-Driver /Driver:$($OSDDriverPackageLocation) /Recurse"
															
															# Validate driver injection
															if ($ApplyDriverInvocation -eq 0) {
																Write-CMLogEntry -Value "Successfully applied drivers using dism.exe" -Severity 1
															}
															else {
																Write-CMLogEntry -Value "An error occurred while applying drivers (single package match). Continuing with warning code: $($ApplyDriverInvocation). See DISM.log for more details" -Severity 2
															}
														}
													}
												}
												"OSUpgrade" {
													# For OSUpgrade, don't attempt to install drivers as this is handled by setup.exe when used together with OSDUpgradeStagedContent
													Write-CMLogEntry -Value "Driver package content downloaded successfully and located in: $($OSDDriverPackageLocation)" -Severity 1
													
													# Set OSDUpgradeStagedContent task sequence variable
													Write-CMLogEntry -Value "Attempting to set OSDUpgradeStagedContent task sequence variable with value: $($OSDDriverPackageLocation)" -Severity 1
													$TSEnvironment.Value("OSDUpgradeStagedContent") = "$($OSDDriverPackageLocation)"
													Write-CMLogEntry -Value "Successfully completed driver package staging process" -Severity 1
												}
												"DriverUpdate" {
													# Apply drivers recursively from downloaded driver package location
													Write-CMLogEntry -Value "Driver package content downloaded successfully, attempting to apply drivers using pnputil.exe located in: $($OSDDriverPackageLocation)" -Severity 1
													$ApplyDriverInvocation = Invoke-Executable -FilePath "powershell.exe" -Arguments "pnputil /add-driver $(Join-Path -Path $OSDDriverPackageLocation -ChildPath '*.inf') /subdirs /install | Out-File -FilePath (Join-Path -Path $($LogsDirectory) -ChildPath 'Install-Drivers.txt') -Force"
													Write-CMLogEntry -Value "Successfully applied drivers" -Severity 1
												}
												"PreCache" {
													# Driver package content downloaded successfully, log output and exit script
													Write-CMLogEntry -Value "Driver package content successfully downloaded and pre-cached to: $($OSDDriverPackageLocation)" -Severity 1
												}
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
								# Handle multiple matches when the computer detection method SystemSKU is used
								if (($ComputerDetectionMethod -like "SystemSKU")) {
									Write-CMLogEntry -Value "Driver package list contains $($PackageList.Count) matches. Attempting to remove driver packages that do not match the computer model." -Severity 1
									
									# Process driver package list in reverse
									for ($i = ($PackageList.Count - 1); $i -ge 0; $i--) {
										switch ($ComputerManufacturer) {
											"Hewlett-Packard" {
												$PackageNameComputerModel = $PackageList[$i].PackageName.Replace("Hewlett-Packard", "HP").Replace(" - ", ":").Split(":").Trim()[1]
											}
											Default {
												$PackageNameComputerModel = $PackageList[$i].PackageName.Replace($ComputerManufacturer, "").Replace(" - ", ":").Split(":").Trim()[1]
											}
										}
										if ($PackageNameComputerModel -notmatch $ComputerModel) {
											Write-CMLogEntry -Value "Detected that the following driver package did not match the computer model: $($PackageList[$i].PackageName)" -Severity 1
											Write-CMLogEntry -Value "Removing driver package due to inconsistency between computer model value from WMI '$($ComputerModel)' and the translated driver package computer model name '$($PackageNameComputerModel)'" -Severity 1
											if ($PackageList[$i].OSVersionDetected -eq $false) {
												$PackageList.RemoveAt($i)
											}
										}
									}
									
									# If list is now empty, check log and verify that the driver package name matches what's in WMI
									if ($PackageList.Count -eq 0) {
										Write-CMLogEntry -Value "Computer model matching removed all driver packages due to inconsistency with computer name in WMI" -Severity 2
										Write-CMLogEntry -Value "Ensure that the desired driver package computer model name matches: $($ComputerModel)" -Severity 2
									}
								}
								
								try {
									Write-CMLogEntry -Value "Driver package list contains multiple matches, attempting to download driver package content based upon latest package creation date" -Severity 1
									# Determine matching driver package from array list with vendor specific solutions
									if (($ComputerManufacturer -like "Hewlett-Packard") -and ($OSName -like "Windows 10")) {
										Write-CMLogEntry -Value "Vendor specific matching required before downloading content. Attempting to match $($ComputerManufacturer) driver package based on OS build number: $($OSVersion)" -Severity 1
										$Package = ($PackageList | Where-Object { $_.PackageName -match $OSVersion }) | Sort-Object -Property PackageCreated -Descending | Select-Object -First 1
									}
									else {
										$Package = $PackageList | Sort-Object -Property PackageCreated -Descending | Select-Object -First 1
									}
									
									# Validate that there's a package available for download
									if ($Package -ne $null) {
										# Attempt to download driver package content
										Write-CMLogEntry -Value "Attempting to download driver package $($Package.PackageID) content from Distribution Point" -Severity 1
										switch ($DeploymentType) {
											"PreCache" {
												$DownloadInvocation = Invoke-CMDownloadContent -PackageID $Package.PackageID -DestinationLocationType CCMCache -DestinationVariableName "OSDDriverPackage"
											}
											Default {
												$DownloadInvocation = Invoke-CMDownloadContent -PackageID $Package.PackageID -DestinationLocationType Custom -DestinationVariableName "OSDDriverPackage" -CustomLocationPath "%_SMSTSMDataPath%\DriverPackage"
											}
										}
										
										try {
											if ($DownloadInvocation -eq 0) {
												$OSDDriverPackageLocation = $($TSEnvironment.Value('OSDDriverPackage01'))
												Write-CMLogEntry -Value "Driver files storage location set to $($OSDDriverPackageLocation)" -Severity 1

												switch ($DeploymentType) {
													"BareMetal" {
														# Apply drivers recursively from downloaded driver package location
														Write-CMLogEntry -Value "Driver package content downloaded successfully, attempting to apply drivers using dism.exe located in: $($OSDDriverPackageLocation)" -Severity 1
														
														# Determine driver injection method from parameter input
														switch ($DriverInstallMode) {
															"Single" {
																try {
																	# Get driver full path and install each driver seperately
																	$DriverINFs = Get-ChildItem -Path $OSDDriverPackageLocation -Recurse -Filter "*.inf" -ErrorAction Stop | Select-Object -Property FullName, Name
																	if ($DriverINFs -ne $null) {
																		foreach ($DriverINF in $DriverINFs) {
																			# Install specific driver
																			Write-CMLogEntry -Value "Attempting to install driver: $($DriverINF.FullName)" -Severity 1
																			$ApplyDriverInvocation = Invoke-Executable -FilePath "Dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDTargetSystemDrive'))\ /Add-Driver /Driver:$($DriverINF.FullName)"
																			
																			# Validate driver injection
																			if ($ApplyDriverInvocation -eq 0) {
																				Write-CMLogEntry -Value "Successfully applied driver using dism.exe" -Severity 1
																			}
																			else {
																				Write-CMLogEntry -Value "An error occurred while applying driver. Continuing with warning code: $($ApplyDriverInvocation). See DISM.log for more details" -Severity 2
																			}
																		}
																	}
																	else {
																		Write-CMLogEntry -Value "An error occurred while enumerating driver paths, downloaded driver package does not contain any INF files" -Severity 3; exit 22
																	}
																}
																catch [System.Exception] {
																	Write-CMLogEntry -Value "An error occurred while installing drivers. See DISM.log for more details" -Severity 2
																}
															}
															"Recurse" {
																# Apply drivers recursively
																$ApplyDriverInvocation = Invoke-Executable -FilePath "Dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDTargetSystemDrive'))\ /Add-Driver /Driver:$($OSDDriverPackageLocation) /Recurse"
																
																# Validate driver injection
																if ($ApplyDriverInvocation -eq 0) {
																	Write-CMLogEntry -Value "Successfully applied drivers using dism.exe" -Severity 1
																}
																else {
																	Write-CMLogEntry -Value "An error occurred while applying drivers (multiple package match). Continuing with warning code: $($ApplyDriverInvocation). See DISM.log for more details" -Severity 2
																}
															}
														}
													}
													"OSUpgrade" {
														# For OSUpgrade, don't attempt to install drivers as this is handled by setup.exe when used together with OSDUpgradeStagedContent
														Write-CMLogEntry -Value "Driver package content downloaded successfully and located in: $($OSDDriverPackageLocation)" -Severity 1
														
														# Set OSDUpgradeStagedContent task sequence variable
														Write-CMLogEntry -Value "Attempting to set OSDUpgradeStagedContent task sequence variable with value: $($OSDDriverPackageLocation)" -Severity 1
														$TSEnvironment.Value("OSDUpgradeStagedContent") = "$($OSDDriverPackageLocation)"
														Write-CMLogEntry -Value "Successfully completed driver package staging process" -Severity 1
													}
													"DriverUpdate" {
														# Apply drivers recursively from downloaded driver package location
														Write-CMLogEntry -Value "Driver package content downloaded successfully, attempting to apply drivers using pnputil.exe located in: $($OSDDriverPackageLocation)" -Severity 1
														$ApplyDriverInvocation = Invoke-Executable -FilePath "powershell.exe" -Arguments "pnputil /add-driver $(Join-Path -Path $OSDDriverPackageLocation -ChildPath '*.inf') /subdirs /install | Out-File -FilePath (Join-Path -Path $($LogsDirectory) -ChildPath 'Install-Drivers.txt') -Force"
														Write-CMLogEntry -Value "Successfully applied drivers" -Severity 1
													}
													"PreCache" {
														# Driver package content downloaded successfully, log output and exit script
														Write-CMLogEntry -Value "Driver package content successfully downloaded and pre-cached to: $($OSDDriverPackageLocation)" -Severity 1
													}
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
										Write-CMLogEntry -Value "An error occurred while selecting manufacturer specific driver packages from list, empty list of packages detected" -Severity 3
										switch ($DeploymentType) {
											"BareMetal" {
												exit 21
											}
											default {
												exit 0
											}
										}
									}
								}
								catch [System.Exception] {
									Write-CMLogEntry -Value "An error occurred while downloading driver package content (multiple package matches). Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 6
								}
							}
							else {
								Write-CMLogEntry -Value "Unable to determine a matching driver package from package list array, unhandled amount of matches" -Severity 2
								switch ($DeploymentType) {
									"BareMetal" {
										exit 7
									}
									default {
										exit 0
									}
								}
							}
						}
						else {
							Write-CMLogEntry -Value "Script has successfully completed DebugMode" -Severity 1
						}
					}
					elseif ($PSBoundParameters.ContainsKey("UseDriverFallback") -eq $true) {
						Write-CMLogEntry -Value "Driver fallback parameter specified and no matching computer model driver packages found" -Severity 1
						
						if ($Packages -ne $null) {
							# Process packages returned from web service
							Write-CMLogEntry -Value "Attempting to match a driver fallback package" -Severity 1
							foreach ($Package in $Packages) {
								Write-CMLogEntry -Value "Processing $($Package.PackageName)" -Severity 1
								if (($Package.PackageName -match "Driver Fallback") -and ($Package.PackageName -match $OSName) -and ($Package.PackageName -match $OSImageArchitecture)) {
									Write-CMLogEntry -Value "Found Driver Fallback package match: $($Package.PackageName)" -Severity 1
									$PackageList.Add($Package) | Out-Null
								}
							}
							
							# Process package list if not empty
							if (-not ($PSCmdLet.ParameterSetName -eq "Debug")) {
								if ($PackageList.Count -eq 1) {
									try {
										# Attempt to download driver fallback package content
										Write-CMLogEntry -Value "Attempting to download driver fallback package content" -Severity 1
										$DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageList[0].PackageID -DestinationLocationType Custom -DestinationVariableName "OSDDriverPackage" -CustomLocationPath "%_SMSTSMDataPath%\DriverPackage"
										
										try {
											if ($DownloadInvocation -eq 0) {
												$OSDDriverPackageLocation = $($TSEnvironment.Value('OSDDriverPackage01'))
												Write-CMLogEntry -Value "Driver files are storage location set to $($OSDDriverPackageLocation)" -Severity 1
												switch ($DeploymentType) {
													"BareMetal" {
														# Apply drivers recursively from downloaded driver package location
														Write-CMLogEntry -Value "Fall back driver package content downloaded successfully, attempting to apply drivers using dism.exe located in: $($OSDDriverPackageLocation)" -Severity 1
														# Determine driver injection method from parameter input
														switch ($DriverInstallMode) {
															"Single" {
																try {
																	# Get driver full path and install each driver seperately
																	$DriverINFs = Get-ChildItem -Path $OSDDriverPackageLocation -Recurse -Filter "*.inf" -ErrorAction Stop | Select-Object -Property FullName, Name
																	if ($DriverINFs -ne $null) {
																		foreach ($DriverINF in $DriverINFs) {
																			# Install specific driver
																			Write-CMLogEntry -Value "Attempting to install fall back driver: $($DriverINF.FullName)" -Severity 1
																			$ApplyDriverInvocation = Invoke-Executable -FilePath "Dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDTargetSystemDrive'))\ /Add-Driver /Driver:$($DriverINF.FullName)"
																			
																			# Validate driver injection
																			if ($ApplyDriverInvocation -eq 0) {
																				Write-CMLogEntry -Value "Successfully applied fall back driver using dism.exe" -Severity 1
																			}
																			else {
																				Write-CMLogEntry -Value "An error occurred while applying fallback driver. Continuing with warning code: $($ApplyDriverInvocation). See DISM.log for more details" -Severity 2
																			}
																		}
																	}
																	else {
																		Write-CMLogEntry -Value "An error occurred while enumerating fallback driver paths, downloaded driver package does not contain any INF files" -Severity 3; exit 22
																	}
																}
																catch [System.Exception] {
																	Write-CMLogEntry -Value "An error occurred while installing fallback drivers. See DISM.log for more details" -Severity 2
																}
															}
															"Recurse" {
																# Apply drivers recursively
																$ApplyDriverInvocation = Invoke-Executable -FilePath "Dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDTargetSystemDrive'))\ /Add-Driver /Driver:$($OSDDriverPackageLocation) /Recurse"
																
																# Validate driver injection
																if ($ApplyDriverInvocation -eq 0) {
																	Write-CMLogEntry -Value "Successfully applied fall back drivers using dism.exe" -Severity 1
																}
																else {
																	Write-CMLogEntry -Value "An error occurred while applying fallback drivers. Continuing with warning code: $($ApplyDriverInvocation). See DISM.log for more details" -Severity 2
																}
															}
														}
													}
													"OSUpgrade" {
														# Not a supported scenario as of yet
														Write-CMLogEntry -Value "Fall back driver package mode is not supported for OSUpgrades, bailing out" -Severity 2
													}
													"DriverUpdate" {
														# Apply drivers recursively from downloaded driver package location
														Write-CMLogEntry -Value "Driver fallback package content downloaded successfully, attempting to apply drivers using pnputil.exe located in: $($OSDDriverPackageLocation)" -Severity 1
														$ApplyDriverInvocation = Invoke-Executable -FilePath "powershell.exe" -Arguments "pnputil /add-driver $(Join-Path -Path $OSDDriverPackageLocation -ChildPath '*.inf') /subdirs /install | Out-File -FilePath (Join-Path -Path $($LogsDirectory) -ChildPath 'Install-Drivers.txt') -Force"
													}
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
							else {
								Write-CMLogEntry -Value "Script has successfully completed debug mode" -Severity 1
							}
						}
						else {
							Write-CMLogEntry -Value "Empty driver package list detected, unable to determine matching driver fallback package" -Severity 2; exit 8
						}
					}
					else {
						Write-CMLogEntry -Value "Computer model detection logic failed for all detected driver packages" -Severity 2; exit 9
					}
				}
				else {
					Write-CMLogEntry -Value "Computer model and SystemSKU values are either null or empty strings" -Severity 2
				}
			}
			else {
				Write-CMLogEntry -Value "No packages found. Please populate the driver repository" -Severity 2; exit 10
			}
		}
		else {
			Write-CMLogEntry -Value "Unsupported computer platform detected, virtual machines are not supported" -Severity 2; exit 10
		}
	}
	else {
		Write-CMLogEntry -Value "Unable to detect current operating system name from task sequence reference objects" -Severity 2; exit 11
	}
}
End {
	if ($PSCmdLet.ParameterSetName -eq "Execute") {
		# Reset OSDDownloadContent.exe dependant variables for further use of the task sequence step
		Invoke-CMResetDownloadContentVariables
	}
}