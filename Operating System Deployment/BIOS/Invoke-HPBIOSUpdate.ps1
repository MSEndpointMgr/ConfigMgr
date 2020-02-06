<#
.SYNOPSIS
    Invoke HP BIOS Update process.

.DESCRIPTION
    This script will invoke the HP BIOS update process for the executable residing in the path specified for the Path parameter.

.PARAMETER Path
    Specify the path containing the HPBIOSUPDREC executable and bios update *.bin -file.

.PARAMETER PasswordBin
    Specify the BIOS password file if necessary (save the password file to the same directory as the script).

.PARAMETER LogFileName
    Set the name of the log file produced by the flash utility.

.EXAMPLE
    .\Invoke-HPBIOSUpdate.ps1 -Path %OSDBIOSPackage01% -PasswordBin "Password.bin"

.NOTES
    FileName:    Invoke-HPBIOSUpdate.ps1
    Author:      Lauri Kurvinen / Nickolaj Andersen
    Contact:     @estmi / @NickolajA
    Created:     2017-09-05
    Updated:     2020-02-06

    Version history:
	1.0.0 - (2017-09-05) Script created
	1.0.1 - (2018-01-30) Updated encrypted volume check and cleaned up some logging messages
	1.0.2 - (2018-06-14) Added support for HPFirmwareUpdRec utility - thanks to Jann Idar Hillestad (jihillestad@hotmail.com)
	1.0.3 - (2019-04-30) Updated to support HPQFlash.exe and HPQFlash64.exe
	1.0.4 - (2019-05-14) Handle $PasswordBin to check if empty string or null instead of just null value
	1.0.5 - (2019-05-14) Fixed an issue where the flash utility would look in the script executing location instead of the passed $Path location for the update file
	1.0.6 - (2020-02-06) Previous "fix" in 1.0.5 was a mistake, this version corrects it
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
	[parameter(Mandatory = $true, HelpMessage = "Specify the path containing the HPBIOSUPDREC executable and bios update *.bin -file.")]
	[ValidateNotNullOrEmpty()]
	[string]$Path,

	[parameter(Mandatory = $false, HelpMessage = "Specify the BIOS password filename if necessary (save the password file to the same directory as the script).")]
	[ValidateNotNullOrEmpty()]
	[string]$PasswordBin,

	[parameter(Mandatory = $false, HelpMessage = "Set the name of the log file produced by the flash utility.")]
	[ValidateNotNullOrEmpty()]
	[string]$LogFileName = "HPFlashBIOSUpdate.log"	
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
			[string]$FileName = "Invoke-HPBIOSUpdate.log"	
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
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""HPBIOSUpdate.log"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"

		# Add value to log file
		try {
			Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop 
		}		
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to Invoke-HPBIOSUpdate.log file. Error message: $($_.Exception.Message)"
		}
	}
	
	# Change working directory to path containing BIOS files	
	Set-Location -Path $Path	
	Write-CMLogEntry -Value "Working directory set as $($Path)" -Severity 1

	# Write log file for script execution	
	Write-CMLogEntry -Value "Initiating script to determine flashing capabilities for HP BIOS updates" -Severity 1
	
	# Attempt to detect HPBIOSUPDREC utility file name
	if (([Environment]::Is64BitOperatingSystem) -eq $true) {
		$HPBIOSUPDUtil = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "HPBIOSUPDREC64.exe" } | Select-Object -ExpandProperty FullName	
	}
	else {
		$HPBIOSUPDUtil = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "HPBIOSUPDREC.exe" } | Select-Object -ExpandProperty FullName	
	}

    # Attempt to detect HPFirmwareUpdRec utility file name
	if (([Environment]::Is64BitOperatingSystem) -eq $true) {
		$HPFirmwareUpdRec = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "HpFirmwareUpdRec64.exe" } | Select-Object -ExpandProperty FullName
	}
	else {
		$HPFirmwareUpdRec = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "HpFirmwareUpdRec.exe" } | Select-Object -ExpandProperty FullName	
	}

    # Attempt to detect HPFirmwareUpdRec utility file name
	if (([Environment]::Is64BitOperatingSystem) -eq $true) {
		$HPFlashUtil = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "HPQFlash.exe" } | Select-Object -ExpandProperty FullName
	}
	else {
		$HPFlashUtil = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "HPQFlash64.exe" } | Select-Object -ExpandProperty FullName	
	}

	if ($HPBIOSUPDUtil -ne $null) {	
		# Set required switches for silent upgrade of the bios and logging
		Write-CMLogEntry -Value "Using HPBIOSUpdRec BIOS update method" -Severity 1
		# This -r switch appears to be undocumented, which is a shame really, but this prevents the reboot without exit code. The command now returns a correct exit code and lets ConfigMgr reboot the computer gracefully.
		$FlashSwitches = " -s -r"
		$FlashUtility = $HPBIOSUPDUtil
	}

	if ($HPFirmwareUpdRec -ne $null) {	
		# Set required switches for silent upgrade of the bios and logging
		Write-CMLogEntry -Value "Using HPFirmwareUpdRec BIOS update method" -Severity 1
		# This -r switch appears to be undocumented, which is a shame really, but this prevents the reboot without exit code. The command now returns a correct exit code and lets ConfigMgr reboot the computer gracefully.
		$FlashSwitches = " -s -r"
		$FlashUtility = $HPFirmwareUpdRec
	}

	if ($HPFlashUtil -ne $null) {	
		# Set required switches for silent upgrade of the bios and logging
		Write-CMLogEntry -Value "Using HPFirmwareUpdRec BIOS update method" -Severity 1
		# This -r switch appears to be undocumented, which is a shame really, but this prevents the reboot without exit code. The command now returns a correct exit code and lets ConfigMgr reboot the computer gracefully.
		$FlashSwitches = " -s -r"
		$FlashUtility = $HPFlashUtil
	}
	
	if (-not($FlashUtility)) {
		Write-CMLogEntry -Value "Supported upgrade utility was not found." -Severity 3; exit 1	
	}
	
	if (-not([System.String]::IsNullOrEmpty($PasswordBin))) {
		# Add password to the flash bios switches
		$FlashSwitches = $FlashSwitches + " -p$($PSScriptRoot)\$($PasswordBin)"	
		Write-CMLogEntry -Value "Using the following switches for BIOS file: $($FlashSwitches)" -Severity 1
	}
	else {
		Write-CMLogEntry -Value "Using the following switches for BIOS file: $($FlashSwitches)" -Severity 1
	}

	# Set log file location
	$LogFilePath = Join-Path -Path $TSEnvironment.Value("_SMSTSLogPath") -ChildPath $LogFileName
	
	# Determine if we're running in WinPE or Full OS
	if (($TSEnvironment -ne $null) -and ($TSEnvironment.Value("_SMSTSinWinPE") -eq $true)) {
		try {		
			# Start flash update process
			$FlashProcess = Start-Process -FilePath $FlashUtility -ArgumentList $FlashSwitches -Passthru -Wait

			# Output Exit Code for testing purposes
			$FlashProcess.ExitCode | Out-File -FilePath $LogFilePath	
		}	
		catch [System.Exception] {
			Write-CMLogEntry -Value "An error occured while updating the system BIOS in WinPE phase. Error message: $($_.Exception.Message)" -Severity 3; exit 1	
		}
	}
	else {
		# Used in a later section of the task sequence
		# Detect Bitlocker Status
		$OSDriveEncrypted = $false
		$EncryptedVolumes = Get-WmiObject -Namespace "root\cimv2\Security\MicrosoftVolumeEncryption" -Class "Win32_EncryptableVolume"
		foreach ($Volume in $EncryptedVolumes) {
			if ($Volume.DriveLetter -like $env:SystemDrive) {
				if ($Volume.EncryptionMethod -ge 1) {
					$OSDriveEncrypted = $true
				}
			}
		}
				
		# Supend Bitlocker if $OSVolumeEncypted is $true
		if ($OSDriveEncrypted -eq $true) {
			Write-CMLogEntry -Value "Suspending BitLocker protected volume: $($env:SystemDrive)" -Severity 1
			Manage-Bde -Protectors -Disable C:
		}		
		
		# Start Bios update process
		try {			
			Write-CMLogEntry -Value "Running Flash Update - $($FlashUtility)" -Severity 1			
			$FlashProcess = Start-Process -FilePath $FlashUtility -ArgumentList $FlashSwitches -Passthru -Wait			
			# Output Exit Code for testing purposes			
			$FlashProcess.ExitCode | Out-File -FilePath $LogFilePath
		}
		catch [System.Exception] {
			Write-Warning -Message "An error occured while updating the system BIOS in Full OS phase. Error message: $($_.Exception.Message)"; exit 1
		}
	}
}
