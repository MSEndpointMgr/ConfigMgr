<#
.SYNOPSIS
	Refresh Driver script for Windows
	
.DESCRIPTION
    This script is to be used in conjunction with the SCConfigMgr Modern Driver Management process for 
	driver maintenance post Windows deployment.

.NOTES
    FileName:    Invoke-CMDownloadDriverPackage.ps1
    Author:      Maurice Daly
    Contact:     @MoDaly_IT
    Created:     2017-10-13
	Updated:     2017-10-13
	
	Minimum required version of ConfigMgr WebService: 1.4.0
    
    Version history:
    1.0.0 - (2017-10-13) Script created
#>
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
		[string]$FileName = "ApplyDriverMaintenancePackage.log"
	)
	# Determine log file location
	#$LogFilePath = Join-Path -Path $Script:TSEnvironment.Value("_SMSTSLogPath") -ChildPath $FileName
	$LogFilePath = Join-Path -Path C:\Windows\Temp -ChildPath $FileName
	
	# Construct time stamp for log entry
	$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
	
	# Construct date for log entry
	$Date = (Get-Date -Format "MM-dd-yyyy")
	
	# Construct context for log entry
	$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
	
	# Construct final log entry
	$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""ApplyDriverMaintenancePackage"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
	
	# Add value to log file
	try {
		Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to append log entry to ApplyDriverMaintenancePackage.log file. Error message: $($_.Exception.Message)"
	}
}

# Apply driver maintenance package
try {
	Write-CMLogEntry -Value "Starting driver installation process" -Severity 1
	Get-ChildItem -Path "C:\_SMSTaskSequence\DriverPackage" -Filter *.inf -Recurse | ForEach-Object {
		pnputil /add-driver $_.FullName /install /subdirs
	} | Out-File -FilePath C:\Windows\Temp\DriverMaintenance.log -Force
	Write-CMLogEntry -Value "Driver installation complete. Restart required" -Severity 1
	exit 0
}
catch [System.Exception] {
	Write-CMLogEntry -Value "An error occurred while attempting to apply the driver maintenance package. Error message: $($_.Exception.Message)" -Severity 3
	exit 1
}