<#
.SYNOPSIS
    Detect and download Language Pack package matching a specific Windows 10 version.

.DESCRIPTION
    This script will detect current installed Language Packs, query the specified endpoint for ConfigMgr WebService for a list of Packages and download
    these packages matching a specific Windows 10 version.

.PARAMETER URI
    Set the URI for the ConfigMgr WebService.

.PARAMETER SecretKey
    Specify the known secret key for the ConfigMgr WebService.

.PARAMETER BuildNumber
    Specify build number, e.g. 14393, for the Windows version being upgraded to.

.PARAMETER OSArchitecture
    Specify architecture of the Windows version being upgraded to.

.PARAMETER Filter
    Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.

.EXAMPLE
    .\Invoke-CMDownloadLanguagePack.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -BuildNumber "14393" -Filter "Language Pack"
    
.NOTES
    FileName:    Invoke-CMDownloadLanguagePack.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-07-22
    Updated:     2019-02-14
    
    Version history:
    1.0.0 - (2017-07-22) Script created
    1.0.1 - (2017-10-08) - Added functionality to download the detected language packs
    1.0.2 - (2017-11-08) - Fixed a bug when validating the param value for PackageID
    1.0.3 - (2019-02-14) - Added capability to set OSDSetupAdditionalUpgradeOptions with required value for configuring setup.exe to install language packs from download location
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Set the URI for the ConfigMgr WebService.")]
    [ValidateNotNullOrEmpty()]
    [string]$URI,

    [parameter(Mandatory=$true, HelpMessage="Specify the known secret key for the ConfigMgr WebService.")]
    [ValidateNotNullOrEmpty()]
    [string]$SecretKey,

    [parameter(Mandatory=$true, HelpMessage="Specify build number, e.g. 14393, for the Windows version being upgraded to.")]
    [ValidateNotNullOrEmpty()]
    [string]$BuildNumber,

    [parameter(Mandatory=$true, HelpMessage="Specify architecture of the Windows version being upgraded to.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("x64", "x86")]
    [string]$OSArchitecture, 

    [parameter(Mandatory=$false, HelpMessage="Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.")]
    [ValidateNotNullOrEmpty()]
    [string]$Filter = [System.String]::Empty
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
			[ValidatePattern("^([A-Z0-9]{3}[A-F0-9]{5})(\s*)(,[A-Z0-9]{3}[A-F0-9]{5})*$")]
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
			$ReturnCode = Invoke-Executable -FilePath (Join-Path -Path $env:SystemRoot -ChildPath "CCM\OSDDownloadContent.exe")

			# Match on return code
			if ($ReturnCode -eq 0) {
				Write-CMLogEntry -Value "Successfully downloaded package content with PackageID: $($PackageID)" -Severity 1
			}
			else {
				Write-CMLogEntry -Value "Package content download process failed with return code $($ReturnCode)" -Severity 2
			}
		}
		catch [System.Exception] {
			Write-CMLogEntry -Value "An error occurred while attempting to download package content. Error message: $($_.Exception.Message)" -Severity 3 ; exit 1
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

    # Write log file for script execution
    Write-CMLogEntry -Value "Language Pack download process initiated" -Severity 1

    # Determine currently installed language packs and system culture
    $DefaultSystemCulture = [CultureInfo]::InstalledUICulture | Select-Object -ExpandProperty Name
    Write-CMLogEntry -Value "Installed UI culture detected: $($DefaultSystemCulture)" -Severity 1
    $CurrentLanguagePacks = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty MUILanguages
    Write-CMLogEntry -Value "Current language packs installed including installed UI culture: $($CurrentLanguagePacks -join ", ")" -Severity 1


    # Detect whether script should continue if more than 1 language pack is installed
    if (($CurrentLanguagePacks | Measure-Object).Count -ge 2) {
        # Construct new web service proxy
        try {
            $WebService = New-WebServiceProxy -Uri $URI -ErrorAction Stop
            Write-CMLogEntry -Value "Successfully connected to web service endpoint" -Severity 1
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value "Unable to establish a connection to web service. Error message: $($_.Exception.Message)" -Severity 3 ; exit 1
        }

        # Call web service for a list of packages
        try {
            $Packages = $WebService.GetCMPackage($SecretKey, $Filter)
            Write-CMLogEntry -Value "Retrieved a total of $(($Packages | Measure-Object).Count) packages from web service" -Severity 1
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value "An error occured while calling web service for a list of available packages. Error message: $($_.Exception.Message)" -Severity 3 ; exit 1
        }

        # Construct array list for matching packages
        $PackageList = New-Object -TypeName System.Collections.ArrayList

        # Determine packages matching operating system build number and architecture specified as in-parameters for the currently installed language packs
        if ($Packages -ne $null) {
            foreach ($Package in $Packages) {
                if ($Package.PackageName -match ($OSArchitecture) -and ($Package.PackageVersion -like $BuildNumber) -and ($Package.PackageLanguage -in $CurrentLanguagePacks) -and ($Package.PackageLanguage -notlike $DefaultSystemCulture)) {
                    $PackageList.Add($Package) | Out-Null
                    Write-CMLogEntry -Value "Found matching language pack: $($Package.PackageName)" -Severity 1
                }
            }
        }
        else {
            Write-CMLogEntry -Value "Language pack list returned from web service did not contain any matching objects" -Severity 2
        }

        # Process matching items in package list and set task sequence variable
        if ($PackageList -ne $null) {
            # Build package id list for task sequence variable
            $PackageIDs = $PackageList.PackageID -join ","

            # Attempt to download language pack package content
            Write-CMLogEntry -Value "Attempting to download language pack package content" -Severity 1
            $DownloadInvocation = Invoke-CMDownloadContent -PackageID $PackageIDs -DestinationLocationType Custom -DestinationVariableName "OSDLanguagePack" -CustomLocationPath "%_SMSTSMDataPath%\LanguagePack"

            if ($DownloadInvocation -eq 0) {
                Write-CMLogEntry -Value "Language pack package content downloaded successfully" -Severity 1

                # Set task sequence variable for handling adding additional command line options for setup.exe
                $SetupAdditionalUpgradeOptions = "/InstallLangPacks %OSDLanguagePack01%"
                Write-CMLogEntry -Value "Attempting to set OSDSetupAdditionalUpgradeOptions task sequence variable with value: $($SetupAdditionalUpgradeOptions)" -Severity 1
                $TSEnvironment.Value("OSDSetupAdditionalUpgradeOptions") = "$($SetupAdditionalUpgradeOptions)"
            }
            else {
                Write-CMLogEntry -Value "Language pack package content download process returned an unhandled exit code: $($DownloadInvocation)" -Severity 3 ; exit 1
            }
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