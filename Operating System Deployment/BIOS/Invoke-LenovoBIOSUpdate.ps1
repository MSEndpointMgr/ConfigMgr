<#
.SYNOPSIS
	Invoke Lenovo BIOS Update process.
	
.DESCRIPTION
	This script will invoke the Lenovo BIOS update process for the executable residing in the path specified for the Path parameter.
	
	IMPORTANT: This script requires the WinPE-HTA optional component added to the boot image when used during WinPE phase.
	
.PARAMETER Path
	Specify the path containing the WinUPTP or Flash.cmd
	
.PARAMETER Password
	Specify the BIOS password if necessary.
	
.PARAMETER LogFileName
	Set the name of the log file produced by the flash utility.
	
.EXAMPLE
	.\Invoke-LenovoBIOSUpdate.ps1 -Path %OSDBIOSPackage01% -Password "BIOSPassword"
	
.NOTES
    FileName:    Invoke-LenovoBIOSUpdate.ps1
    Author:      Maurice Daly / Nickolaj Andersen
    Contact:     @modaly_it / @NickolajA
    Created:     2017-06-09
    Updated:     2019-05-14
    
    Version history:
    1.0.0 - (2017-06-09) Script created
	1.0.1 - (2017-07-05) Added additional logging, methods and variables
	1.0.2 - (2018-01-29) Changed condition for the password switches
	1.0.3 - (2018-04-30) Example conditional variable example updated. No functional changes
	1.0.4 - (2018-05-07) Updated to copy in required OLEDLG.dll where missing in the BIOS package
	1.0.5 - (2018-05-08) Updated to cater for varying OS source directory paths
	1.0.6 - (2018-12-10) Updated to support 64-bit version of Flash64.cmd
	1.0.7 - (2019-05-01) Extended the search for OLEDLG.dll to include X: for when running from WinPE
	1.0.8 - (2019-05-01) Fixed a bug where the script would show an error and fail if the WinUPTP log file could not be found
	1.0.9 - (2019-05-14) Handle $Password to check if empty string or null instead of just null value
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[parameter(Mandatory = $true, HelpMessage = "Specify the path containing the Flash64W.exe and BIOS executable.")]
	[ValidateNotNullOrEmpty()]
	[string]$Path,
	[parameter(Mandatory = $false, HelpMessage = "Specify the BIOS password if necessary.")]
	[ValidateNotNullOrEmpty()]
	[string]$Password,
	[parameter(Mandatory = $false, HelpMessage = "Set the name of the log file produced by the flash utility.")]
	[ValidateNotNullOrEmpty()]
	[string]$LogFileName = "LenovoFlashBiosUpdate.log"
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
			[string]$FileName = "Invoke-LenovoBIOSUpdate.log"
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
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""LenovoBIOSUpdate.log"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file
		try {
			Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to Invoke-LenovoBIOSUpdate.log file. Error message: $($_.Exception.Message)"
		}
	}
	
	Set-Location -Path $Path
	# Write log file for script execution
	Write-CMLogEntry -Value "Initiating script to determine flashing capabilities for Lenovo BIOS updates" -Severity 1
	
	# Check for required DLL's
	if ((Test-Path -Path (Join-Path -Path $Path -ChildPath "OLEDLG.dll")) -eq $False) {
		Write-CMLogEntry -Value "Copying OLEDLG.dll to $($Path) directory" -Severity 1
		if (([string]::IsNullOrEmpty($TSEnvironment.Value("OSDisk"))) -eq $false) {
			Copy-Item -Path (Join-Path -path $TSEnvironment.Value("OSDisk") -ChildPath "Windows\System32\OLEDLG.dll") -Destination "$($Path)\OLEDLG.dll"
		}
		elseif ((Test-Path -Path "C:\Windows\System32\OLEDLG.dll") -eq $true) {
			Copy-Item -Path "C:\Windows\System32\OLEDLG.dll" -Destination "$($Path)\OLEDLG.dll"
		}
		elseif ((Test-Path -Path "D:\Windows\System32\OLEDLG.dll") -eq $true) {
			Copy-Item -Path "D:\Windows\System32\OLEDLG.dll" -Destination "$($Path)\OLEDLG.dll"
		}
		elseif ((Test-Path -Path "X:\Windows\System32\OLEDLG.dll") -eq $true) {
			Copy-Item -Path "X:\Windows\System32\OLEDLG.dll" -Destination "$($Path)\OLEDLG.dll"
		}
		else {
			Write-CMLogEntry -Value "Failed to copy DLL file. Aborting update process" -Severity 3; exit 1
		}
	}
	
	# WinUPTP bios upgrade utility file name
	if (([Environment]::Is64BitOperatingSystem) -eq $true) {
		$WinUPTPUtility = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "WinUPTP64.exe"	} | Select-Object -ExpandProperty FullName
	}
	else {
		$WinUPTPUtility = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "WinUPTP.exe" } | Select-Object -ExpandProperty FullName
	}
	
    # Flash CMD upgrade utility file name
    if (([Environment]::Is64BitOperatingSystem) -eq $true) {
        $FlashCMDUtility = Get-ChildItem -Path $Path -Filter "*.cmd" -Recurse | Where-Object { $_.Name -like "Flash64.cmd" } | Select-Object -ExpandProperty FullName
    }
    else {
        $FlashCMDUtility = Get-ChildItem -Path $Path -Filter "*.cmd" -Recurse | Where-Object { $_.Name -like "Flash.cmd" } | Select-Object -ExpandProperty FullName
    }

	if ($WinUPTPUtility -ne $null) {
		# Set required switches for silent upgrade of the bios and logging
		Write-CMLogEntry -Value "Using WinUTPT BIOS update method" -Severity 1
		$FlashSwitches = " /S"
		$FlashUtility = $WinUPTPUtility
	}
	
	if ($FlashCMDUtility -ne $null) {
		# Set required switches for silent upgrade of the bios and logging
		Write-CMLogEntry -Value "Using FlashCMDUtility BIOS update method" -Severity 1
		$FlashSwitches = " /quiet /sccm /ign"
		$FlashUtility = $FlashCMDUtility
	}
	
	if (-not($FlashUtility)) {
		Write-CMLogEntry -Value "Supported upgrade utility was not found." -Severity 3; break
	}
	
	if (-not([System.String]::IsNullOrEmpty($Password))) {
		# Add password to the flash bios switches
		$FlashSwitches = $FlashSwitches + " /pass:$($Password)"
		Write-CMLogEntry -Value "Using the following switches for BIOS file: $($FlashSwitches -replace $Password, "<Password Removed>")" -Severity 1
	}
	else {
		Write-CMLogEntry -Value "Using the following switches for BIOS file: $($FlashSwitches)" -Severity 1
	}
	
	# Set log file location
	$LogFilePath = Join-Path -Path $TSEnvironment.Value("_SMSTSLogPath") -ChildPath $LogFileName
	
	if (($TSEnvironment -ne $null) -and ($TSEnvironment.Value("_SMSTSinWinPE") -eq $true)) {
		try {
			# Start flash update process
			$FlashProcess = Start-Process -FilePath $FlashUtility -ArgumentList "$FlashSwitches" -Passthru -Wait
			
			#Output Exit Code for testing purposes
			$FlashProcess.ExitCode | Out-File -FilePath $LogFilePath
			
			#Get winuptp.log file
			$WinUPTPLog = Get-ChildItem -Filter "*.log" -Recurse | Where-Object { $_.Name -like "winuptp.log" } -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
			if ($WinUPTPLog -ne $null) {
				Write-CMLogEntry -Value "winuptp.log file path is $($WinUPTPLog)" -Severity 1
				$SMSTSLogPath = Join-Path -Path $TSEnvironment.Value("_SMSTSLogPath") -ChildPath "winuptp.log"
				Copy-Item -Path $WinUPTPLog -Destination $SMSTSLogPath -Force -ErrorAction SilentlyContinue
			}
		}
		catch [System.Exception] {
			Write-CMLogEntry -Value "An error occured while updating the system BIOS in OS online phase. Error message: $($_.Exception.Message)" -Severity 3; exit 1
		}
	}
	else {
		# Detect Bitlocker Status
		$OSVolumeEncypted = if ((Manage-Bde -Status C:) -match "Protection On") {
			Write-Output $True
		}
		else {
			Write-Output $False
		}
		
		# Supend Bitlocker if $OSVolumeEncypted is $true
		if ($OSVolumeEncypted -eq $true) {
			Write-CMLogEntry -Value "Suspending BitLocker protected volume: C:" -Severity 1
			Manage-Bde -Protectors -Disable C:
		}
		
		# Start BIOS update process
		try {
			Write-CMLogEntry -Value "Running Flash Update - $($FlashUtility)" -Severity 1
			$FlashProcess = Start-Process -FilePath $FlashUtility -ArgumentList "$($FlashSwitches)" -Passthru -Wait
			
			# Output Exit Code for testing purposes
			$FlashProcess.ExitCode | Out-File -FilePath $LogFilePath
		}
		catch [System.Exception]
		{
			Write-Warning -Message "An error occured while updating the system bios. Error message: $($_.Exception.Message)"; exit 1
		}
	}
}
