<#
.SYNOPSIS
    Download BIOS package (regular package) matching computer model and manufacturer.
.DESCRIPTION
    This script will determine the model of the computer and manufacturer and then query the specified endpoint
    for ConfigMgr WebService for a list of Packages. It then sets the OSDDownloadDownloadPackages variable to include
    the PackageID property of a package matching the computer model. If multiple packages are detect, it will select
    most current one by the creation date of the packages.
.PARAMETER URI
    Set the URI for the ConfigMgr WebService.
.PARAMETER SecretKey
    Specify the known secret key for the ConfigMgr WebService.
.PARAMETER Filter
    Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.
.EXAMPLE
    .\Invoke-CMDownloadBIOSPackage.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345" -Filter "BIOS"
.NOTES
    FileName:    Invoke-CMDownloadBIOSPackage.ps1
    Author:      Nickolaj Andersen & Maurice Daly
    Contact:     @NickolajA / @modaly_it
    Created:     2017-05-22
    Updated:     2017-07-27
    
    Version history:
    1.0.0 - (2017-05-22) Script created (Nickolaj Andersen)
    1.0.1 - (2017-07-07) Updated with BIOS revision checker. Initially used for Dell systems (Maurice Daly)
    1.0.2 - (2017-07-13) Updated with support for downloading BIOS packages for Lenovo models (Maurice Daly)
    1.0.3 - (2017-07-19) Updated with additional condition for matching Lenovo models (Maurice Daly)
    1.0.4 - (2017-07-27) Updated with additional logic for matching based on description for Lenovo models and version checking update for Lenovo using the release date value (Maurice Daly)
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
Begin
{
	# Load Microsoft.SMS.TSEnvironment COM object
	try
	{
		$TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object"; exit 1
	}
}
Process
{
	# Functions
	function Write-CMLogEntry
	{
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
			[string]$FileName = "BIOSPackageDownload.log"
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
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""BIOSPackageDownloader"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file
		try
		{
			Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to BIOSPackageDownload.log file. Error message: $($_.Exception.Message)"
		}
	}
	
	function Compare-BIOSVersion
	{
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
		
		if ($ComputerManufacturer -match "Dell")
		{
			# Obtain current BIOS release
			$CurrentBIOSVersion = (Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty SMBIOSBIOSVersion).Trim()
            Write-CMLogEntry -Value "Current BIOS release detected as $CurrentBIOSVersion." -Severity 1
						
			# Determine Dell BIOS revision format			
			if ($CurrentBIOSVersion -like "*.*.*")
			{
				# Compare current BIOS release to available
				if ([System.Version]$AvailableBIOSVersion -gt [System.Version]$CurrentBIOSVersion)
				{
					# Write output to task sequence variable
					$TSEnvironment.Value("NewBIOSAvailable") = $true
					Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current release $($CurrentBIOSVersion) will be replaced by $($AvailableBIOSVersion)." -Severity 1
				}
			}
			elseif ($CurrentBIOSVersion -like "A*")
			{
				# Compare current BIOS release to available
				if ($AvailableBIOSVersion -like "*.*.*")
				{
					# Assume that the bios is new as moving from Axx to x.x.x formats
					# Write output to task sequence variable
					$TSEnvironment.Value("NewBIOSAvailable") = $true
					Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current release $CurrentBIOSVersion will be replaced by $AvailableBIOSVersion." -Severity 1
				}
				elseif ($AvailableBIOSVersion -gt $CurrentBIOSVersion)
				{
					# Write output to task sequence variable
					$TSEnvironment.Value("NewBIOSAvailable") = $true
					Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current release $CurrentBIOSVersion will be replaced by $AvailableBIOSVersion." -Severity 1
				}
			}
		}
		
		if ($ComputerManufacturer -match "Lenovo")
		{
			# Obtain current BIOS release
			$CurrentBIOSReleaseDate = ((Get-WmiObject -Class Win32_BIOS | Select -Property *).ReleaseDate).SubString(0, 8)
            Write-CMLogEntry -Value "Current BIOS release date detected as $CurrentBIOSReleaseDate." -Severity 1
             Write-CMLogEntry -Value "Available BIOS release date detected as $AvailableBIOSReleaseDate." -Severity 1

			# Compare current BIOS release to available
			if ($AvailableBIOSReleaseDate -gt $CurrentBIOSReleaseDate)
			{
				# Write output to task sequence variable
				#$TSEnvironment.Value("NewBIOSAvailable") = $true
				Write-CMLogEntry -Value "A new version of the BIOS has been detected. Current date release dated $CurrentBIOSReleaseDate will be replaced by release $AvailableBIOSReleaseDate." -Severity 1
			}
		}
	}
	
	# Write log file for script execution
	Write-CMLogEntry -Value "BIOS download package process initiated" -Severity 1
	
	# Determine manufacturer
	#$ComputerManufacturer = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer).Trim()
	Write-CMLogEntry -Value "Manufacturer determined as: $($ComputerManufacturer)" -Severity 1
	
	Determine manufacturer name and computer model
	switch -Wildcard ($ComputerManufacturer)
	{
		"*Dell*" {
			$ComputerManufacturer = "Dell"
			$ComputerModel = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
		}
		"*Lenovo*" {
			$ComputerManufacturer = "Lenovo"
			$ComputerModel = ((Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model).SubString(0, 4)).Trim()
			$ComputerName = ((Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty Name).SubString(0, 4)).Trim()
		}
	}
	Write-CMLogEntry -Value "Computer model determined as: $($ComputerModel)" -Severity 1
	
	# Get existing BIOS version
	$CurrentBIOSVersion = (Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty SMBIOSBIOSVersion).Trim()
	Write-CMLogEntry -Value "Current BIOS version determined as: $($CurrentBIOSVersion)" -Severity 1
	
	# Construct new web service proxy
	try
	{
		$WebService = New-WebServiceProxy -Uri $URI -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "Unable to establish a connection to ConfigMgr WebService. Error message: $($_.Exception.Message)" -Severity 3; exit 1
	}
	
	# Call web service for a list of packages
	try
	{
		$Packages = $WebService.GetCMPackage($SecretKey, "$($Filter)")
		Write-CMLogEntry -Value "Retrieved a total of $(($Packages | Measure-Object).Count) BIOS packages from web service" -Severity 1
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "An error occured while calling ConfigMgr WebService for a list of available packages. Error message: $($_.Exception.Message)" -Severity 3; exit 1
	}
	
	# Construct array list for matching packages
	$PackageList = New-Object -TypeName System.Collections.ArrayList
	
	# Set script error preference variable
	$ErrorActionPreference = "Stop"
	
	# Validate supported system was detected
	if ($ComputerManufacturer -eq "Dell" -or $ComputerManufacturer -eq "Lenovo")
	{
		# Process packages returned from web service
		if ($Packages -ne $null)
		{
			    # Add packages with matching criteria to list
			foreach ($Package in $Packages)
			{
				if ($Package.PackageManufacturer -ne $null) {
					# Match model, manufacturer criteria
					if ($ComputerManufacturer -eq "Dell")
					{
						if (($Package.PackageName -match $ComputerModel) -and ($ComputerManufacturer -match $Package.PackageManufacturer))
						{
							Write-CMLogEntry -Value "Match found for computer model and manufacturer: $($Package.PackageName) ($($Package.PackageID))" -Severity 1
							$PackageList.Add($Package) | Out-Null
						}
						else{
							Write-CMLogEntry -Value "Package does not meet computer model and manufacturer criteria: $($Package.PackageName) ($($Package.PackageID))" -Severity 2
						}
					}
					
					if (($ComputerManufacturer -eq "Lenovo") -and ($ComputerManufacturer -match $Package.PackageManufacturer) -and (($Package.PackageDescription.Split(":")[1]) -ne $null))
					{
							if (($Package.PackageDescription.Split(":")[1].Trimend(")")) -match $ComputerModel)
							{
								Write-CMLogEntry -Value "Match found for computer model and manufacturer: $($Package.PackageName) ($($Package.PackageID))" -Severity 1
								$PackageList.Add($Package) | Out-Null
							}
					}
					else{
						Write-CMLogEntry -Value "Package does not meet computer model and manufacturer criteria: $($Package.PackageName) ($($Package.PackageID))" -Severity 2
					}
				}
			}
			
			# Process matching items in package list and set task sequence variable
			if ($PackageList -ne $null)
			{
				# Determine the most current package from list
				if ($PackageList.Count -eq 1)
				{
					Write-CMLogEntry -Value "BIOS package list contains a single match, attempting to set task sequence variable" -Severity 1
					
					# Check if BIOS package is newer than currently installed
					if ($ComputerManufacturer -match "Dell")
					{
						Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].PackageVersion -ComputerManufacturer $ComputerManufacturer
					}
					if ($ComputerManufacturer -match "Lenovo")
					{
						Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].PackageVersion -AvailableBIOSReleaseDate $(($PackageList[0].PackageDescription).Split(":")[2].Trimend(")")) -ComputerManufacturer $ComputerManufacturer
					}
					
					if ($TSEnvironment.Value("NewBIOSAvailable") -eq $true)
					{
						# Attempt to set task sequence variable
						try
						{
							$TSEnvironment.Value("OSDDownloadDownloadPackages") = $($PackageList[0].PackageID)
							Write-CMLogEntry -Value "Successfully set OSDDownloadDownloadPackages variable with PackageID: $($PackageList[0].PackageID)" -Severity 1
						}
						catch [System.Exception] {
							Write-CMLogEntry -Value "An error occured while setting OSDDownloadDownloadPackages variable. Error message: $($_.Exception.Message)" -Severity 3; exit 1
						}
					}
					else{
						Write-CMLogEntry -Value "BIOS is already up to date with the latest $($PackageList[0].PackageVersion) version" -Severity 1
					}
				}
				elseif ($PackageList.Count -ge 2)
				{
					Write-CMLogEntry -Value "BIOS package list contains multiple matches, attempting to set task sequence variable" -Severity 1
					
					# Determine the latest BIOS package by creation date
					if ($ComputerManufacturer -match "Dell")
					{
						$Package = $PackageList | Sort-Object -Property PackageCreated -Descending | Select-Object -First 1
					}
					elseif ($ComputerManufacturer -eq "Lenovo")
					{
						If ($Package -ne $null)
						{
							#$ComputerDescription = Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version
							# Attempt to find exact model match for Lenovo models which overlap model types
                            $PackageList = $PackageList | Where-object {($_.PackageName -like "*$ComputerDescription") -and ($_.PackageManufacturer -match $ComputerManufacturer)}
							#$PackageList = $PackageList | Where-object { (($_.PackageDescription.Split("(")[0]) -match ("$ComputerDescription BIOS")) }
							#$Package.PackageDescription.Split("(")[0]) -match (Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version) +" BIOS")
						}
						else{
							# Fall back to select the latest model type match if no model name match is found
							$Package = $PackageList | Sort-object -Property PackageVersion -Descending | Select-Object -First 1
						}
					}
					if ($PackageList.Count -eq 1)
					{
						# Check if BIOS package is newer than currently installed
						if ($ComputerManufacturer -match "Dell")
						{
							Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].PackageVersion -ComputerManufacturer $ComputerManufacturer
						}
						elseif ($ComputerManufacturer -match "Lenovo")
						{
							Compare-BIOSVersion -AvailableBIOSVersion $PackageList[0].PackageVersion -AvailableBIOSReleaseDate $(($PackageList[0].PackageDescription).Split(":")[2]).Trimend(")") -ComputerManufacturer $ComputerManufacturer
						}
						else{
							Write-CMLogEntry -Value "BIOS is already up to date with the latest $($PackageList[0].PackageVersion) version" -Severity 1
						}
						
						if ($TSEnvironment.Value("NewBIOSAvailable") -eq $true)
						{
							# Attempt to set task sequence variable
							try
							{
								$TSEnvironment.Value("OSDDownloadDownloadPackages") = $($PackageList[0].PackageID)
								Write-CMLogEntry -Value "Successfully set OSDDownloadDownloadPackages variable with PackageID: $($Package.PackageID)" -Severity 1
							}
							catch [System.Exception] {
								Write-CMLogEntry -Value "An error occured while setting OSDDownloadDownloadPackages variable. Error message: $($_.Exception.Message)" -Severity 3; exit 1
							}
						}
						else{
							Write-CMLogEntry -Value "Empty BIOS package list detected, bailing out" -Severity 1
						}
					}
					else{
						Write-CMLogEntry -Value "Unable to determine a matching BIOS package from list since an unsupported count was returned from package list, bailing out" -Severity 2; exit 1
					}
				}
				else{
					Write-CMLogEntry -Value "Empty BIOS package list detected, bailing out" -Severity 1
				}
			}
			else{
				Write-CMLogEntry -Value "BIOS package list returned from web service did not contain any objects matching the computer model and manufacturer, bailing out" -Severity 1
			}
		}
		else{
			Write-CMLogEntry -Value "This script is supported on Dell and Lenovo systems only at this point, bailing out" -Severity 1
		}
	}
}
