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
    Updated:     2019-03-19

    Version history:
	1.0.0 - (2018-09-07) Script created
	1.0.1 - (2018-09-07) Changed parameters to switches
	1.0.2 - (2018-09-12) Renamed battery check to power check and updated the logic around detecting if machine has the AC power connected
	1.0.3 - (2018-11-26) Updated the DiskFreeSpace check to create a TS variable named 'OSDCleanDisk' if free disk space is below the specified amount of GB
	1.0.4 - (2019-03-19) Added VPN check to see if an established VPN connection exist
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[parameter(Mandatory = $false, HelpMessage = "Specify if you want to run AC power check.")]
	[switch]$PowerCheck,
	
	[parameter(Mandatory = $false, HelpMessage = "Specify if you want to run network check.")]
	[switch]$NetworkCheck,
	
	[parameter(Mandatory = $false, HelpMessage = "Specify if you want to run client cache size check.")]
	[switch]$CacheCheck,
	
	[parameter(Mandatory = $false, HelpMessage = "Specify if you want to run disk space check.")]
	[switch]$DiskSpaceCheck,

	[parameter(Mandatory = $false, HelpMessage = "Specify if you want to run established VPN connection check.")]
	[switch]$VPNCheck
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
	
	Write-CMLogEntry -Value "===== Running selected In-Place Upgrade pre-flight checks =====" -Severity 1
	
	if ($PSBoundParameters["PowerCheck"]) {
		try {
			$LogDescription = "AC Power check:"
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
			$LogDescription = "Network check:"
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
			$LogDescription = "ConfigMgr Client cache size check:"
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
			$LogDescription = "Hard Disk check:"
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
				$TSEnvironment.Value("OSDCleanDisk") = $true
				Write-CMLogEntry -Value "$($LogDescription) Drive C: ($($OSDriveInfo.VolumeName)) does not meet minimum free disk space reserve of ($($MinDiskValue)GB)" -Severity 3
			}

			Write-CMLogEntry -Value "$($LogDescription) OSDPLDiskSpacePass variable has value: $($TSEnvironment.Value("OSDPLDiskSpacePass"))" -Severity 1
		}
		catch [System.Exception] {
			Write-Warning -Message "$($LogDescription) An error occurred while checking free disk space. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; break
		}
	}

	if ($PSBoundParameters["VPNCheck"]) {
		try {
			# Check Hard Disk Space
			$LogDescription = "Established VPN connection check:"
			Write-CMLogEntry -Value "$($LogDescription) Checking for an established VPN connection" -Severity 1

			# Control variable for outcome of check
			$VPNConnectionEstablished = $false

			# Validate that Direct Access is configured
			$DirectAccess = Get-ChildItem -Path "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient\DnsPolicyConfig" -ErrorAction SilentlyContinue
			if ($DirectAccess -ne $null) {
				# Validate that Direct Access is not connected
				if ((Get-DAConnectionStatus | Select-Object -Property Status).Status -notlike "ConnectedRemotely") {
					# Continue, Direct Access is not successfully connected
					Write-CMLogEntry -Value "$($LogDescription) Direct Access was not detected as connected" -Severity 1
				}
				else {
					# Do not continue, Direct Access is connected
					Write-CMLogEntry -Value "$($LogDescription) Direct Access was detected as connected" -Severity 2
					$VPNConnectionEstablished = $true
				}
			}

			# Validate that VPN connection is not in use
			$KnownDescriptionPattern = @('^WAN Miniport \(PPPOE\)', '^WAN Miniport \(IPv6\)', '^WAN Miniport \(Network Monitor\)', '^WAN Miniport \(IP\)', '^Surface Ethernet Adapter', '^Microsoft 6to4 Adapter', '^Hyper-V Virtual', '^Microsoft Wi-Fi Direct Virtual Adapter', '^Microsoft Virtual WiFi Miniport Adapter', '^Microsoft WiFi Direct Virtual Adapter', '^Microsoft ISATAP Adapter', '^Direct Parallel', '^Microsoft Kernel Debug Network Adapter', '^Microsoft Teredo', '^Packet Scheduler Miniport', '^VMware Virtual', '^vmxnet', 'VirtualBox', '^Bluetooth Device', '^RAS Async Adapter', 'USB')  -join "|" 
			$NetworkAdapterList = New-Object -TypeName System.Collections.ArrayList
			$NetworkAdapterConfigurations = Get-WmiObject -Class "Win32_NetworkAdapterConfiguration" -ErrorAction Stop
			foreach ($NetworkAdapterConfiguration in $NetworkAdapterConfigurations) {
				if ($NetworkAdapterConfiguration.Description -notmatch $KnownDescriptionPattern) {
					$NetworkAdapterList.Add(($NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true } | Select-Object -Property @{ L = "DeviceID"; E = { $_.Index } }, DNSDomain, DefaultIPGateway, DHCPServer, IPEnabled, PhysicalAdapter, Manufacturer, Description)) | Out-Null
				}
			}
			$VPNConnection = $NetworkAdapterList | Where-Object { $_.Description -match "Fortinet|Cisco AnyConnect|Juniper|Check Point|SonicWall|F5 Access|Palo Alto|Pulse Secure|Zscaler" }
			if ($VPNConnection -ne $null) {
				Write-CMLogEntry -Value "$($LogDescription) VPN connection detected on adapter '$($VPNConnection.Description)'" -Severity 2
				$VPNConnectionEstablished = $true
			}
			else {
				Write-CMLogEntry -Value "$($LogDescription) VPN connection was not detected" -Severity 1
			}

			# Validate that built-in VPN connection is not connected
			$VPNConnections = Get-VpnConnection
			if ($VPNConnections -ne $null) {
				foreach ($VPNConnection in $VPNConnections) {
					if ($VPNConnection.ConnectionStatus -notlike "Disconnected") {
						Write-CMLogEntry -Value "$($LogDescription) Built-in VPN connection '$($VPNConnection.Name)' is connected" -Severity 2
						$VPNConnectionEstablished = $true
					}
					else {
						Write-CMLogEntry -Value "$($LogDescription) Built-in VPN connection '$($VPNConnection.Name)' is disconnected" -Severity 1
					}
				}				
			}
			else {
				Write-CMLogEntry -Value "$($LogDescription) No built-in VPN connections detected" -Severity 1
			}

			if ($VPNConnectionEstablished -eq $false) {
				$TSEnvironment.Value("OSDPLVPNPass") = $true
			}
			else {
				$TSEnvironment.Value("OSDPLVPNPass") = $false
			}

			Write-CMLogEntry -Value "$($LogDescription) OSDPLVPNPass variable has value: $($TSEnvironment.Value("OSDPLVPNPass"))" -Severity 1
		}
		catch [System.Exception] {
			Write-Warning -Message "$($LogDescription) An error occurred while checking for an established VPN connection. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; break
		}
	}	
}
