<#
.SYNOPSIS
    This script is used to gather data from ConfigMgr using a SQL Query and then saves that information to a CSV file. The data can then be picked up by another agent
    and or compressed and e-mailed.

.DESCRIPTION
	Run several functions to gather data. Remove reports that are old and log the creation of the data. 	

.PARAMETER Param
    There are currently no required pararmeters to run this report. If you wish to modify this script you can do so by changing the SQL query content in the invoke-reportcommand.

.EXAMPLE
	The script is static and is simply called by a scheduled task.

.NOTES
    FileName:    get-SQLDataPowerShell.PS1
    Author:      Jordan Benzing
    Contact:     @JordanTheItGuy
    Created:     2018-12-4
    Updated:     2018-12-4

    Version history:
    1.0.0 - (2018-12-04) Script created
    1.0.1 - (2018-12-04) Implemented logging - impelmented more testing implemented auto cleanup of logs and reports
    1.0.2 - (2018-12-06) Removed E-mail stuff to simply save to a file share removed saving it daily and zipping

    License:

    The MIT License (MIT)

    Copyright (c) 2018 Jordan Benzing

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
#>

############################################
#region ReportCollection
function Invoke-ReportCommand
{
param
	(
		[Parameter(Mandatory = $False)]
		[string]$ServerName,
		[Parameter(Mandatory = $False)]
        [string]$DataBaseName
    )
    Write-Log "Setting the CSV Path to export the Data..."
    $DAILYCSVPATH = 'C:\SCRIPTS\REPORTS\' + (Get-Date).ToString('MM-dd-yyyy') + '.CSV'
    #Sets the path to where you want the report to be sent to this could be turned into a parameter change as needed. 
    Write-Log "Succesfully set all of the path locations now validating those paths actually exist"
    Write-Log -Message "Invoking SQL Commands to retrieve information"
    #The below command is the invoke SQL command that is then called this is the important part if you want to change
    #What data is going to be returned simply replace the content below with your SQL Query inside of the Double Quotes.
    Invoke-Sqlcmd -ServerInstance $ServerName -Database $DataBaseName -Query "With T1 as (
        select * from v_GS_NETWORK_ADAPTER
        where ProductName0 like '%broadband%'
        )
        Select distinct v_R_System.Name0 as 'Name'
            , v_GS_COMPUTER_SYSTEM.Manufacturer0 as 'Manufacturer'
            , v_GS_COMPUTER_SYSTEM.Model0 as 'Model'
            , v_GS_PC_BIOS.SerialNumber0 as 'Serial Number'
            , v_GS_PROCESSOR.Name0 as 'Processor'
            , v_GS_OPERATING_SYSTEM.TotalVisibleMemorySize0 as 'RAM in MB'
            , v_GS_LOGICAL_DISK.DeviceID0 as 'Drive Letter'
            , (v_GS_LOGICAL_DISK.Size0/1000) as 'Drive Size'
        --    , v_R_System.Client_Version0 as 'Client'
            , T1.ProductName0 as 'Cellular'
           from v_R_System
        left outer join v_GS_OPERATING_SYSTEM on v_R_System.ResourceID = v_GS_OPERATING_SYSTEM.ResourceID
        Left Outer Join v_GS_PC_BIOS on v_R_System.ResourceID = v_GS_PC_BIOS.ResourceID
        LEFT outer Join v_GS_PROCESSOR on v_R_System.ResourceID = v_GS_PROCESSOR.ResourceID
        LEFT OUTER JOIN v_GS_COMPUTER_SYSTEM on v_R_System.ResourceID = v_GS_COMPUTER_SYSTEM.ResourceID
        LEFT OUTER JOIN V_GS_System on V_r_system.ResourceID = V_GS_System.REsourceID
        LEFT OUTER JOIN v_GS_LOGICAL_DISK on v_R_System.ResourceID = v_GS_LOGICAL_DISK.ResourceID
        LEFT OUTER JOIN T1 on v_R_System.ResourceID = T1.ResourceID
        Where v_GS_SYSTEM.SystemRole0 = 'Workstation' and v_GS_COMPUTER_SYSTEM.Model0 not like '%Virtual%' and v_GS_LOGICAL_DISK.DeviceID0 = 'C:'
        " | Export-Csv -NoTypeInformation -Path $DAILYCSVPATH
    #The above query is then stored into a varibale and logged that its completed before being returned back.
    Write-Log -Message "Completed the data retrieval"
 }
function Remove-OldReports
#This is a function to remove any of the old reports that are older in nature in a path location.
{
    Param
    (
        [Parameter(Mandatory = $True)]
        [string]$DaysOld,
        [Parameter(Mandatory = $True)]
        [string]$Path
    )
    try 
    {
        $FilesToRemove = Get-ChildItem -File -Recurse -Path $Path -Force | Where-Object {$_.LastWriteTime -le (Get-Date).AddDays($DaysOld)} | Select-Object Name,LastWriteTime,FullName
        #Gets the list of files that meet the criteria specified in the parameter set. 
        ForEach($File in $FilesToRemove)
            {
                Write-Log -LogLevel 2 -Message "File was found that met the removal criteria $($File.Name) will be removed"
                #Logs what item is about to be removed
                Remove-Item -Path $File.FullName
                #Removes the item and then logs it was succefully removed.
                Write-Log -Message "File $($File.Name) was removed succesfully"
            }

    }
    catch
    {
        write-log -LogLevel 3 'Failed to run the removal'
        #Logs event for failure to remove. 
    }
}   

#Endregion ReportCollection
############################################

############################################
#region HelperFunctions
Function Start-Log
#Set global variable for the write-log function in this session or script.
{
	[CmdletBinding()]
    param (
    [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
	[string]$FilePath
 	)
    try
    	{
			#Confirm the provided destination for logging exists if it doesn't then create it.
			if (!(Test-Path $FilePath))
				{
	    			## Create the log file destination if it doesn't exist.
	    			New-Item $FilePath -Type File | Out-Null
				}
				## Set the global variable to be used as the FilePath for all subsequent Write-Log
				## calls in this session
				$global:ScriptLogFilePath = $FilePath
    	}
    catch
    {
		#In event of an error write an exception
        Write-Error $_.Exception.Message
    }
}

Function Write-Log
#Write the log file if the global variable is set
{
	param (
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [Parameter()]
    [ValidateSet(1, 2, 3)]
    [string]$LogLevel = 1
   )
    $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
    $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $LogLevel
    #$LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "$($MyInvocation.ScriptName | Split-Path -Leaf)", $LogLevel
    $Line = $Line -f $LineFormat
    Add-Content -Value $Line -Path $ScriptLogFilePath
    if($writetoscreen -eq $true){
        switch ($LogLevel)
        {
            '1'{
                Write-Verbose $Message -ForegroundColor Gray
                }
            '2'{
                Write-Verbose $Message -ForegroundColor Yellow
                }
            '3'{
                Write-Verbose $Message -ForegroundColor Red
                }
            Default {}
        }
    }

    if($writetolistbox -eq $true){
        $result1.Items.Add("$Message")
    }
}

function Test-Module
#Function that is designed to test a module if it is loaded or not. 
{
    [CMdletbinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [String]$ModuleName,
        [Parameter(Mandatory = $false)]
        [bool]$Remediate
    )
    If(Get-Module -Name $ModuleName)
    #Checks if the module is currently loaded and if it is then return true.
    {
        Write-Log -Message "The module was already loaded return TRUE"
        return $true
    }
    If((Get-Module -Name $ModuleName) -ne $true)
    #Checks if the module is NOT loaded and if it's not loaded then check to see if remediation is requested. 
    {
        Write-Log -Message "The Module was not already loaded evaluate if remediation flag was set"
        if($Remediate -eq $True)
        #If the remediation flag is selected then attempt to import the module. 
        {
            try 
            {
                    Write-Log -Message "Remediation flag WAS set now attempting to import module $ModuleName"
                    Import-Module -Name $ModuleName
                    Write-Log -Message "Succesfully improted the module $ModuleName"
                    Return $true
            }
            catch 
            {
                Write-Log -LogLevel 3 -Message "Failed to import the module $ModulName"
                break
            }
        }
        else {
            #Else return the fact that it's not applicable and return false from the execution.
            {
                Return $false
            }
        }
    }
}
#Endregion HelperFunctions
############################################

############################################
#Region PerformActions
$LogPath = "C:\scripts\Logs\" + (Get-Date -UFormat "%m-%d-%Y-%S") + "_" + $MyInvocation.MyCommand.Name
#Sets the log path for where you want to generate logs - Modify the string at the start C:\scripts\Logs to change the directory reccomended ot not change the format of the file name.
$LogFile = $LogPath + ".log"
#Appends the .LOG to the end of the path staatement for use when referencing the file v.s. the log location itself.
Start-Log -FilePath $LogFile
#Sets the loging location globally for the duration of the session
Write-Log -Message "Starting Data Gather"
#Logs the start of the process
Write-Log -Message "Evaluating if the SQL powershell cmdlets are loaded"
#Begins evaluation to see if we can run this.
if(Test-Module -ModuleName SQLPS -Remediate $true)
{
    write-log -Message "All requirements have been met now executing the data gather step"
    Invoke-ReportCommand -ServerName $ENV:COMPUTERNAME -DataBaseName CM_P01
    #This actually performs the data generation - change the database to match the CM database future development may automatically determine the database name.
    Write-Log -Message "Data Gathering complete"
}
#remote reprots older than 7 days and logs older than 7 days.
Remove-OldReports -DaysOld '-7' -Path "C:\Scripts\logs\" 
Remove-OldReports -DaysOld '-7' -Path "C:\Scripts\Reports\"
Write-Log -Message "Cleanup has been completed now exiting"
#Endregion PerformActions
############################################