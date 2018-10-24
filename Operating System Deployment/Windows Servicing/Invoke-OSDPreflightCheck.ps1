<#
.SYNOPSIS
	OS Pre-Flight Checks
	
.DESCRIPTION
	Used to determine if the common pre-flight checks for performing in-place OS upgrades have been met 

.EXAMPLE
	# Run only network connectivity tests
	.\Invoke-OSDPLCheck.ps1 -NetworkCheck

	# Run disk and cache size tests
	.\Invoke-OSDPLCheck.ps1 -DiskSpaceCheck -CacheSizeCheck

.NOTES
    FileName:    Invoke-OSDPreflightCheck.ps1
    Author:      Maurice Daly / Nickolaj Andersen
    Contact:     @MoDaly_IT / @NickolajA
    Created:     2018-09-07
    Updated:     2018-09-12

    Version history:
	1.0.0 - (2018-09-07) Script created
	1.0.1 - (2018-09-07) Changed parameters to switches
	1.0.2 - (2018-09-12) Renamed battery check to power check and updated the logic around detecting if machine has the AC power connected

#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[parameter(Mandatory = $false, HelpMessage = "Specify if you want to run AC power check")]
	[switch]$PowerCheck,
	
	[parameter(Mandatory = $false, HelpMessage = "Specify if you want to run network checks")]
	[switch]$NetworkCheck,
	
	[parameter(Mandatory = $false, HelpMessage = "Specify if you want to run client cache size checks")]
	[switch]$CacheCheck,
	
	[parameter(Mandatory = $false, HelpMessage = "Specify if you want to run disk space checks")]
	[switch]$DiskSpaceCheck
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
	$LogsDirectory = $Script:TSEnvironment.Value("_SMSTSLogPath")
	
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
			[string]$FileName = "OSDPreFlight.log"
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
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""OSDPreFlightChecks"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file
		try {
			Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to OSDPreFlight.log file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
		}
	}
	
	Write-CMLogEntry -Value "===== Running in-place upgrade pre-flight checks =====" -Severity 1
	
	if ($PSBoundParameters["PowerCheck"]) {
		try {
			$LogDescription = "AC Power Pre-Flight Check:"
			Write-CMLogEntry -Value "$($LogDescription) Validating AC power status" -Severity 1
			$BatteryStatus = Get-WmiObject -Class Win32_Battery | Select-Object BatteryStatus

			# Check AC Power Status
			if ($BatteryStatus -ne $null) {
				switch ($BatteryStatus.BatteryStatus) {
					1 {
						Write-CMLogEntry -Value "$($LogDescription) Battery is present and but not running on AC power." -Severity 1
						$TSEnvironment.Value("OSDPLPowerPass") = $false
					}
					2 {
						Write-CMLogEntry -Value "$($LogDescription) Battery is present and is currently running on AC power." -Severity 1
						$TSEnvironment.Value("OSDPLPowerPass") = $true
					}
				}
			}
			else {
				Write-CMLogEntry -Value "$($LogDescription) Battery is not present in this machine." -Severity 1
				$TSEnvironment.Value("OSDPLPowerPass") = $true
			}

			Write-CMLogEntry -Value "$($LogDescription) OSDPLPowerPass variable has value: $($TSEnvironment.Value("OSDPLPowerPass"))" -Severity 1
		}
		catch [System.Exception] {
			Write-Warning -Message "$($LogDescription) An error occurred while checking battery status. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; break
		}
	}
	
	if ($PSBoundParameters["NetworkCheck"]) {
		try {
			# List all locally available IPv4 connections
			$LogDescription = "Network Pre-Flight Check:"
			$NetworkConnections = Get-NetConnectionProfile
			
			# Check Network Connection Type
			Write-CMLogEntry -Value "$($LogDescription) Checking for local domain ethernet access" -Severity 1

			# Ennumerate SMS values
			$SMSManagementPoint = Get-WmiObject -Namespace "root\CCM" -Class "SMS_Authority"
			
			foreach ($Connection in $NetworkConnections) {
				# Get Interface Details
				$InterfaceDetails = Get-NetAdapter -InterfaceAlias $Connection.InterfaceAlias
				Write-CMLogEntry -Value "$($LogDescription) Checking $($InterfaceDetails.Name)($($InterfaceDetails.InterfaceDescription)) for connectivity" -Severity 1
				
				if (($Connection.NetworkCategory -match "DomainAuthenticated") -and ($InterfaceDetails.InterfaceOperationalStatus -match "Up")) {
					Write-CMLogEntry -Value "$($LogDescription) Interface $($InterfaceDetails.Name) is domain connected. Passed network connectivity pre-flight check" -Severity 1
					$TSEnvironment.Value("OSDPLNetworkPass") = $true
				}
				elseif ($InterfaceDetails.MediaType -eq "802.3") {
					# Check local management point availiability
					Write-CMLogEntry -Value "$($LogDescription) Active VPN connection found. Testing connectivity to assigned management point" -Severity 1
					if ((-not ([string]::IsNullOrEmpty($($SMSManagementPoint).CurrentManagementPoint))) -and ((Test-NetConnection -ComputerName $($SMSManagementPoint).CurrentManagementPoint | Select-Object -ExpandProperty PingSucceeded) -eq $true)) {
						Write-CMLogEntry -Value "$($LogDescription) Successful test to management point $($SMSManagementPoint.CurrentManagementPoint)" -Severity 1
						$TSEnvironment.Value("OSDPLNetworkPass") = $true
					}
				}
			}
			if ([string]::IsNullOrEmpty($TSEnvironment.Value("OSDPLNetworkPass"))) {
				Write-CMLogEntry -Value "$($LogDescription) Processed all network interfaces but failed connectivity tests to ConfigMgr environment" -Severity 3
				$TSEnvironment.Value("OSDPLNetworkPass") = $false
			}

			Write-CMLogEntry -Value "$($LogDescription) OSDPLNetworkPass variable has value: $($TSEnvironment.Value("OSDPLNetworkPass"))" -Severity 1
		}
		catch [System.Exception] {
			Write-Warning -Message "$($LogDescription) An error occurred while checking network status. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; break
		}
	}
	
	if ($PSBoundParameters["CacheCheck"]) {
		try {
			# Check Cache Size
			$LogDescription = "Cache Size Pre-Flight Check:"
			[int]$MinCacheSize = 10
			[int]$CacheSize = [Math]::Round((Get-WmiObject -Namespace ROOT\CCM\SoftMgmtAgent -Query "Select Size from CacheConfig" | Select-Object -ExpandProperty "Size") / 1024)
			Write-CMLogEntry -Value "$($LogDescription) Client cache size determined as $($CacheSize) GB" -Severity 1
			if ($CacheSize -ge 10) {
				Write-CMLogEntry -Value "$($LogDescription) Client cache size meets minimum recommended threshold of $($MinCacheSize)GB" -Severity 1
				$TSEnvironment.Value("OSDPLCachePass") = $true
			}
			else {
				Write-CMLogEntry -Value "$($LogDescription) Client cache size does not meet minimum recommended threshold of $($MinCacheSize)GB" -Severity 3
				$TSEnvironment.Value("OSDPLCachePass") = $false
			}

			Write-CMLogEntry -Value "$($LogDescription) OSDPLCachePass variable has value: $($TSEnvironment.Value("OSDPLCachePass"))" -Severity 1
		}
		catch [System.Exception] {
			Write-Warning -Message "$($LogDescription) An error occurred while checking cache size value. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; break
		}
	}
	
	if ($PSBoundParameters["DiskSpaceCheck"]) {
		try {
			# Check Hard Disk Space
			$LogDescription = "Hard Disk Pre-Flight Check:"
			Write-CMLogEntry -Value "$($LogDescription) Checking free disk space reserve on drive C:" -Severity 1

			$OSDriveInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
			[int]$MinDiskValue = 40
			[int]$FreeDiskSpace = [math]::Round(($OSDriveInfo.FreeSpace)/1gb)
			
			if ($FreeDiskSpace -ge $MinDiskValue) {
				$TSEnvironment.Value("OSDPLDiskSpacePass") = $true
				Write-CMLogEntry -Value "$($LogDescription) Drive C: ($($OSDriveInfo.VolumeName)) currently has $($FreeDiskSpace)GB of available disk space. Sufficient free space is available." -Severity 1
			}
			else {
				$TSEnvironment.Value("OSDPLDiskSpacePass") = $false
				Write-CMLogEntry -Value "$($LogDescription) Drive C: ($($OSDriveInfo.VolumeName)) does not meet minimum free disk space reserve of ($($MinDiskValue)GB)" -Severity 3
			}

			Write-CMLogEntry -Value "$($LogDescription) OSDPLDiskSpacePass variable has value: $($TSEnvironment.Value("OSDPLDiskSpacePass"))" -Severity 1
		}
		catch [System.Exception] {
			Write-Warning -Message "$($LogDescription) An error occurred while checking free disk space. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; break
		}
	}
}
