<#
.SYNOPSIS
	Download BIOS package (regular package) matching computer model and manufacturer.
	
.DESCRIPTION
    This script will determine the model of the computer and manufacturer and then query the specified endpoint
    for ConfigMgr WebService for a list of Packages. It then sets the OSDDownloadDownloadPackages variable to include
    the PackageID property of a package matching the computer model. If multiple packages are detect, it will select
	most current one by the creation date of the packages.

.PARAMETER DebugMode
	Set the script to operate in 'DebugMode' deployment type mode.

.PARAMETER Endpoint
	Specify the internal fully qualified domain name of the server hosting the AdminService, e.g. CM01.domain.local.

.PARAMETER UserName
	Specify the service account user name used for authenticating against the AdminService endpoint.

.PARAMETER Password
	Specify the service account password used for authenticating against the AdminService endpoint.
	
.PARAMETER Filter
	Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.

.PARAMETER OperationalMode
	Define the operational mode, either Production or Pilot, for when calling ConfigMgr WebService to only return objects matching the selected operational mode.

.PARAMETER Manufacturer
	Override the automatically detected computer manufacturer when running in debug mode.

.PARAMETER ComputerModel
	Override the automatically detected computer model when running in debug mode.

.PARAMETER SystemSKU
	Override the automatically detected SystemSKU when running in debug mode.

.PARAMETER OSVersionFallback
	Use this switch to check for drivers packages that matches earlier versions of Windows than what's specified as input for TargetOSVersion.

.EXAMPLE
	# Detect and download latest available BIOS package with ConfigMgr through the admin service:
	.\Invoke-CMDownloadBIOSPackage.ps1 -Endpoint "CM01.domain.com" 

	# Detect, and report on the matched BIOS release without downloading / in full OS
	.\Invoke-CMDownloadBIOSPackage.ps1 -Endpoint "CM01.domain.com" -UserName "Username" -Password "Password" -DebugMode
	
	# Detect, and report on the matched BIOS release without downloading / in full OS, with the make / model / sku specified
	.\Invoke-CMDownloadBIOSPackage.ps1 -Endpoint "CM01.domain.com" -UserName "Username" -Password "Password" -Manufacturer "HP" -ComptuerModel "ZBook Studio x360 G5" -SystemSKU "8427" -DebugMode

.NOTES
    FileName:    Invoke-CMDownloadBIOSPackage.ps1
	Author:      Nickolaj Andersen / Maurice Daly
    Contact:     @NickolajA / @MoDaly_IT
    Created:     2020-10-30
    Updated:     2020-10-30
    
    Version history:
    3.0.0 - (2020-10-30) - Script created
	3.0.1 - (2020-12-04) - Fixes to parameter sets, matching logic and removal of no longer code
						 - Added TS variable support for Resource URL

#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[parameter(Mandatory = $true, ParameterSetName = "Production", HelpMessage = "Specify the internal fully qualified domain name of the server hosting the AdminService, e.g. CM01.domain.local.")]
	[parameter(Mandatory = $true, ParameterSetName = "Debug")]
	[ValidateNotNullOrEmpty()]
	[string]$Endpoint,
	
	[parameter(Mandatory = $false, ParameterSetName = "Debug", HelpMessage = "Set the script to operate in 'DebugMode' deployment type mode.")]
	[switch]$DebugMode,
		
	[parameter(Mandatory = $true, ParameterSetName = "Debug", HelpMessage = "Specify the service account user name used for authenticating against the AdminService endpoint.")]
	[ValidateNotNullOrEmpty()]
	[string]$UserName = "",
	
	[parameter(Mandatory = $true, ParameterSetName = "Debug", HelpMessage = "Specify the service account password used for authenticating against the AdminService endpoint.")]
	[ValidateNotNullOrEmpty()]
	[string]$Password = "",
	
	[parameter(Mandatory = $false, ParameterSetName = "Production", HelpMessage = "Define a filter used when calling the AdminService to only return objects matching the filter.")]
	[ValidateNotNullOrEmpty()]
	[string]$Filter = "BIOS",
	
	[parameter(Mandatory = $false, ParameterSetName = "Production", HelpMessage = "Define the operational mode, either Production or Pilot, for when calling ConfigMgr WebService to only return objects matching the selected operational mode.")]
	[parameter(Mandatory = $true, ParameterSetName = "Debug")]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("Production", "Pilot")]
	[string]$OperationalMode = "Production",
	
	[parameter(Mandatory = $false, ParameterSetName = "Debug", HelpMessage = "Override the automatically detected computer manufacturer when running in debug mode.")]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("Hewlett-Packard", "HP", "Dell", "Lenovo", "Microsoft", "Fujitsu", "Panasonic", "Viglen", "AZW")]
	[string]$Manufacturer,
	
	[parameter(Mandatory = $false, ParameterSetName = "Debug", HelpMessage = "Override the automatically detected computer model when running in debug mode.")]
	[ValidateNotNullOrEmpty()]
	[string]$ComputerModel,
	
	[parameter(Mandatory = $false, ParameterSetName = "Debug", HelpMessage = "Override the automatically detected SystemSKU when running in debug mode.")]
	[ValidateNotNullOrEmpty()]
	[string]$SystemSKU
	
)
Begin {
	# Load Microsoft.SMS.TSEnvironment COM object
	if ($PSCmdLet.ParameterSetName -notlike "Debug") {
		try {
			$TSEnvironment = New-Object -ComObject "Microsoft.SMS.TSEnvironment" -ErrorAction Stop
		} catch [System.Exception] {
			Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object"; exit
		}
	}
}
Process {
	# Set Log Path
	switch ($PSCmdLet.ParameterSetName) {
		"Debug" {
			$LogsDirectory = Join-Path -Path $env:SystemRoot -ChildPath "Temp"
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
			[string]$FileName = "ApplyBIOSPackage.log"
		)
		# Determine log file location
		$LogFilePath = Join-Path -Path $LogsDirectory -ChildPath $FileName
		
		# Construct time stamp for log entry
		if (-not (Test-Path -Path 'variable:global:TimezoneBias')) {
			[string]$global:TimezoneBias = [System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes
			if ($TimezoneBias -match "^-") {
				$TimezoneBias = $TimezoneBias.Replace('-', '+')
			} else {
				$TimezoneBias = '-' + $TimezoneBias
			}
		}
		$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), $TimezoneBias)
		
		# Construct date for log entry
		$Date = (Get-Date -Format "MM-dd-yyyy")
		
		# Construct context for log entry
		$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		
		# Construct final log entry
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""ApplyBIOSPackage"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file
		try {
			Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
		} catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to ApplyBIOSPackage.log file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
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
		} catch [System.Exception] {
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
		
		# Set SMSTSDownloadRetryCount to 1000 to overcome potential BranchCache issue that will cause 'SendWinHttpRequest failed. 80072efe'
		$TSEnvironment.Value("SMSTSDownloadRetryCount") = 1000
		
		# Invoke download of package content
		try {
			if ($TSEnvironment.Value("_SMSTSInWinPE") -eq $false) {
				Write-CMLogEntry -Value " - Starting package content download process (FullOS), this might take some time" -Severity 1
				$ReturnCode = Invoke-Executable -FilePath (Join-Path -Path $env:windir -ChildPath "CCM\OSDDownloadContent.exe")
			} else {
				Write-CMLogEntry -Value " - Starting package content download process (WinPE), this might take some time" -Severity 1
				$ReturnCode = Invoke-Executable -FilePath "OSDDownloadContent.exe"
			}
			
			# Reset SMSTSDownloadRetryCount to 5 after attempted download
			$TSEnvironment.Value("SMSTSDownloadRetryCount") = 5
			
			# Match on return code
			if ($ReturnCode -eq 0) {
				Write-CMLogEntry -Value " - Successfully downloaded package content with PackageID: $($PackageID)" -Severity 1
			} else {
				Write-CMLogEntry -Value " - Failed to download package content with PackageID '$($PackageID)'. Return code was: $($ReturnCode)" -Severity 3
				
				# Throw terminating error
				$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
				$PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
		} catch [System.Exception] {
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
	
	function New-TerminatingErrorRecord {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Specify the exception message details.")]
			[ValidateNotNullOrEmpty()]
			[string]$Message,
			
			[parameter(Mandatory = $false, HelpMessage = "Specify the violation exception causing the error.")]
			[ValidateNotNullOrEmpty()]
			[string]$Exception = "System.Management.Automation.RuntimeException",
			
			[parameter(Mandatory = $false, HelpMessage = "Specify the error category of the exception causing the error.")]
			[ValidateNotNullOrEmpty()]
			[System.Management.Automation.ErrorCategory]$ErrorCategory = [System.Management.Automation.ErrorCategory]::NotImplemented,
			
			[parameter(Mandatory = $false, HelpMessage = "Specify the target object causing the error.")]
			[ValidateNotNullOrEmpty()]
			[string]$TargetObject = ([string]::Empty)
		)
		# Construct new error record to be returned from function based on parameter inputs
		$SystemException = New-Object -TypeName $Exception -ArgumentList $Message
		$ErrorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList @($SystemException, $ErrorID, $ErrorCategory, $TargetObject)
		
		# Handle return value
		return $ErrorRecord
	}
	
	function Get-DeploymentType {
		switch ($PSCmdlet.ParameterSetName) {
			"XMLPackage" {
				# Set required variables for XMLPackage parameter set
				$Script:DeploymentMode = $Script:XMLDeploymentType
				$Script:PackageSource = "XML Package Logic file"
				
				# Define the path for the pre-downloaded XML Package Logic file called DriverPackages.xml
				$script:XMLPackageLogicFile = (Join-Path -Path $TSEnvironment.Value("MDMXMLPackage01") -ChildPath "DriverPackages.xml")
				if (-not (Test-Path -Path $XMLPackageLogicFile)) {
					Write-CMLogEntry -Value " - Failed to locate required 'DriverPackages.xml' logic file for XMLPackage deployment type, ensure it has been pre-downloaded in a Download Package Content step before running this script" -Severity 3
					
					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}
			}
			default {
				$Script:DeploymentMode = $Script:PSCmdlet.ParameterSetName
				$Script:PackageSource = "AdminService"
			}
		}
	}
	
	function ConvertTo-ObfuscatedUserName {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Specify the user name string to be obfuscated for log output.")]
			[ValidateNotNullOrEmpty()]
			[string]$InputObject
		)
		# Convert input object to a character array
		$UserNameArray = $InputObject.ToCharArray()
		
		# Loop through each character obfuscate every second item, with exceptions of the @ character if present
		for ($i = 0; $i -lt $UserNameArray.Count; $i++) {
			if ($UserNameArray[$i] -notmatch "@") {
				if ($i % 2) {
					$UserNameArray[$i] = "*"
				}
			}
		}
		
		# Join character array and return value
		return -join @($UserNameArray)
	}
	
	function Test-AdminServiceData {
		# Validate correct value have been either set as a TS environment variable or passed as parameter input for service account user name used to authenticate against the AdminService
		if ([string]::IsNullOrEmpty($Script:UserName)) {
			switch ($PSCmdLet.ParameterSetName) {
				"Debug" {
					Write-CMLogEntry -Value " - Required service account user name could not be determined from parameter input" -Severity 3
					
					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}
				default {
					# Attempt to read TSEnvironment variable MDMUserName
					$Script:UserName = $TSEnvironment.Value("MDMUserName")
					if (-not ([string]::IsNullOrEmpty($Script:UserName))) {
						# Obfuscate user name
						$ObfuscatedUserName = ConvertTo-ObfuscatedUserName -InputObject $Script:UserName
						
						Write-CMLogEntry -Value " - Successfully read service account user name from TS environment variable 'MDMUserName': $($ObfuscatedUserName)" -Severity 1
					} else {
						Write-CMLogEntry -Value " - Required service account user name could not be determined from TS environment variable" -Severity 3
						
						# Throw terminating error
						$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
						$PSCmdlet.ThrowTerminatingError($ErrorRecord)
					}
				}
			}
		} else {
			# Obfuscate user name
			$ObfuscatedUserName = ConvertTo-ObfuscatedUserName -InputObject $Script:UserName
			
			Write-CMLogEntry -Value " - Successfully read service account user name from parameter input: $($ObfuscatedUserName)" -Severity 1
		}
		
		# Validate correct value have been either set as a TS environment variable or passed as parameter input for service account password used to authenticate against the AdminService
		if ([string]::IsNullOrEmpty($Script:Password)) {
			switch ($Script:PSCmdLet.ParameterSetName) {
				"Debug" {
					Write-CMLogEntry -Value " - Required service account password could not be determined from parameter input" -Severity 3
				}
				default {
					# Attempt to read TSEnvironment variable MDMPassword
					$Script:Password = $TSEnvironment.Value("MDMPassword")
					if (-not ([string]::IsNullOrEmpty($Script:Password))) {
						Write-CMLogEntry -Value " - Successfully read service account password from TS environment variable 'MDMPassword': ********" -Severity 1
					} else {
						Write-CMLogEntry -Value " - Required service account password could not be determined from TS environment variable" -Severity 3
						
						# Throw terminating error
						$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
						$PSCmdlet.ThrowTerminatingError($ErrorRecord)
					}
				}
			}
		} else {
			Write-CMLogEntry -Value " - Successfully read service account password from parameter input: ********" -Severity 1
		}
		
		# Validate that if determined AdminService endpoint type is external, that additional required TS environment variables are available
		if ($Script:AdminServiceEndpointType -like "External") {
			if ($Script:PSCmdLet.ParameterSetName -notlike "Debug") {
				# Attempt to read TSEnvironment variable MDMExternalEndpoint
				$Script:ExternalEndpoint = $TSEnvironment.Value("MDMExternalEndpoint")
				if (-not ([string]::IsNullOrEmpty($Script:ExternalEndpoint))) {
					Write-CMLogEntry -Value " - Successfully read external endpoint address for AdminService through CMG from TS environment variable 'MDMExternalEndpoint': $($Script:ExternalEndpoint)" -Severity 1
				} else {
					Write-CMLogEntry -Value " - Required external endpoint address for AdminService through CMG could not be determined from TS environment variable" -Severity 3
					
					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}
				
				# Attempt to read TSEnvironment variable MDMClientID
				$Script:ClientID = $TSEnvironment.Value("MDMClientID")
				if (-not ([string]::IsNullOrEmpty($Script:ClientID))) {
					Write-CMLogEntry -Value " - Successfully read client identification for AdminService through CMG from TS environment variable 'MDMClientID': $($Script:ClientID)" -Severity 1
				} else {
					Write-CMLogEntry -Value " - Required client identification for AdminService through CMG could not be determined from TS environment variable" -Severity 3
					
					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}
				
				# Attempt to read TSEnvironment variable MDMTenantName
				$Script:TenantName = $TSEnvironment.Value("MDMTenantName")
				if (-not ([string]::IsNullOrEmpty($Script:TenantName))) {
					Write-CMLogEntry -Value " - Successfully read client identification for AdminService through CMG from TS environment variable 'MDMTenantName': $($Script:TenantName)" -Severity 1
				} else {
					Write-CMLogEntry -Value " - Required client identification for AdminService through CMG could not be determined from TS environment variable" -Severity 3
					
					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}
				
				# Attempt to read TSEnvironment variable MDMResourceURL
				$Script:TenantResourceURL = $TSEnvironment.Value("MDMResourceURL")
				if (-not([string]::IsNullOrEmpty($Script:TenantResourceURL))) {
					Write-CMLogEntry -Value " - Successfully read resource URL from TS environment variable 'MDMResourceName': $($Script:TenantResourceURL)" -Severity 1
				}
				else {
					Write-CMLogEntry -Value " - Using standard resource URL value: https://ConfigMgrService" -Severity 2
					$Script:TenantResourceURL = "https://ConfigMgrService"
				}
			}
		}
	}
	
	function Get-AdminServiceEndpointType {
		switch ($Script:DeploymentMode) {
			"Debug" {
				$Script:AdminServiceEndpointType = "Internal"
			}
			default {
				Write-CMLogEntry -Value " - Attempting to determine AdminService endpoint type based on current active Management Point candidates and from ClientInfo class" -Severity 1
				
				# Determine active MP candidates and if 
				$ActiveMPCandidates = Get-WmiObject -Namespace "root\ccm\LocationServices" -Class "SMS_ActiveMPCandidate"
				$ActiveMPInternalCandidatesCount = ($ActiveMPCandidates | Where-Object {
						$PSItem.Type -like "Assigned"
					} | Measure-Object).Count
				$ActiveMPExternalCandidatesCount = ($ActiveMPCandidates | Where-Object {
						$PSItem.Type -like "Internet"
					} | Measure-Object).Count
				
				# Determine if ConfigMgr client has detected if the computer is currently on internet or intranet
				$CMClientInfo = Get-WmiObject -Namespace "root\ccm" -Class "ClientInfo"
				switch ($CMClientInfo.InInternet) {
					$true {
						if ($ActiveMPExternalCandidatesCount -ge 1) {
							$Script:AdminServiceEndpointType = "External"
						} else {
							Write-CMLogEntry -Value " - Detected as an Internet client but unable to determine External AdminService endpoint, bailing out" -Severity 3
							
							# Throw terminating error
							$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
							$PSCmdlet.ThrowTerminatingError($ErrorRecord)
						}
					}
					$false {
						if ($ActiveMPInternalCandidatesCount -ge 1) {
							$Script:AdminServiceEndpointType = "Internal"
						} else {
							Write-CMLogEntry -Value " - Detected as an Intranet client but unable to determine Internal AdminService endpoint, bailing out" -Severity 3
							
							# Throw terminating error
							$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
							$PSCmdlet.ThrowTerminatingError($ErrorRecord)
						}
					}
				}
			}
		}
		Write-CMLogEntry -Value " - Determined AdminService endpoint type as: $($AdminServiceEndpointType)" -Severity 1
	}
	
	function Set-AdminServiceEndpointURL {
		switch ($Script:AdminServiceEndpointType) {
			"Internal" {
				$Script:AdminServiceURL = "https://{0}/AdminService/wmi" -f $Endpoint
			}
			"External" {
				$Script:AdminServiceURL = "{0}/wmi" -f $ExternalEndpoint
			}
		}
		Write-CMLogEntry -Value " - Setting 'AdminServiceURL' variable to: $($Script:AdminServiceURL)" -Severity 1
	}
	
	function Install-AuthModule {
		# Determine if the PSIntuneAuth module needs to be installed
		try {
			Write-CMLogEntry -Value " - Attempting to locate PSIntuneAuth module" -Severity 1
			$PSIntuneAuthModule = Get-InstalledModule -Name "PSIntuneAuth" -ErrorAction Stop -Verbose:$false
			if ($PSIntuneAuthModule -ne $null) {
				Write-CMLogEntry -Value " - Authentication module detected, checking for latest version" -Severity 1
				$LatestModuleVersion = (Find-Module -Name "PSIntuneAuth" -ErrorAction SilentlyContinue -Verbose:$false).Version
				if ($LatestModuleVersion -gt $PSIntuneAuthModule.Version) {
					Write-CMLogEntry -Value " - Latest version of PSIntuneAuth module is not installed, attempting to install: $($LatestModuleVersion.ToString())" -Severity 1
					$UpdateModuleInvocation = Update-Module -Name "PSIntuneAuth" -Scope CurrentUser -Force -ErrorAction Stop -Confirm:$false -Verbose:$false
				}
			}
		} catch [System.Exception] {
			Write-CMLogEntry -Value " - Unable to detect PSIntuneAuth module, attempting to install from PSGallery" -Severity 2
			try {
				# Install NuGet package provider
				$PackageProvider = Install-PackageProvider -Name "NuGet" -Force -Verbose:$false
				
				# Install PSIntuneAuth module
				Install-Module -Name "PSIntuneAuth" -Scope AllUsers -Force -ErrorAction Stop -Confirm:$false -Verbose:$false
				Write-CMLogEntry -Value " - Successfully installed PSIntuneAuth module" -Severity 1
			} catch [System.Exception] {
				Write-CMLogEntry -Value " - An error occurred while attempting to install PSIntuneAuth module. Error message: $($_.Exception.Message)" -Severity 3
				
				# Throw terminating error
				$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
				$PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
		}
	}
	
	function Get-AuthToken {
		try {
			# Attempt to install PSIntuneAuth module, if already installed ensure the latest version is being used
			Install-AuthModule
					
			# Import MS Intune Auth Token
			Write-CMLogEntry -Value " - Importing PSIntuneAuth PS module" -Severity 1			
			Import-Module -Name PSIntuneAuth
			
			# Retrieve authentication token
			Write-CMLogEntry -Value " - Attempting to retrieve authentication token using native client with ID: $($ClientID)" -Severity 1
			$Script:AuthToken = Get-MSIntuneAuthToken -TenantName $TenantName -ClientID $ClientID -Credential $Credential -Resource $TenantResourceURL -RedirectUri "https://login.microsoftonline.com/common/oauth2/nativeclient" -ErrorAction Stop
			Write-CMLogEntry -Value " - Successfully retrieved authentication token" -Severity 1
		} catch [System.Exception] {
			Write-CMLogEntry -Value " - Failed to retrieve authentication token. Error message: $($PSItem.Exception.Message)" -Severity 3
			
			# Throw terminating error
			$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
			$PSCmdlet.ThrowTerminatingError($ErrorRecord)
		}
	}
	
	function Get-AuthCredential {
		# Construct PSCredential object for authentication
		$EncryptedPassword = ConvertTo-SecureString -String $Script:Password -AsPlainText -Force
		$Script:Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList @($Script:UserName, $EncryptedPassword)
	}
	
	function Get-AdminServiceItem {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Specify the resource for the AdminService API call, e.g. '/SMS_Package'.")]
			[ValidateNotNullOrEmpty()]
			[string]$Resource
		)
		# Construct array object to hold return value
		$PackageArray = New-Object -TypeName System.Collections.ArrayList
		
		switch ($Script:AdminServiceEndpointType) {
			"External" {
				try {
					$AdminServiceUri = $AdminServiceURL + $Resource
					Write-CMLogEntry -Value " - Calling AdminService endpoint with URI: $($AdminServiceUri)" -Severity 1
					$AdminServiceResponse = Invoke-RestMethod -Method Get -Uri $AdminServiceUri -Headers $AuthToken -ErrorAction Stop
				} catch [System.Exception] {
					Write-CMLogEntry -Value " - Failed to retrieve available package items from AdminService endpoint. Error message: $($PSItem.Exception.Message)" -Severity 3
					
					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}
			}
			"Internal" {
				$AdminServiceUri = $AdminServiceURL + $Resource
				Write-CMLogEntry -Value " - Calling AdminService endpoint with URI: $($AdminServiceUri)" -Severity 1
				
				try {
					# Call AdminService endpoint to retrieve package data
					$AdminServiceResponse = Invoke-RestMethod -Method Get -Uri $AdminServiceUri -Credential $Credential -ErrorAction Stop
				} catch [System.Security.Authentication.AuthenticationException] {
					Write-CMLogEntry -Value " - The remote AdminService endpoint certificate is invalid according to the validation procedure. Error message: $($PSItem.Exception.Message)" -Severity 2
					Write-CMLogEntry -Value " - Will attempt to set the current session to ignore self-signed certificates and retry AdminService endpoint connection" -Severity 2
					
					# Attempt to ignore self-signed certificate binding for AdminService
					# Convert encoded base64 string for ignore self-signed certificate validation functionality
					$CertificationValidationCallbackEncoded = "DQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAdQBzAGkAbgBnACAAUwB5AHMAdABlAG0AOwANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB1AHMAaQBuAGcAIABTAHkAcwB0AGUAbQAuAE4AZQB0ADsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAdQBzAGkAbgBnACAAUwB5AHMAdABlAG0ALgBOAGUAdAAuAFMAZQBjAHUAcgBpAHQAeQA7AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHUAcwBpAG4AZwAgAFMAeQBzAHQAZQBtAC4AUwBlAGMAdQByAGkAdAB5AC4AQwByAHkAcAB0AG8AZwByAGEAcABoAHkALgBYADUAMAA5AEMAZQByAHQAaQBmAGkAYwBhAHQAZQBzADsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAcAB1AGIAbABpAGMAIABjAGwAYQBzAHMAIABTAGUAcgB2AGUAcgBDAGUAcgB0AGkAZgBpAGMAYQB0AGUAVgBhAGwAaQBkAGEAdABpAG8AbgBDAGEAbABsAGIAYQBjAGsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAewANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHAAdQBiAGwAaQBjACAAcwB0AGEAdABpAGMAIAB2AG8AaQBkACAASQBnAG4AbwByAGUAKAApAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAewANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAaQBmACgAUwBlAHIAdgBpAGMAZQBQAG8AaQBuAHQATQBhAG4AYQBnAGUAcgAuAFMAZQByAHYAZQByAEMAZQByAHQAaQBmAGkAYwBhAHQAZQBWAGEAbABpAGQAYQB0AGkAbwBuAEMAYQBsAGwAYgBhAGMAawAgAD0APQBuAHUAbABsACkADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAUwBlAHIAdgBpAGMAZQBQAG8AaQBuAHQATQBhAG4AYQBnAGUAcgAuAFMAZQByAHYAZQByAEMAZQByAHQAaQBmAGkAYwBhAHQAZQBWAGEAbABpAGQAYQB0AGkAbwBuAEMAYQBsAGwAYgBhAGMAawAgACsAPQAgAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAZABlAGwAZQBnAGEAdABlAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAKAANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAATwBiAGoAZQBjAHQAIABvAGIAagAsACAADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAFgANQAwADkAQwBlAHIAdABpAGYAaQBjAGEAdABlACAAYwBlAHIAdABpAGYAaQBjAGEAdABlACwAIAANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAWAA1ADAAOQBDAGgAYQBpAG4AIABjAGgAYQBpAG4ALAAgAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIABTAHMAbABQAG8AbABpAGMAeQBFAHIAcgBvAHIAcwAgAGUAcgByAG8AcgBzAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAKQANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHIAZQB0AHUAcgBuACAAdAByAHUAZQA7AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAfQA7AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB9AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAfQANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB9AA0ACgAgACAAIAAgACAAIAAgACAA"
					$CertificationValidationCallback = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($CertificationValidationCallbackEncoded))
					
					# Load required type definition to be able to ignore self-signed certificate to circumvent issues with AdminService running with ConfigMgr self-signed certificate binding
					Add-Type -TypeDefinition $CertificationValidationCallback
					[ServerCertificateValidationCallback]::Ignore()
					
					try {
						# Call AdminService endpoint to retrieve package data
						$AdminServiceResponse = Invoke-RestMethod -Method Get -Uri $AdminServiceUri -Credential $Credential -ErrorAction Stop
					} catch [System.Exception] {
						Write-CMLogEntry -Value " - Failed to retrieve available package items from AdminService endpoint. Error message: $($PSItem.Exception.Message)" -Severity 3
						
						# Throw terminating error
						$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
						$PSCmdlet.ThrowTerminatingError($ErrorRecord)
					}
				} catch {
					Write-CMLogEntry -Value " - Failed to retrieve available package items from AdminService endpoint. Error message: $($PSItem.Exception.Message)" -Severity 3
					
					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}
			}
		}
		
		# Add returned driver package objects to array list
		if ($AdminServiceResponse.value -ne $null) {
			foreach ($Package in $AdminServiceResponse.value) {
				$PackageArray.Add($Package) | Out-Null
			}
		}
		
		# Handle return value
		return $PackageArray
	}
	
	function Get-BIOSPackages {
		try {
			# Retrieve BIOS packages but filter out matches depending on script operational mode
			switch ($OperationalMode) {
				"Production" {
					if ($Script:PSCmdlet.ParameterSetName -like "XMLPackage") {
						Write-CMLogEntry -Value " - Reading XML content logic file BIOS package entries" -Severity 1
						$Packages = (([xml]$(Get-Content -Path $XMLPackageLogicFile -Raw)).ArrayOfCMPackage).CMPackage | Where-Object {
							$_.Name -notmatch "Pilot" -and $_.Name -notmatch "Legacy" -and $_.Name -match $Filter
						}
					} else {
						Write-CMLogEntry -Value " - Querying AdminService for BIOS package instances" -Severity 1
						$Packages = Get-AdminServiceItem -Resource "/SMS_Package?`$filter=contains(Name,'$($Filter)')" | Where-Object {
							$_.Name -notmatch "Pilot" -and $_.Name -notmatch "Retired"
						}
					}
					
				}
				"Pilot" {
					if ($Script:PSCmdlet.ParameterSetName -like "XMLPackage") {
						Write-CMLogEntry -Value " - Reading XML content logic file BIOS package entries" -Severity 1
						$Packages = (([xml]$(Get-Content -Path $XMLPackageLogicFile -Raw)).ArrayOfCMPackage).CMPackage | Where-Object {
							$_.Name -match "Pilot" -and $_.Name -match $Filter
						}
					} else {
						Write-CMLogEntry -Value " - Querying AdminService for BIOS package instances" -Severity 1
						$Packages = Get-AdminServiceItem -Resource "/SMS_Package?`$filter=contains(Name,'$($Filter)')" | Where-Object {
							$_.Name -match "Pilot"
						}
					}
				}
			}
			
			# Handle return value
			if ($Packages -ne $null) {
				Write-CMLogEntry -Value " - Retrieved a total of '$(($Packages | Measure-Object).Count)' BIOS packages from $($Script:PackageSource) matching operational mode: $($OperationalMode)" -Severity 1
				return $Packages
			} else {
				Write-CMLogEntry -Value " - Retrieved a total of '0' BIOS packages from $($Script:PackageSource) matching operational mode: $($OperationalMode)" -Severity 3
				
				# Throw terminating error
				$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
				$PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
		} catch [System.Exception] {
			Write-CMLogEntry -Value " - An error occurred while calling $($Script:PackageSource) for a list of available BIOS packages. Error message: $($_.Exception.Message)" -Severity 3
			
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
				$ComputerDetails.Manufacturer = "HP"
				$ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
				$ComputerDetails.SystemSKU = (Get-CIMInstance -ClassName "MS_SystemInformation" -NameSpace "root\WMI").BaseBoardProduct.Trim()
			}
			"*Hewlett-Packard*" {
				$ComputerDetails.Manufacturer = "HP"
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
			"*AZW*" {
				$ComputerDetails.Manufacturer = "AZW"
				$ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
				$ComputerDetails.SystemSKU = (Get-CIMInstance -ClassName "MS_SystemInformation" -NameSpace root\WMI).BaseBoardProduct.Trim()
			}
			"*Fujitsu*" {
				$ComputerDetails.Manufacturer = "Fujitsu"
				$ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
				$ComputerDetails.SystemSKU = (Get-WmiObject -Class "Win32_BaseBoard" | Select-Object -ExpandProperty SKU).Trim()
			}
		}
		
		# Handle overriding computer details if debug mode and additional parameters was specified
		if ($Script:PSCmdlet.ParameterSetName -like "Debug") {
			if (-not ([string]::IsNullOrEmpty($Manufacturer))) {
				$ComputerDetails.Manufacturer = $Manufacturer
			}
			if (-not ([string]::IsNullOrEmpty($ComputerModel))) {
				$ComputerDetails.Model = $ComputerModel
			}
			if (-not ([string]::IsNullOrEmpty($SystemSKU))) {
				$ComputerDetails.SystemSKU = $SystemSKU
			}
		}
		
		# Handle output to log file for computer details
		Write-CMLogEntry -Value " - Computer manufacturer determined as: $($ComputerDetails.Manufacturer)" -Severity 1
		Write-CMLogEntry -Value " - Computer model determined as: $($ComputerDetails.Model)" -Severity 1
		
		# Handle output to log file for computer SystemSKU
		if (-not ([string]::IsNullOrEmpty($ComputerDetails.SystemSKU))) {
			Write-CMLogEntry -Value " - Computer SystemSKU determined as: $($ComputerDetails.SystemSKU)" -Severity 1
		} else {
			Write-CMLogEntry -Value " - Computer SystemSKU determined as: <null>" -Severity 2
		}
		
		# Handle output to log file for Fallback SKU
		if (-not ([string]::IsNullOrEmpty($ComputerDetails.FallBackSKU))) {
			Write-CMLogEntry -Value " - Computer Fallback SystemSKU determined as: $($ComputerDetails.FallBackSKU)" -Severity 1
		}
		
		# Handle return value from function
		return $ComputerDetails
	}
	
	function Get-ComputerSystemType {
		$ComputerSystemType = Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty "Model"
		if ($ComputerSystemType -notin @("Virtual Machine", "VMware Virtual Platform", "VirtualBox", "HVM domU", "KVM", "VMWare7,1")) {
			Write-CMLogEntry -Value " - Supported computer platform detected, script execution allowed to continue" -Severity 1
		} else {
			if ($Script:PSCmdlet.ParameterSetName -like "Debug") {
				Write-CMLogEntry -Value " - Unsupported computer platform detected, virtual machines are not supported but will be allowed in DebugMode" -Severity 2
			} else {
				Write-CMLogEntry -Value " - Unsupported computer platform detected, virtual machines are not supported" -Severity 3
				
				# Throw terminating error
				$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
				$PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
		}
	}
	
	function Test-ComputerDetails {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Specify the computer details object from Get-ComputerDetails function.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$InputObject
		)
		# Construct custom object for computer details validation
		$Script:ComputerDetection = [PSCustomObject]@{
			"ModelDetected" = $false
			"SystemSKUDetected" = $false
		}
		
		if (($InputObject.Model -ne $null) -and (-not ([System.String]::IsNullOrEmpty($InputObject.Model)))) {
			Write-CMLogEntry -Value " - Computer model detection was successful" -Severity 1
			$ComputerDetection.ModelDetected = $true
		}
		
		if (($InputObject.SystemSKU -ne $null) -and (-not ([System.String]::IsNullOrEmpty($InputObject.SystemSKU)))) {
			Write-CMLogEntry -Value " - Computer SystemSKU detection was successful" -Severity 1
			$ComputerDetection.SystemSKUDetected = $true
		}
		
		if (($ComputerDetection.ModelDetected -eq $false) -and ($ComputerDetection.SystemSKUDetected -eq $false)) {
			Write-CMLogEntry -Value " - Computer model and SystemSKU values are missing, script execution is not allowed since required values to continue could not be gathered" -Severity 3
			
			# Throw terminating error
			$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
			$PSCmdlet.ThrowTerminatingError($ErrorRecord)
		} else {
			Write-CMLogEntry -Value " - Computer details successfully verified" -Severity 1
		}
	}
	
	function Set-ComputerDetectionMethod {
		if ($ComputerDetection.SystemSKUDetected -eq $true) {
			Write-CMLogEntry -Value " - Determined primary computer detection method: SystemSKU" -Severity 1
			return "SystemSKU"
		} else {
			Write-CMLogEntry -Value " - Determined fallback computer detection method: ComputerModel" -Severity 1
			return "ComputerModel"
		}
	}
	
	function Compare-BIOSVersion {
		param (
			[parameter(Mandatory = $false, HelpMessage = "Current available BIOS version.")]
			[ValidateNotNullOrEmpty()]
			[string]$AvailableBIOSVersion,
			[parameter(Mandatory = $false, HelpMessage = "Current available BIOS revision date.")]
			[string]$AvailableBIOSReleaseDate,
			[parameter(Mandatory = $true, HelpMessage = "Current available BIOS version.")]
			[ValidateNotNullOrEmpty()]
			[string]$ComputerManufacturer
		)
		
		if ($ComputerManufacturer -match "Dell") {
			# Obtain current BIOS release
			$CurrentBIOSVersion = (Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty SMBIOSBIOSVersion).Trim()
			Write-CMLogEntry -Value "Current BIOS release detected as $($CurrentBIOSVersion)." -Severity 1
			Write-CMLogEntry -Value "Available BIOS release deteced as $($AvailableBIOSVersion)." -Severity 1
			
			# Determine Dell BIOS revision format			
			if ($CurrentBIOSVersion -like "*.*.*") {
				# Compare current BIOS release to available
				if ([System.Version]$AvailableBIOSVersion -gt [System.Version]$CurrentBIOSVersion) {
					# Write output to task sequence variable
					if ($Script:PSCmdlet.ParameterSetName -notlike "Debug") {
						$TSEnvironment.Value("NewBIOSAvailable") = $true
					}
					Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current release $($CurrentBIOSVersion) will be replaced by $($AvailableBIOSVersion)." -Severity 1
				}
			} elseif ($CurrentBIOSVersion -like "A*") {
				# Compare current BIOS release to available
				if ($AvailableBIOSVersion -like "*.*.*") {
					# Assume that the bios is new as moving from Axx to x.x.x formats
					# Write output to task sequence variable
					if ($Script:PSCmdlet.ParameterSetName -notlike "Debug") {
						$TSEnvironment.Value("NewBIOSAvailable") = $true
					}
					Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current release $($CurrentBIOSVersion) will be replaced by $($AvailableBIOSVersion)." -Severity 1
				} elseif ($AvailableBIOSVersion -gt $CurrentBIOSVersion) {
					# Write output to task sequence variable
					if ($Script:PSCmdlet.ParameterSetName -notlike "Debug") {
						$TSEnvironment.Value("NewBIOSAvailable") = $true
					}
					Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current release $($CurrentBIOSVersion) will be replaced by $($AvailableBIOSVersion)." -Severity 1
				}
			}
		}
		
		if ($ComputerManufacturer -match "Lenovo") {
			# Obtain current BIOS release
			$CurrentBIOSReleaseDate = ((Get-WmiObject -Class Win32_BIOS | Select-Object -Property *).ReleaseDate).SubString(0, 8)
			Write-CMLogEntry -Value "Current BIOS release date detected as $($CurrentBIOSReleaseDate)." -Severity 1
			Write-CMLogEntry -Value "Available BIOS release date detected as $($AvailableBIOSReleaseDate)." -Severity 1
			
			# Compare current BIOS release to available
			if ($AvailableBIOSReleaseDate -gt $CurrentBIOSReleaseDate) {
				# Write output to task sequence variable
				if ($Script:PSCmdlet.ParameterSetName -notlike "Debug") {
					$TSEnvironment.Value("NewBIOSAvailable") = $true
				}
				Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current date release dated $($CurrentBIOSReleaseDate) will be replaced by release $($AvailableBIOSReleaseDate)." -Severity 1
			}
		}
		
		if ($ComputerManufacturer -match "Hewlett-Packard|HP") {
			# Obtain current BIOS release
			$CurrentBIOSProperties = (Get-WmiObject -Class Win32_BIOS | Select-Object -Property *)
			
			# Update version formatting
			$AvailableBIOSVersion = $AvailableBIOSVersion.TrimEnd(".")
			$AvailableBIOSVersion = $AvailableBIOSVersion.Split(" ")[0]
			
			# Detect new versus old BIOS formats
			switch -wildcard ($($CurrentBIOSProperties.SMBIOSBIOSVersion)) {
				"*ver*" {
					if ($CurrentBIOSProperties.SMBIOSBIOSVersion -match '.F.\d+$') {
						$CurrentBIOSVersion = ($CurrentBIOSProperties.SMBIOSBIOSVersion -split "Ver.")[1].Trim()
						$BIOSVersionParseable = $false
					} else {
						$CurrentBIOSVersion = [System.Version]::Parse(($CurrentBIOSProperties.SMBIOSBIOSVersion).TrimStart($CurrentBIOSProperties.SMBIOSBIOSVersion.Split(".")[0]).TrimStart(".").Trim().Split(" ")[0])
						$BIOSVersionParseable = $true
					}
				}
				default {
					$CurrentBIOSVersion = "$($CurrentBIOSProperties.SystemBiosMajorVersion).$($CurrentBIOSProperties.SystemBiosMinorVersion)"
					$BIOSVersionParseable = $true
				}
			}
			
			# Output version details	
			Write-CMLogEntry -Value "Current BIOS release detected as $($CurrentBIOSVersion)." -Severity 1
			Write-CMLogEntry -Value "Available BIOS release detected as $($AvailableBIOSVersion)." -Severity 1
			
			# Compare current BIOS release to available
			switch ($BIOSVersionParseable) {
				$true {
					if ([System.Version]$AvailableBIOSVersion -gt [System.Version]$CurrentBIOSVersion) {
						# Write output to task sequence variable
						if ($Script:PSCmdlet.ParameterSetName -notlike "Debug") {
							$TSEnvironment.Value("NewBIOSAvailable") = $true
						}
						Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current release $($CurrentBIOSVersion) will be replaced by $($AvailableBIOSVersion)." -Severity 1
					}
				}
				$false {
					if ([System.Int32]::Parse($AvailableBIOSVersion.TrimStart("F.")) -gt [System.Int32]::Parse($CurrentBIOSVersion.TrimStart("F."))) {
						# Write output to task sequence variable
						if ($Script:PSCmdlet.ParameterSetName -notlike "Debug") {
							$TSEnvironment.Value("NewBIOSAvailable") = $true
						}
						Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current release $($CurrentBIOSVersion) will be replaced by $($AvailableBIOSVersion)." -Severity 1
					}
				}
			}
		}
	}
	
	function Get-BIOSUpdate {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Specify the computer details object from Get-ComputerDetails function.")]
			[ValidateNotNullOrEmpty()]
			[PSCustomObject]$InputObject
		)
		
		# Define machine matching values
		$ComputerSystemType = $InputObject.Model
		$ComputerManufacturer = $InputObject.Manufacturer
		$SystemSKU = $InputObject.SystemSKU
		
		# Supported manufacturers
		$Manufacturers = @("Dell", "Hewlett-Packard", "Lenovo", "Microsoft", "HP")
		
		$PackageList = New-Object -TypeName System.Collections.ArrayList
		
		if ($ComputerSystemType -notin @("Virtual Machine", "VMware Virtual Platform", "VirtualBox", "HVM domU", "KVM")) {
			# Process packages returned from web service
			if ($BIOSPackages -ne $null) {
				if (($ComputerModel -ne $null) -and (-not ([System.String]::IsNullOrEmpty($ComputerModel))) -or (($SystemSKU -ne $null) -and (-not ([System.String]::IsNullOrEmpty($SystemSKU))))) {
					# Determine computer model detection
					if ([System.String]::IsNullOrEmpty($SystemSKU)) {
						Write-CMLogEntry -Value "Attempting to find a match for BIOS package: $($Package.PackageName) ($($Package.PackageID))" -Severity 1
						Write-CMLogEntry -Value "Computer detection method set to use ComptuerModel" -Severity 1
						$ComputerDetectionMethod = "ComputerModel"
					} else {
						Write-CMLogEntry -Value "Attempting to find a match for BIOS package: $($Package.PackageName) ($($Package.PackageID))" -Severity 1
						Write-CMLogEntry -Value "Computer detection method set to use SystemSKU" -Severity 1
						$ComputerDetectionMethod = "SystemSKU"
					}
					
					# Add packages with matching criteria to list
					foreach ($Package in $BIOSPackages) {
						Write-CMLogEntry -Value "Attempting to find a match for BIOS package: $($Package.Name) ($($Package.PackageID)) $($Package.Version)" -Severity 1
						
						# Computer detection method matching
						$ComputerDetectionResult = $false
						switch ($ComputerManufacturer) {
							"Hewlett-Packard" {
								$PackageNameComputerModel = $Package.Name.Replace("Hewlett-Packard", "HP").Split("-").Trim()[1]
							}
							Default {
								$PackageNameComputerModel = $Package.Name.Split("-", 2).Replace($ComputerManufacturer, "").Trim()[1]
							}
						}
						
						switch ($ComputerDetectionMethod) {
							"ComputerModel" {
								if ($PackageNameComputerModel -like $ComputerModel) {
									Write-CMLogEntry -Value "Match found for computer model using detection method: $($ComputerDetectionMethod) ($($ComputerModel))" -Severity 1
									$ComputerDetectionResult = $true
								}
							}
							"SystemSKU" {
								if ($Package.Description -match $SystemSKU) {
									Write-CMLogEntry -Value "Match found for computer model using detection method: $($ComputerDetectionMethod) ($($SystemSKU))" -Severity 1
									$ComputerDetectionResult = $true
								} else {
									Write-CMLogEntry -Value "Unable to match computer model using detection method: $($ComputerDetectionMethod) ($($SystemSKU))" -Severity 2
									if ($PackageNameComputerModel -like $ComputerModel) {
										Write-CMLogEntry -Value "Fallback from SystemSKU match found for computer model instead using detection method: $($ComputerDetectionMethod) ($($ComputerModel))" -Severity 1
										$ComputerDetectionResult = $true
									}
								}
							}
						}
						
						if ($ComputerDetectionResult -eq $true) {
							# Match model, manufacturer criteria
							if ($Manufacturers -contains $ComputerManufacturer) {
								if ($ComputerManufacturer -match $Package.Manufacturer) {
									Write-CMLogEntry -Value "Match found for computer model and manufacturer: $($Package.Name) ($($Package.PackageID))" -Severity 1
									$PackageList.Add($Package) | Out-Null
								} else {
									Write-CMLogEntry -Value "Package does not meet computer model and manufacturer criteria: $($Package.PackageName) ($($Package.PackageID))" -Severity 2
								}
							}
						}
						
					}
					
					# Process matching items in package list and set task sequence variable
					if ($PackageList.Count -ge 1) {
						Write-CMLogEntry -Value "[BIOSValidation]: Starting BIOS package validation phase" -Severity 1
						# Determine the most current package from list
						if ($PackageList.Count -eq 1) {
							Write-CMLogEntry -Value "BIOS package list contains a single match, attempting to set task sequence variable" -Severity 1
							
							# Check if BIOS package is newer than currently installed
							if ($ComputerManufacturer -match "Dell") {
								Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].Version -ComputerManufacturer $ComputerManufacturer
							} elseif ($ComputerManufacturer -match "Lenovo") {
								Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].Version -AvailableBIOSReleaseDate $(($PackageList[0].Description).Split(":")[2].Trimend(")")) -ComputerManufacturer $ComputerManufacturer
							} elseif ($ComputerManufacturer -match "Hewlett-Packard|HP") {
								Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].Version -ComputerManufacturer $ComputerManufacturer
							} elseif ($ComputerManufacturer -match "Microsoft") {
								$NewBIOSAvailable = $true
							}
							
							if ($Script:PSCmdlet.ParameterSetName -notlike "Debug") {
								if ($TSEnvironment.Value("NewBIOSAvailable") -eq $true) {
									# Attempt to download BIOS package content
									$DownloadInvocation = Invoke-CMDownloadContent -PackageID $($PackageList[0].PackageID) -DestinationLocationType Custom -DestinationVariableName "OSDBIOSPackage" -CustomLocationPath "%_SMSTSMDataPath%\BIOSPackage"
									try {
										# Check for successful package download
										if ($DownloadInvocation -eq 0) {
											Write-CMLogEntry -Value "BIOS update package content downloaded successfully. Update located in: $($TSEnvironment.Value('OSDBIOSPackage01'))" -Severity 1
											Write-CMLogEntry -Value "[BIOSPackageDownload]: Completed BIOS package download phase" -Severity 1
										} else {
											Write-CMLogEntry -Value "BIOS update package content download process returned an unhandled exit code: $($DownloadInvocation)" -Severity 3; exit 13
										}
									} catch [System.Exception] {
										Write-CMLogEntry -Value "An error occurred while downloading the BIOS update (single package match). Error message: $($_.Exception.Message)" -Severity 3; exit 14
									}
								} else {
									Write-CMLogEntry -Value "BIOS is already up to date with the latest $($PackageList[0].PackageVersion) version" -Severity 1
								}
							} else {
								Write-CMLogEntry -Value "Task sequence engine would have been instructed to download package ID $($PackageList[0].PackageID) to %_SMSTSMDataPath%\BIOSPackage" -Severity 1
							}
							
						} elseif ($PackageList.Count -ge 2) {
							Write-CMLogEntry -Value "BIOS package list contains multiple matches, attempting to set task sequence variable" -Severity 1
							
							# Determine the latest BIOS package by creation date
							if ($ComputerManufacturer -match "Dell") {
								$PackageList = $PackageList | Sort-Object -Property SourceDate -Descending | Select-Object -First 1
							} elseif ($ComputerManufacturer -eq "Lenovo") {
								$ComputerDescription = Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version
								# Attempt to find exact model match for Lenovo models which overlap model types
								$PackageList = $PackageList | Where-object {
									($_.Name -like "*$ComputerDescription") -and ($_.Manufacturer -match $ComputerManufacturer)
								} | Sort-object -Property SourceDate -Descending | Select-Object -First 1
								
								If ($PackageList -eq $null) {
									# Fall back to select the latest model type match if no model name match is found
									$PackageList = $PackageList | Sort-object -Property SourceDate -Descending | Select-Object -First 1
								}
							} elseif ($ComputerManufacturer -match "Hewlett-Packard|HP") {
								# Determine the latest BIOS package by creation date
								$PackageList = $PackageList | Sort-Object -Property PackageCreated -Descending | Select-Object -First 1
							} elseif ($ComputerManufacturer -match "Microsoft") {
								$PackageList = $PackageList | Sort-Object -Property PackageCreated -Descending | Select-Object -First 1
							}
							if ($PackageList.Count -eq 1) {
								# Check if BIOS package is newer than currently installed
								if ($ComputerManufacturer -match "Dell") {
									Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].Version -ComputerManufacturer $ComputerManufacturer
								} elseif ($ComputerManufacturer -match "Lenovo") {
									Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].Version -AvailableBIOSReleaseDate $(($PackageList[0].PackageDescription).Split(":")[2]).Trimend(")") -ComputerManufacturer $ComputerManufacturer
								} elseif ($ComputerManufacturer -match "Hewlett-Packard|HP") {
									Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].Version -ComputerManufacturer $ComputerManufacturer
								} elseif ($ComputerManufacturer -match "Microsoft") {
									$NewBIOSAvailable = $true
								}
								
								if ($Script:PSCmdlet.ParameterSetName -notlike "Debug") {
									if ($TSEnvironment.Value("NewBIOSAvailable") -eq $true) {
										$DownloadInvocation = Invoke-CMDownloadContent -PackageID $($PackageList[0].PackageID) -DestinationLocationType Custom -DestinationVariableName "OSDBIOSPackage" -CustomLocationPath "%_SMSTSMDataPath%\BIOSPackage"
										
										try {
											# Check for successful package download
											if ($DownloadInvocation -eq 0) {
												Write-CMLogEntry -Value "BIOS update package content downloaded successfully. Package located in: $($TSEnvironment.Value('OSDBIOSPackage01'))" -Severity 1
											} else {
												Write-CMLogEntry -Value "BIOS package content download process returned an unhandled exit code: $($DownloadInvocation)" -Severity 3; exit 13
											}
										} catch [System.Exception] {
											Write-CMLogEntry -Value "An error occurred while applying BIOS (multiple package match). Error message: $($_.Exception.Message)" -Severity 3; exit 15
										}
									} else {
										Write-CMLogEntry -Value "BIOS is already up to date with the latest $($PackageList[0].Version) version" -Severity 1
									}
								} else {
									Write-CMLogEntry -Value "Task sequence engine would have been instructed to download package ID $($PackageList[0].PackageID) to %_SMSTSMDataPath%\BIOSPackage" -Severity 1
								}
							} else {
								Write-CMLogEntry -Value "Unable to determine a matching BIOS package from list since an unsupported count was returned from package list, bailing out" -Severity 2; exit 1
							}
						} else {
							Write-CMLogEntry -Value "Empty BIOS package list detected, bailing out" -Severity 1
						}
					} else {
						Write-CMLogEntry -Value "BIOS package list returned from web service did not contain any objects matching the computer model and manufacturer, bailing out" -Severity 1
					}
				} else {
					Write-CMLogEntry -Value "This script is supported on Dell, Lenovo and HP systems only at this point, bailing out" -Severity 1
				}
			}
		}
	}
	
	Write-CMLogEntry -Value "[ApplyBIOSPackage]: Apply BIOS Package process initiated" -Severity 1
	if ($PSCmdLet.ParameterSetName -like "Debug") {
		Write-CMLogEntry -Value " - Apply BIOS package process initiated in debug mode" -Severity 1
	}
	Write-CMLogEntry -Value " - Apply BIOS package deployment type: $($PSCmdLet.ParameterSetName)" -Severity 1
	Write-CMLogEntry -Value " - Apply BIOS package operational mode: $($OperationalMode)" -Severity 1
	
	# Set script error preference variable
	$ErrorActionPreference = "Stop"
	
	try {
		# Set Security Protocol (TLS) 
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		
		Write-CMLogEntry -Value "[PrerequisiteChecker]: Starting environment prerequisite checker" -Severity 1
		
		# Determine the deployment type mode for driver package installation
		Get-DeploymentType
		
		# Determine if running on supported computer system type
		Get-ComputerSystemType
		
		# Determine computer manufacturer, model, SystemSKU and FallbackSKU
		$ComputerData = Get-ComputerData
		
		# Validate required computer details have successfully been gathered from WMI
		Test-ComputerDetails -InputObject $ComputerData
		
		# Determine the computer detection method to be used for matching against driver packages
		$ComputerDetectionMethod = Set-ComputerDetectionMethod
		
		Write-CMLogEntry -Value "[PrerequisiteChecker]: Completed environment prerequisite checker" -Severity 1
		
		if ($Script:PSCmdLet.ParameterSetName -notlike "XMLPackage") {
			Write-CMLogEntry -Value "[AdminService]: Starting AdminService endpoint phase" -Severity 1
			
			# Detect AdminService endpoint type
			Write-CMLogEntry -Value "- Detecting AdminService endpoint type" -Severity 1
			Get-AdminServiceEndpointType
			
			# Determine if required values to connect to AdminService are provided
			Test-AdminServiceData
			
			# Determine the AdminService endpoint URL based on endpoint type
			Write-CMLogEntry -Value "- Detecting AdminService URL" -Severity 1
			Set-AdminServiceEndpointURL
			
			# Construct PSCredential object for AdminService authentication, this is required for both endpoint types
			Write-CMLogEntry -Value "- Constructing AdminService authentication" -Severity 1
			Get-AuthCredential
			
			# Attempt to retrieve an authentication token for external AdminService endpoint connectivity
			# This will only execute when the endpoint type has been detected as External, which means that authentication is needed against the Cloud Management Gateway
			if ($Script:AdminServiceEndpointType -like "External") {
				Get-AuthToken
			}
			
			Write-CMLogEntry -Value "[AdminService]: Completed AdminService endpoint phase" -Severity 1
		}
		Write-CMLogEntry -Value "[BIOSPackage]: Starting BIOS package retrieval using method: $($Script:PackageSource)" -Severity 1
		
		# Retrieve available BIOS packages from admin service
		$BIOSPackages = Get-BIOSPackages
		
		# Get existing BIOS version
		$CurrentBIOSVersion = (Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty SMBIOSBIOSVersion).Trim()
		Write-CMLogEntry -Value "Current BIOS version determined as: $($CurrentBIOSVersion)" -Severity 1
		$ComputerData = $ComputerData | Select-Object -first 1
		
		# Determine if a newer BIOS release is available
		Get-BIOSUpdate -InputObject $ComputerData
		Write-CMLogEntry -Value "[BIOSPackage]: Completed BIOS package matching phase" -Severity 1
		Write-CMLogEntry -Value "[BIOSPackageValidation]: Completed BIOS package validation phase" -Severity 1
		
	} catch [System.Exception] {
		Write-CMLogEntry -Value "[BIOSPackage]: BIOS detection process failed, please refer to previous error or warning messages" -Severity 3
		
		# Main try-catch block was triggered, this should cause the script to fail with exit code 1
		exit 1
	}
}
End {
	if ($PSCmdLet.ParameterSetName -notlike "Debug") {
		# Reset OSDDownloadContent.exe dependant variables for further use of the task sequence step
		Invoke-CMResetDownloadContentVariables
	}
	
	# Write final output to log file
	Write-CMLogEntry -Value "[ApplyBIOSPackage]: Completed Apply BIOS Package process" -Severity 1
}
