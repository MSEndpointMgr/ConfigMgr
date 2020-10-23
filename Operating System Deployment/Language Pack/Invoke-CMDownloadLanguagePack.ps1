<#
.SYNOPSIS
    Detect and download Language Pack package matching a specific Windows 10 version.

.DESCRIPTION
    This script will detect current installed Language Packs, query the specified endpoint for ConfigMgr WebService for a list of Packages and download
    these packages matching a specific Windows 10 version.

.PARAMETER BuildNumber
    Specify build number, e.g. 14393, for the Windows version being upgraded to.

.PARAMETER OSArchitecture
    Specify architecture of the Windows version being upgraded to.

.PARAMETER Filter
	Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.

.PARAMETER PreCachePath
	Specify a custom path for the PreCache directory, overriding the default CCMCache directory.

.EXAMPLE
    .\Invoke-CMDownloadLanguagePack.ps1 -BuildNumber ‘18363’ -OSArchitecture ‘x64’ -Filter ‘Language Pack’ -PreCachePath "C:\Windows\Temp\LanguagePack"
    
.NOTES
    FileName:    Invoke-CMDownloadLanguagePack.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-07-22
    Updated:     2020-10-23
    
    Version history:
    1.0.0 - (2017-07-22) Script created
    1.0.1 - (2017-10-08) - Added functionality to download the detected language packs
    1.0.2 - (2017-11-08) - Fixed a bug when validating the param value for PackageID
    1.0.3 - (2019-02-14) - Added capability to set OSDSetupAdditionalUpgradeOptions with required value for configuring setup.exe to install language packs from download location
    2.0.0 - (2020-10-23) - IMPORTANT: From this version and onwards, usage of the ConfigMgr WebService has been deprecated. This version will only work with the built-in AdminService in ConfigMgr.
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Execute")]
param(
    [parameter(Mandatory=$true, HelpMessage="Specify build number, e.g. 14393, for the Windows version being upgraded to.")]
    [ValidateNotNullOrEmpty()]
    [string]$BuildNumber,

    [parameter(Mandatory=$true, HelpMessage="Specify architecture of the Windows version being upgraded to.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("x64", "x86")]
    [string]$OSArchitecture, 

    [parameter(Mandatory=$false, HelpMessage="Define a filter used when calling ConfigMgr AdminService to only return objects matching the filter.")]
    [ValidateNotNullOrEmpty()]
	[string]$Filter = [System.String]::Empty,
	
	[parameter(Mandatory = $false, ParameterSetName = "PreCache", HelpMessage = "Specify a custom path for the PreCache directory, overriding the default CCMCache directory.")]
	[ValidateNotNullOrEmpty()]
	[string]$PreCachePath
)
Begin {
    # Load Microsoft.SMS.TSEnvironment COM object
    try {
        $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 1
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
		    [string]$FileName = "LanguagePackDownload.log"
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
        $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""LanguagePackDownload"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
	
	    # Add value to log file
        try {
            Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to append log entry to LanguagePackDownload.log file. Error message: $($_.Exception.Message)"
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
			FilePath	 = $FilePath
			NoNewWindow  = $true
			Passthru	 = $true
			ErrorAction  = "Stop"
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
        $TsEnvironment.Value("SMSDownloadLangPackID") = "$($PackageID)"

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
        
        # Set SMSTSDownloadRetryCount to 1000 to overcome potential BranchCache issue that will cause 'SendWinHttpRequest failed. 80072efe'
        $TSEnvironment.Value("SMSTSDownloadRetryCount") = 1000
        


		# Invoke download of package content
		try {
			Write-CMLogEntry -Value "Starting package content download process, this might take some time" -Severity 1
            $ReturnCode = Invoke-Executable -FilePath (Join-Path -Path $env:windir -ChildPath "CCM\OSDDownloadContent.exe")

			# Match on return code
			if ($ReturnCode -eq 0) {
				Write-CMLogEntry -Value "Successfully downloaded package content with PackageID: $($PackageID)" -Severity 1
			}
			else {
                Write-CMLogEntry -Value "Package content download process failed with return code $($ReturnCode)" -Severity 2
                # Throw terminating error
				$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
				$PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
		}
		catch [System.Exception] {
            Write-CMLogEntry -Value "An error occurred while attempting to download package content. Error message: $($_.Exception.Message)" -Severity 3 ; exit 1
            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
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

    function New-TerminatingErrorRecord {
        param(
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

    function ConvertTo-ObfuscatedUserName {
		param(
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
		return -join@($UserNameArray)
	}

	function Test-AdminServiceData {
		# Validate correct value have been either set as a TS environment variable or passed as parameter input for service account user name used to authenticate against the AdminService
		if ([string]::IsNullOrEmpty($Script:UserName)) {
					# Attempt to read TSEnvironment variable LPMUserName
					$Script:UserName = $TSEnvironment.Value("LPMUserName")
					if (-not([string]::IsNullOrEmpty($Script:UserName))) {
						# Obfuscate user name
						$ObfuscatedUserName = ConvertTo-ObfuscatedUserName -InputObject $Script:UserName

						Write-CMLogEntry -Value " - Successfully read service account user name from TS environment variable 'LPMUserName': $($ObfuscatedUserName)" -Severity 1
					}
					else {
						Write-CMLogEntry -Value " - Required service account user name could not be determined from TS environment variable" -Severity 3

						# Throw terminating error
						$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
						$PSCmdlet.ThrowTerminatingError($ErrorRecord)
					}
		}
		else {
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
					# Attempt to read TSEnvironment variable LPMPassword
					$Script:Password = $TSEnvironment.Value("LPMPassword")
					if (-not([string]::IsNullOrEmpty($Script:Password))) {
						Write-CMLogEntry -Value " - Successfully read service account password from TS environment variable 'LPMPassword': ********" -Severity 1
					}
					else {
						Write-CMLogEntry -Value " - Required service account password could not be determined from TS environment variable" -Severity 3

						# Throw terminating error
						$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
						$PSCmdlet.ThrowTerminatingError($ErrorRecord)
					}
				}
			}
		}
		else {
			Write-CMLogEntry -Value " - Successfully read service account password from parameter input: ********" -Severity 1
		}

		# Validate that if determined AdminService endpoint type is external, that additional required TS environment variables are available
		if ($Script:AdminServiceEndpointType -like "External") {
			if ($Script:PSCmdLet.ParameterSetName -notlike "Debug") {
				# Attempt to read TSEnvironment variable LPMExternalEndpoint
				$Script:ExternalEndpoint = $TSEnvironment.Value("LPMExternalEndpoint")
				if (-not([string]::IsNullOrEmpty($Script:ExternalEndpoint))) {
					Write-CMLogEntry -Value " - Successfully read external endpoint address for AdminService through CMG from TS environment variable 'LPMExternalEndpoint': $($Script:ExternalEndpoint)" -Severity 1
				}
				else {
					Write-CMLogEntry -Value " - Required external endpoint address for AdminService through CMG could not be determined from TS environment variable" -Severity 3

					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}

				# Attempt to read TSEnvironment variable LPMClientID
				$Script:ClientID = $TSEnvironment.Value("LPMClientID")
				if (-not([string]::IsNullOrEmpty($Script:ClientID))) {
					Write-CMLogEntry -Value " - Successfully read client identification for AdminService through CMG from TS environment variable 'LPMClientID': $($Script:ClientID)" -Severity 1
				}
				else {
					Write-CMLogEntry -Value " - Required client identification for AdminService through CMG could not be determined from TS environment variable" -Severity 3

					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}

				# Attempt to read TSEnvironment variable LPMTenantName
				$Script:TenantName = $TSEnvironment.Value("LPMTenantName")
				if (-not([string]::IsNullOrEmpty($Script:TenantName))) {
					Write-CMLogEntry -Value " - Successfully read client identification for AdminService through CMG from TS environment variable 'LPMTenantName': $($Script:TenantName)" -Severity 1
				}
				else {
					Write-CMLogEntry -Value " - Required client identification for AdminService through CMG could not be determined from TS environment variable" -Severity 3

					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}
			}			
		}
	}

	function Get-AdminServiceEndpointType {
		Write-CMLogEntry -Value " - Attempting to determine AdminService endpoint type based on current active Management Point candidates and from ClientInfo class" -Severity 1

		# Determine active MP candidates and if 
		$ActiveMPCandidates = Get-WmiObject -Namespace "root\ccm\LocationServices" -Class "SMS_ActiveMPCandidate"
		$ActiveMPInternalCandidatesCount = ($ActiveMPCandidates | Where-Object { $PSItem.Type -like "Assigned" } | Measure-Object).Count
		$ActiveMPExternalCandidatesCount = ($ActiveMPCandidates | Where-Object { $PSItem.Type -like "Internet" } | Measure-Object).Count

		# Determine if ConfigMgr client has detected if the computer is currently on internet or intranet
		$CMClientInfo = Get-WmiObject -Namespace "root\ccm" -Class "ClientInfo"
			switch ($CMClientInfo.InInternet) {
				$true {
					if ($ActiveMPExternalCandidatesCount -ge 1) {
						$Script:AdminServiceEndpointType = "External"
					} 
					else {
						Write-CMLogEntry -Value " - Detected as an Internet client but unable to determine External AdminService endpoint, bailing out" -Severity 3
			
						# Throw terminating error
						$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
						$PSCmdlet.ThrowTerminatingError($ErrorRecord)
					}
				}
				$false {
					if ($ActiveMPInternalCandidatesCount -ge 1) {
						$Script:AdminServiceEndpointType = "Internal"
					}
					else {
						Write-CMLogEntry -Value " - Detected as an Intranet client but unable to determine Internal AdminService endpoint, bailing out" -Severity 3
			
						# Throw terminating error
						$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
						$PSCmdlet.ThrowTerminatingError($ErrorRecord)
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
		}
		catch [System.Exception] {
			Write-CMLogEntry -Value " - Unable to detect PSIntuneAuth module, attempting to install from PSGallery" -Severity 2
			try {
				#Force TLS1.2
				Write-CMLogEntry -Value " - Setting security protocol to TLS1.2" -Severity 1
				[Net.servicepointmanager]::securityprotocol = [Net.securityProtocolType]::Tls12

				# Install NuGet package provider
				$PackageProvider = Install-PackageProvider -Name "NuGet" -Force -Verbose:$false
	
				# Install PSIntuneAuth module
				Install-Module -Name "PSIntuneAuth" -Scope AllUsers -Force -ErrorAction Stop -Confirm:$false -Verbose:$false
				Write-CMLogEntry -Value " - Successfully installed PSIntuneAuth module" -Severity 1
			}
			catch [System.Exception] {
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

			# Retrieve authentication token
			Write-CMLogEntry -Value " - Attempting to retrieve authentication token using native client with ID: $($ClientID)" -Severity 1
			$Script:AuthToken = Get-MSIntuneAuthToken -TenantName $TenantName -ClientID $ClientID -Credential $Credential -Resource "https://ConfigMgrService" -RedirectUri "https://login.microsoftonline.com/common/oauth2/nativeclient" -ErrorAction Stop
			Write-CMLogEntry -Value " - Successfully retrieved authentication token" -Severity 1
		}
		catch [System.Exception] {
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
		param(
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
				}
				catch [System.Exception] {
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
				}
				catch [System.Security.Authentication.AuthenticationException] {
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
					}
					catch [System.Exception] {
						Write-CMLogEntry -Value " - Failed to retrieve available package items from AdminService endpoint. Error message: $($PSItem.Exception.Message)" -Severity 3

						# Throw terminating error
						$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
						$PSCmdlet.ThrowTerminatingError($ErrorRecord)
					}
				}
				catch {
					Write-CMLogEntry -Value " - Failed to retrieve available package items from AdminService endpoint. Error message: $($PSItem.Exception.Message)" -Severity 3

					# Throw terminating error
					$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
					$PSCmdlet.ThrowTerminatingError($ErrorRecord)
				}
			}
		}

		# Add returned languagepack objects to array list
		if ($AdminServiceResponse.value -ne $null) {
			foreach ($Package in $AdminServiceResponse.value) {
				$PackageArray.Add($Package) | Out-Null
			}
		}

		# Handle return value
		return $PackageArray
    }
    
    function Invoke-DownloadLanguagePackContent {
		Write-CMLogEntry -Value " - Attempting to download content files for matched language package: $($PackageList[0].Name)" -Severity 1

		# Depending on current deployment type, attempt to download language pack content
		switch ($Script:PSCmdlet.ParameterSetName) {
			"PreCache" {
				if ($Script:PSBoundParameters["PreCachePath"]) {
					if (-not(Test-Path -Path $Script:PreCachePath)) {
						Write-CMLogEntry -Value " - Attempting to create PreCachePath directory, as it doesn't exist: $($Script:PreCachePath)" -Severity 1
						
						try {
							New-Item -Path $PreCachePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
						}
						catch [System.Exception] {
							Write-CMLogEntry -Value " - Failed to create PreCachePath directory '$($Script:PreCachePath)'. Error message: $($_.Exception.Message)" -Severity 3
							
							# Throw terminating error
							$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
							$PSCmdlet.ThrowTerminatingError($ErrorRecord)
						}
					}

					if (Test-Path -Path $Script:PreCachePath) {
						$DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageList[0].PackageID -DestinationLocationType "Custom" -DestinationVariableName "OSDLanguagePack" -CustomLocationPath "$($Script:PreCachePath)"
					}
				}
				else {
					$DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageList[0].PackageID -DestinationLocationType "CCMCache" -DestinationVariableName "OSDLanguagePack"
				}
			}
			default {
				$DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageList[0].PackageID -DestinationLocationType "Custom" -DestinationVariableName "OSDLanguagePack" -CustomLocationPath "%_SMSTSMDataPath%\LanguagePack"
			}
		}

		# If download process was successful, meaning exit code from above function was 0, return the download location path
		if ($DownloadInvocation -eq 0) {
			$LanguagePackContentLocation = $TSEnvironment.Value("OSDLanguagePack01")
			Write-CMLogEntry -Value " - LanguagePack content files was successfully downloaded to: $($LanguagePackContentLocation)" -Severity 1

			# Handle return value for successful download of languagepack content files
			return $LanguagePackContentLocation
		}
		else {
			Write-CMLogEntry -Value " - LanguagePack content download process returned an unhandled exit code: $($DownloadInvocation)" -Severity 3

			# Throw terminating error
			$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
			$PSCmdlet.ThrowTerminatingError($ErrorRecord)
		}
    }

    function Get-LanguagePack {
        try {
            # Retrieve languagepacks but filter out matches depending on script operational mode
				Write-CMLogEntry -Value " - Querying AdminService for languagepacks instances" -Severity 1
				$Packages = Get-AdminServiceItem -Resource "/SMS_Package?`$filter=contains(Name,'$($Filter)')" | Where-Object {$_.Name -notmatch "Retired"}

		
			# Handle return value
			if ($Packages -ne $null) {
				Write-CMLogEntry -Value " - Retrieved a total of '$(($Packages | Measure-Object).Count)' languagepacks from $($Script:PackageSource) matching operational mode: $($OperationalMode)" -Severity 1
				return $Packages
			}
			else {
				Write-CMLogEntry -Value " - Retrieved a total of '0' languagepacks from $($Script:PackageSource) matching operational mode: $($OperationalMode)" -Severity 3

				# Throw terminating error
				$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
				$PSCmdlet.ThrowTerminatingError($ErrorRecord)
			}
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - An error occurred while calling $($Script:PackageSource) for a list of available languagepacks. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }        
	}
    
    # Write log file for script execution
    Write-CMLogEntry -Value "Language Pack download process initiated" -Severity 1

    # Determine currently installed language packs and system culture
    $DefaultSystemCulture = [CultureInfo]::InstalledUICulture | Select-Object -ExpandProperty Name
    Write-CMLogEntry -Value "Installed UI culture detected: $($DefaultSystemCulture)" -Severity 1
    $CurrentLanguagePacks = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty MUILanguages
    Write-CMLogEntry -Value "Current language packs installed including installed UI culture: $($CurrentLanguagePacks -join ", ")" -Severity 1


    # Detect whether script should continue if more than 1 language pack is installed
    if (($CurrentLanguagePacks | Measure-Object).Count -ge 2) {
        Write-CMLogEntry -Value "[AdminService]: Starting AdminService endpoint phase" -Severity 1

        # Detect AdminService endpoint type
        Get-AdminServiceEndpointType

        # Determine if required values to connect to AdminService are provided
        Test-AdminServiceData

        # Determine the AdminService endpoint URL based on endpoint type
        Set-AdminServiceEndpointURL

        # Construct PSCredential object for AdminService authentication, this is required for both endpoint types
        Get-AuthCredential

        # Attempt to retrieve an authentication token for external AdminService endpoint connectivity
        # This will only execute when the endpoint type has been detected as External, which means that authentication is needed against the Cloud Management Gateway
        if ($Script:AdminServiceEndpointType -like "External") {
            Get-AuthToken
        }

        Write-CMLogEntry -Value "[AdminService]: Completed AdminService endpoint phase" -Severity 1

        Write-CMLogEntry -Value "[LanguagePack]: Starting languagepack retrieval using method: $($Script:PackageSource)" -Severity 1

        # Retrieve available languagepack from web service
		$LanguagePacks = Get-LanguagePack

        # Construct array list for matching packages
        $PackageList = New-Object -TypeName System.Collections.ArrayList

        # Determine packages matching operating system build number and architecture specified as in-parameters for the currently installed language packs
        if ($LanguagePacks -ne $null) {
            foreach ($Package in $LanguagePacks) {
				Write-CMLogEntry -Value "Processing : $($Package.Name) - $($Package.Language) -  $($Package.Version)" -Severity 1

                if ($Package.Name -match ($OSArchitecture) -and ($Package.Version -like $BuildNumber) -and ($Package.Language -in $CurrentLanguagePacks) -and ($Package.Language -notlike $DefaultSystemCulture)) {
                    $PackageList.Add($Package) | Out-Null
                    Write-CMLogEntry -Value "Found matching language pack: $($Package.Name)" -Severity 1
                }
            }
        }
        else {
            Write-CMLogEntry -Value "Language pack list returned from web service did not contain any matching objects" -Severity 2
        }

        # Process matching items in package list and set task sequence variable
        if ($PackageList -ne $null) {
            # Build package id list for task sequence variable
			#$PackageIDs = $PackageList.PackageID -join ","
			#Write-CMLogEntry -Value "Selected language packages: $PackageIDs" -Severity 1

            # Attempt to download language pack package content
            Write-CMLogEntry -Value "Attempting to download language pack package content" -Severity 1
            $sCacheFolder = $TSEnvironment.Value("LOCALLANGPACKPATH")
			Remove-Item $sCacheFolder -Force  -Recurse -ErrorAction SilentlyContinue
			Write-CMLogEntry -Value "[LanguagePackkDownload]: Starting Language Pack download phase" -Severity 1

			# Attempt to download the matched driver package content files from distribution point
			$LanguagePackContentLocation = Invoke-DownloadLanguagePackContent

			Write-CMLogEntry -Value "[LanguagePackkDownload]: Completed Language Pack download phase" -Severity 1
            #$DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageList[0].PackageID -DestinationLocationType Custom -DestinationVariableName "OSDLanguagePack" -CustomLocationPath "$sCacheFolder"
        }
        else {
            Write-CMLogEntry -Value "Empty language pack list detected, bailing out" -Severity 1
        }
    }
    else {
        Write-CMLogEntry -Value "Current Windows installation only contains a single language, no need to download addition language packs" -Severity 1
    }
}
End {
	# Reset OSDDownloadContent.exe dependant variables for further use of the task sequence step
    Invoke-CMResetDownloadContentVariables
}
