<#	
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2017 v5.4.144
	 Created on:   	2/23/2018 11:13 AM
	 Created by:   	Jordan Benzing
	 Organization: 	
	 Filename:     	CMOperations.psm1
	-------------------------------------------------------------------------
	 Module Name: CMOperations
	===========================================================================
#>

############################################
#region TriggerClientActions

function Start-SoftwareUpdateScan
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$ComputerName,
		[Parameter(Mandatory = $False)]
		[switch]$ConnectionTest
	)
	if ($ConnectionTest)
	#If the connection test switch is set start the process to test the network connectivity and run the function. 
	{
		if (Test-Connectivity -ComputerName $ComputerName)
		#Validates that the machine can be conneted to. If it passes will enter the try statement to start a software update Scan Cycle.
		{
			try
			{
				Write-Verbose -message "Attempting to start a Software Update Scan Cycle"
				Invoke-WmiMethod -ComputerName $ComputerName -ErrorAction Stop -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000113}" | Out-Null
				#Uses the invoke command to start scheduled action 113 - Software Update Scan Cycle
				Write-Verbose -Message "The computer has started a software update scan cycle."
				#When verbose flag is triggered notifies the user that the cycle has been started.
			}
			Catch
			{
				throw "$ComputerName failed to start software update Scan"
				#Catch and throw an error statement if anything goes wrong. 
			}
		}
	}
	else
	#In the event a connection test is NOT requested - attempt to perform the action without triggering a connection test. Not reccomended.
	{
		try
		{
			Write-Verbose -message "Attempting to start a Software Update Scan Cycle"
			Invoke-WmiMethod -ComputerName $ComputerName -ErrorAction Stop -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000113}" | Out-Null
			#Uses the invoke command to start scheduled action 113 - Software Update Scan Cycle
			Write-Verbose -Message "The computer has started a software update scan cycle."
			#When verbose flag is triggered notifies the user that the cycle has been started.
		}
		Catch
		{
			throw "$ComputerName failed to start software update Scan"
			#Catch and throw an error statement if anything goes wrong. 
		}
	}
}

function Start-HardwareInventoryScan
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$ComputerName,
		[Parameter(Mandatory = $False)]
		[switch]$ConnectionTest
	)
	if ($ConnectionTest)
	#If the connection test switch is set start the process to test the network connectivity and run the function. 
	{
		if (Test-Connectivity -ComputerName $ComputerName)
		#Validates that the machine can be conneted to. If it passes will enter the try statement to start a Hardware Inventory Scan
		{
			try
			{
				Write-Verbose -Message "Attempting to invoke a hardware inventory cycle"
				Invoke-WMIMethod -ComputerName $ComputerName -ErrorAction Stop -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000001}" | Out-Null
				#Uses the invoke command to start scheduled action 001 - Hardware Inventory Scan Cycle
				Write-Verbose -Message "The computer has started a hardware inventory cycle."
				#When verbose flag is triggered notifies the user that the cycle has been started.
			}
			Catch
			{
				throw "$ComputerName failed to start hardware inventory cycle"
				#Catch and throw an error statement if anything goes wrong. 
			}
		}
	}
	else
	#In the event a connection test is NOT requested - attempt to perform the action without triggering a connection test. Not reccomended.
	{
		try
		{
			Write-Verbose -Message "Attempting to invoke a hardware inventory cycle."
			Invoke-WMIMethod -ComputerName $ComputerName -ErrorAction Stop -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000001}" | Out-Null
			#Uses the invoke command to start scheduled action 001 - Hardware Inventory Scan Cycle
			Write-Verbose -Message "The computer has started a hardware inventory cycle."
			#When verbose flag is triggered notifies the user that the cycle has been started.
		}
		Catch
		{
			throw "$ComputerName failed to start a hardware inventory cycle"
			#Catch and throw an error statement if anything goes wrong. 
		}
	}
}

#endregion TriggerClientActions
############################################

############################################
#region SoftwareUpdateActions

function Get-UpdatesInSoftwareCenter
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[string]$ComputerName,
		[Parameter(Mandatory = $False)]
		[switch]$ConnectionTest
		
	)
	If ($ConnectionTest)
	#If the connection test switch is set start the process to test the network connectivity and run the function. 
	{
		If (Test-Connectivity -ComputerName $ComputerName)
		#If the computer passes the connection test enter the if statement to try to get the updates that are currently available to install in software center. 
		{
			try
			{
				Write-Verbose "Connecting to $ComputerName to query for updates in Software Center"
				Get-WmiObject -ComputerName $ComputerName -ErrorAction Stop -Query 'SELECT * FROM CCM_SoftwareUpdate' -Namespace ROOT\ccm\ClientSDK -Verbose:$false | ft ArticleID, Name -AutoSize
				#Connects to the WMI Client SDK namespace and returns teh updates that are currently pending installation or are displayed in software center.
			}
			catch
			{
				Throw "Error with returning any data from $ComputerName"
				#Catch Error in the event something goes wrong connecting to WMI. 
			}
		}
	}
	else
	#If a connection test switch was NOT set this will run the process without performing a connection test to device. This is not recccommended.
	{
		Write-Verbose "Connecting to $ComputerName to query for updates in Software Center"
		Get-WmiObject -ComputerName $ComputerName -Query 'SELECT * FROM CCM_SoftwareUpdate' -Namespace ROOT\ccm\ClientSDK -Verbose:$false | ft ArticleID, Name -AutoSize
		#Connects to the WMI Client SDK namespace and returns the updates that are currently pending installation or are displayed in software center.
	}
}

function Install-UpdatesInSoftwareCenter
{
	param (
		[Parameter(Mandatory = $true)]
		[String]$ComputerName,
		[Parameter(Mandatory = $false)]
		[switch]$AllUpdates,
		[Parameter(Mandatory = $false)]
		[array]$ArticleID,
		[Parameter(Mandatory = $False)]
		[switch]$ConnectionTest
	)
	If ($ConnectionTest)
	#If the connection test switch is set start the process to test the network connectivity and run the function. 
	{
		If (Test-Connectivity -ComputerName $ComputerName)
		#If the computer passes the connection test enter the if statement and based on parameters install the missing software updates.
		{
			if ($AllUpdates)
			#The All Updates Switch is flagged then enter and try
			{
				try
				{
					Write-Verbose "All Updates was selected for $ComputerName attempting to install all available updates in software center"
					$Updates = [System.Management.ManagementObject[]](Get-WmiObject -ComputerName $ComputerName -ErrorAction Stop -Query 'SELECT * FROM CCM_SoftwareUpdate' -Namespace ROOT\ccm\ClientSDK -Verbose:$false)
					#build an array in the variable $Updates that contains all udpate articles
					([wmiclass]"\\$ComputerName\ROOT\ccm\ClientSDK:CCM_SoftwareUpdatesManager").InstallUpdates([System.Management.ManagementObject[]]$Updates) | Out-Null
					#Using the older WMI methodology run the install updates wmi method to install allupdates in the $updates object. 
				}
				catch
				#If an error occurs throw terminating catch event.
				{
					throw "Remote installation of updates failed."	
				}
			}
			ElseIf ($ArticleID)
			#array of articleID's provided by the user.
			{
				try
				{
					Write-Verbose "$ArticleID were selected for $ComputerName attempting to install updates"
					$Updates = [System.Management.ManagementObject[]](Get-WmiObject -ComputerName $ComputerName -ErrorAction Stop -Query 'SELECT * FROM CCM_SoftwareUpdate' -Namespace ROOT\ccm\ClientSDK -Verbose:$false) | Where-Object { $_.ArticleID -in $ArticleID }
					#build an array in the variable $Updates that contains all udpate articles that are in the articleID list provided by the user.
					([wmiclass]"\\$ComputerName\ROOT\ccm\ClientSDK:CCM_SoftwareUpdatesManager").InstallUpdates([System.Management.ManagementObject[]]$Updates) | Out-Null
					#Using the older WMI methodology run the install updates wmi method to install allupdates in the $updates object. 
				}
				catch
				#In an error occurs throw a terminating catch event.
				{
					throw "Remote installation of updates failed"	
				}
			}
		}
		
	}
	else
	#See Comments above - runs exactly the same but does not perform connection test.
	{
		if ($AllUpdates)
		{
			try
			{
				Write-Verbose "All Updates was selected for $ComputerName attempting to install all available updates in software center"
				$Updates = [System.Management.ManagementObject[]](Get-WmiObject -ComputerName $ComputerName -Query 'SELECT * FROM CCM_SoftwareUpdate' -Namespace ROOT\ccm\ClientSDK -Verbose:$false)
				#build an array in the variable $Updates that contains all udpate articles
				([wmiclass]"\\$ComputerName\ROOT\ccm\ClientSDK:CCM_SoftwareUpdatesManager").InstallUpdates([System.Management.ManagementObject[]]$Updates) | Out-Null
				#Using the older WMI methodology run the install updates wmi method to install allupdates in the $updates object. 
			}
			catch
			#If an error occurs throw terminating catch event.
			{
				throw "Remote installation of updates failed."
			}
		}
		ElseIf ($ArticleID)
		{
			try
			{
				Write-Verbose "$ArticleID were selected for $ComputerName attempting to install updates"
				$Updates = [System.Management.ManagementObject[]](Get-WmiObject -ComputerName $ComputerName -Query 'SELECT * FROM CCM_SoftwareUpdate' -Namespace ROOT\ccm\ClientSDK -Verbose:$false) | Where-Object { $_.ArticleID -in $ArticleID }
				#build an array in the variable $Updates that contains all udpate articles that are in the articleID list provided by the user.
				([wmiclass]"\\$ComputerName\ROOT\ccm\ClientSDK:CCM_SoftwareUpdatesManager").InstallUpdates([System.Management.ManagementObject[]]$Updates) | Out-Null
				#Using the older WMI methodology run the install updates wmi method to install allupdates in the $updates object. 
			}
			catch
			#If an error occurs throw terminating catch event.
			{
				throw "Remote installation of updates failed"
			}
		}
	}
}

#endregion SoftwareUpdateActions
############################################

############################################
#region GetClientInformation

function Get-NextAvailableMW
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[string]$ComputerName,
		[Parameter(Mandatory = $False)]
		[switch]$ConnectionTest,
		[Parameter(Mandatory = $False)]
		[switch]$SoftwareMW,
		[Parameter(Mandatory = $False)]
		[switch]$AllProgramsMW,
		[Parameter(Mandatory = $False)]
		[switch]$ProgramsMW
		
		
	)
	if ($ConnectionTest)
	#If the connection test switch is set start the process to test the network connectivity and run the function. 
	{
		if (Test-Connectivity -ComputerName $ComputerName)
		#If the test connection is passed enter the step to look for maintenance window switches are detected.
		{
			if ($AllProgramsMW)
			#If the All Programs MW is selected find the next available ALL PROGRAMS maintenance window.
			{
				try
				{
					Write-Verbose -Message "Attempting to connect to $ComputerName and retrieve next available ALL PROGRAMS MAINTENANCE WINDOW"
					$Window = Get-WmiObject -ComputerName $ComputerName -ErrorACtion Stop -Namespace root\ccm\clientsdk -ClassName CCM_ServiceWindow | Where-Object{ $_.type -eq 1 } | ForEach-Object{ [Management.ManagementDateTimeConverter]::ToDateTime($_.StartTime) } | Sort $_.StartTime | Select-Object -First 1
					#Gets the Maintenance Window time from WMI And converts it to a date time object. 
					$Message = "Next available ALL PROGRAMS window for $ComputerName is " + $Window
					$Message
					#Returns and displays the window information to the screen.
				}
				catch
				#catches and throws a terminating error if the remote WMI call fails.
				{
					throw "An Error has occured retriving window information"
				}
			}
			if ($SoftwareMW)
			#if the SoftwareMW is selected finds the next available software maintenance window for the device. 
			{
				try
				{
					Write-Verbose -Message "Attempting to connect to $ComputerName and retrieve next available SOFTWARE UPDATES MAINTENANCE WINDOW"
					$Window = Get-WmiObject -ComputerName $ComputerName -Namespace root\ccm\clientsdk -ClassName CCM_ServiceWindow | Where-Object{ $_.type -eq 4 } | ForEach-Object{ [Management.ManagementDateTimeConverter]::ToDateTime($_.StartTime) } | Sort $_.StartTime | Select-Object -First 1
					#Gets the next available maintenance window from WMI of type Software Update and converts it to a datetime object
					$Message = "Next available SOFTWARE UPDATES MAINTENANCE window for $ComputerName is " + $Window
					$Message
					#Returns and displays the window information to the screen.
				}
				catch
				#catches and throws a terminating error if the remote WMI call fails.
				{
					throw "An Error has occured retriving window information"
				}
			}
			if ($ProgramsMW)
			#if the ProgramsMW is selected finds the next available Programs window for the device. 
			{
				try
				{
					Write-Verbose -Message "Attempting to connect to $ComputerName and retrieve next available PROGRAMS MAINTENANCE WINDOW"
					$window = Get-WmiObject -ComputerName $ComputerName -Namespace root\ccm\clientsdk -ClassName CCM_ServiceWindow | Where-Object{ $_.type -eq 2 } | ForEach-Object{ [Management.ManagementDateTimeConverter]::ToDateTime($_.StartTime) } | Sort $_.StartTime | Select-Object -First 1
					$Message = "Next available PROGRAMS MAINTENANCE window for $ComputerName is " + $Window
					$Message
				}
				catch
				{
					throw "An Error has occured retriving window information"
				}
			}
			if($SoftwareMW -eq $false -and $AllProgramsMW -eq $false -and $ProgramsMW -eq $false)
			{
				try
				{
					Write-Verbose -Message "Attempting to connect to $ComputerName and retrieve next available MAINTENANCE WINDOW OF ANY TYPE"
					$Window = Get-WmiObject -ComputerName $ComputerName -Namespace root\ccm\clientsdk -ClassName CCM_ServiceWindow | Where-Object{ $_.type -eq 2 -or $_.Type -eq 1 -or $_.Type -eq 4 } | ForEach-Object{ [Management.ManagementDateTimeConverter]::ToDateTime($_.StartTime) } | Sort $_.StartTime | Select-Object -First 1
					#Gets the next available Programs Maintenance window from WMI and converts it to a datetime object
					$Message = "Next available MAINTEANNCE window of any type for $ComputerName is " + $Window
					$Message
					#Returns and displays the window information to the screen.
				}
				catch
				#catches and throws a terminating error if the remote WMI call fails.
				{
					throw "An Error has occured retriving window information"
				}
			}
		}
	}
	else
	#See above comments. Performs same actions without running the connection test first. Might later be created as a sub function that is called. 
	{
		if ($AllProgramsMW)
		{
			try
			{
				Write-Verbose -Message "Attempting to connect to $ComputerName and retrieve next available ALL PROGRAMS MAINTENANCE WINDOW"
				$Window = Get-WmiObject -ComputerName $ComputerName -Namespace root\ccm\clientsdk -ClassName CCM_ServiceWindow | Where-Object{ $_.type -eq 1 } | ForEach-Object{ [Management.ManagementDateTimeConverter]::ToDateTime($_.StartTime) } | Sort $_.StartTime | Select-Object -First 1
				$Message = "Next available ALL PROGRAMS window for $ComputerName is " + $Window
				$Message
			}
			catch
			{
				throw "An Error has occured retriving window information"
			}
		}
		if ($SoftwareMW)
		{
			try
			{
				Write-Verbose -Message "Attempting to connect to $ComputerName and retrieve next available SOFTWARE UPDATES MAINTENANCE WINDOW"
				$Window = Get-WmiObject -ComputerName $ComputerName -Namespace root\ccm\clientsdk -ClassName CCM_ServiceWindow | Where-Object{ $_.type -eq 4 } | ForEach-Object{ [Management.ManagementDateTimeConverter]::ToDateTime($_.StartTime) } | Sort $_.StartTime | Select-Object -First 1
				$Message = "Next available SOFTWARE UPDATES MAINTENANCE window for $ComputerName is " + $Window
				$Message
			}
			catch
			{
				throw "An Error has occured retriving window information"
			}
		}
		if ($ProgramsMW)
		{
			try
			{
				Write-Verbose -Message "Attempting to connect to $ComputerName and retrieve next available PROGRAMS MAINTENANCE WINDOW"
				$window = Get-WmiObject -ComputerName $ComputerName -Namespace root\ccm\clientsdk -ClassName CCM_ServiceWindow | Where-Object{ $_.type -eq 2 } | ForEach-Object{ [Management.ManagementDateTimeConverter]::ToDateTime($_.StartTime) } | Sort $_.StartTime | Select-Object -First 1
				$Message = "Next available PROGRAMS MAINTENANCE window for $ComputerName is " + $Window
				$Message
			}
			catch
			{
				throw "An Error has occured retriving window information"
			}
		}
		if ($SoftwareMW -eq $false -and $AllProgramsMW -eq $false -and $ProgramsMW -eq $false)
		{
			try
			{
				Write-Verbose -Message "Attempting to connect to $ComputerName and retrieve next available MAINTENANCE WINDOW OF ANY TYPE"
				$Window = Get-WmiObject -ComputerName $ComputerName -Namespace root\ccm\clientsdk -ClassName CCM_ServiceWindow | Where-Object{ $_.type -eq 2 -or $_.Type -eq 1 -or $_.Type -eq 4 } | ForEach-Object{ [Management.ManagementDateTimeConverter]::ToDateTime($_.StartTime) } | Sort $_.StartTime | Select-Object -First 1
				$Message = "Next available MAINTEANNCE window of any type for $ComputerName is " + $Window
				$Message
			}
			catch
			{
				throw "An Error has occured retriving window information"
			}
		}
	}
}

function Get-LastSoftwareUpdateScan
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$ComputerName,
		[Parameter(Mandatory = $False)]
		[switch]$ConnectionTest
	)
	if ($ConnectionTest)
	#If the connection test switch is set start the process to test the network connectivity and run the function. 
	{
		if (Test-Connectivity -ComputerName $ComputerName)
		#If the connect test is passed enters the IF statement and trys to run the function to get the last software Update Scan Cycle run time and location run against.
		{
			try
			{
				Write-Verbose -Message "Attempting to gather Last Scanned WSUS Server name and time"
				$LastScanTime = Get-WmiObject -ComputerName $ComputerName -ErrorAction Stop -Namespace "Root\ccm\SCanAgent" -ClassName CCM_ScanUpdateSourceHistory | ForEach-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.LastCompletionTime) }
				#Connects to WMI And returns the date time object of the last time a WSUS scan was run. 
				$LastServerScanned = Get-WmiObject -computer $ComputerName -ErrorAction Stop -Namespace root\ccm\softwareupdates\wuahandler -Class CCM_updatesource | Select-Object ContentLocation
				#Connects to WMI and returns the last server that a software update scan was run against. 
				$Message = "Your computer $Computername last scanned at " + $LastScanTime + " against the server " + $LastServerScanned.ContentLocation
				$Message
				#Returns the message to the screen with the information of last run time and server name.
			}
			catch
			#Cathes terminating errors and throws an event.
			{
				throw "Something went wrong collecting the Software Update Scan Time"
			}
		}
	}
	else
	#if the conection test was not called for runs the function without running the connection test. - Can be optimized later by creating wrapper/action function.
	{
		try
		{
			Write-Verbose -Message "Attempting to gather Last Scanned WSUS Server name and time"
			$LastScanTime = Get-WmiObject -ComputerName $ComputerName -ErrorAction Stop -Namespace "Root\ccm\SCanAgent" -ClassName CCM_ScanUpdateSourceHistory | ForEach-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.LastCompletionTime) }
			#Connects to WMI And returns the date time object of the last time a WSUS scan was run. 
			$LastServerScanned = Get-WmiObject -computer $ComputerName -erroraction Stop -Namespace root\ccm\softwareupdates\wuahandler -Class CCM_updatesource | Select-Object ContentLocation
			#Connects to WMI and returns the last server that a software update scan was run against.
			$Message = "Your computer $Computername last scanned at " + $LastScanTime + " against the server " + $LastServerScanned.ContentLocation
			$Message
		}
		catch
		{
			throw "Something went wrong collecting the Software Update Scan Time"
		}
	}
}

function Get-LastHardwareScan
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$ComputerName,
		[Parameter(Mandatory = $False)]
		[switch]$ConnectionTest
	)
	if ($ConnectionTest)
	#If the connection test switch is set start the process to test the network connectivity and run the function. 
	{
		if (Test-Connectivity -ComputerName $ComputerName)
		#If the connection test function is passed enter the function to attempt to get the last time a hardware scan was run. 
		{
			try
			{
				Write-Verbose -Message "Attempting to connect and retrieve the instance for Hardware Inventory Information"
				$obj = Get-WmiObject -computername $ComputerName -Namespace "root\ccm\invagt" -Class InventoryActionStatus -ErrorAction Stop | Where-Object { $_.InventoryActionID -eq "{00000000-0000-0000-0000-000000000001}" } | select PsComputerName, LastCycleStartedDate, LastReportDate
				#Get the WMI Instance for the hardware scan information. 
				Write-Verbose -Message "Retrieved WMI Instance for Hardware Scan Information"
				$LastHWRun = $ComputerName + " last attempted Hardware inventory on " + [Management.ManagementDateTimeConverter]::ToDateTime($obj.LastCycleStartedDate)
				#Convert the instance information into a date time object and send the data back to the screen.
				$LastHWRun
			}
			Catch
			#In the event of an error terminate and throw.
			{
				throw "Unable to get last hardware scan run time"
			}
		}
		else
		{
			throw "Failed collection test to remote machine"
		}
	}
	else
	#Same function as above but tun without connection test - could be optimized at a later date using a 'rapper' function.
	{
		try
		{
			Write-Verbose -Message "Attempting to connect and retrieve the instance for Hardware Inventory Information"
			$obj = Get-WmiObject -ComputerName $ComputerName -Namespace "root\ccm\invagt" -Class InventoryActionStatus -ErrorAction Stop | Where-Object { $_.InventoryActionID -eq "{00000000-0000-0000-0000-000000000001}" } | select PsComputerName, LastCycleStartedDate, LastReportDate
			Write-Verbose -Message "Retrieved WMI Instance for Hardware Scan Information"
			$LastHWRun = $ComputerName + " last attempted Hardware inventory on " + [Management.ManagementDateTimeConverter]::ToDateTime($obj.LastCycleStartedDate)
			Write-Host $LastHWRun
		}
		Catch
		{
			throw "Unable to get last hardware scan run time"
		}
	}
}

#endregion GetClientInformation
############################################

############################################
#region HelperFunctions
function Test-Connectivity
#Test Connection function. All network tests should be added to this for a full connection test. Returns true or false.
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[string]$ComputerName
	)
	Try
	#Try each connection test. If there is a connection test that you do not want to use remove it by commenting out the line.
	{
		Test-Ping -ComputerName $ComputerName -ErrorAction Stop
		Test-AdminShare -ComputerName $ComputerName -ErrorAction Stop
		Test-WinRM -ComputerName $ComputerName -ErrorAction Stop
		Write-Verbose -Message "$ComputerName has passed all connection tests"
		return $true
	}
	CATCH
	{
		$ConnectionStatus = $false
		Write-Verbose "$ComputerName failed a connection test."
		return $false
	}
}

function Test-Ping
#Test ping for computer.
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[string]$ComputerName
	)
	$PingTest = Test-Connection -ComputerName $ComputerName -BufferSize 8 -Count 1 -Quiet
	If ($PingTest)
	{
		Write-Verbose "The Ping test for $ComputerName has PASSED"
	}
	Else
	{
		Write-Verbose "$ComputerName failed ping test"
		throw [System.Net.NetworkInformation.PingException] "$ComputerName failed ping test."
	}
}

function Test-AdminShare
#Test Conection to admin C$ share.
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[string]$ComputerName
	)
	$AdminShare = "\\" + $ComputerName + "\C$"
	$AdminAccess = Test-Path -Path $AdminShare -ErrorAction Stop
	if ($AdminAccess)
	{
		Write-Verbose "The admin share connection test $ComputerName has PASSED"
		$ConnectionStatus = $true
	}
	Else
	{
		Write-Verbose "$ComputerName admin share not found"
		throw [System.IO.FileNotFoundException] "$ComputerName admin share not found"
		
	}
}

function Test-WinRM
#Test WinRM.
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[string]$ComputerName
	)
	Try
	{
		Test-WSMan -computername $ComputerName -ErrorAction Stop
		Write-Verbose "The WINRM check for $ComputerName has PASSED"
	}
	Catch
	{
		throw [System.IO.DriveNotFoundException] "$ComputerName cannot be connected to via WINRM"
	}
}
#endregion HelperFunctions
############################################


