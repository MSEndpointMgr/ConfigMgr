#region
<#

.SYNOPSIS 
Creates a Maintenace Window in Configuration Manager.

.DESCRIPTION 
This script will create Maintenace Windows in Configuration Manager 2012 (or 2007).
It will create a non-reoccuring Maintenace Window with the specified options.
There is also an option to create Maintenace Windows based on "Patch Tuesday" or with 
an offset of days from "Patch Tuesday". This is useful when for example second Thursday of a month
occurs before second Tuesday (see may 2013 as an example).

.PARAMETER SiteCode
    Sitecode for SCCM
.PARAMETER MaintenanceWindowName
    This is what the Maintenance Window will be called.
.PARAMETER AddMaintenanceWindowNameMonth
    If this is used the month number, month name and year will be added to the Maintenance Window Name
    For example: <MaintenanceWindowName> "01 january 2013"
    
.PARAMETER MaintenanceWindowDescription
    Optional, this is the description of the Maintenace Window (Will be overwritten if any changes is done in the GUI).
.PARAMETER CollectionID
    SCCM Collection ID where the Maintenace Window will be created
.PARAMETER patchTuesday
    If this is used date will based on patch tuesday. If used without <-nextmonth> Maintenace Windows will be created for every month.
.PARAMETER nextmonth
    Limits the creation of Maintenace Windows to one which will be the following month.
.PARAMETER adddays
    This is used together with patchTuesday to create an offset counting from patch Tuesday. For example if you want to create a Maintenace Window
    every Thursday after patch Tuesday enter "-adddays 2"
.PARAMETER StartYear
    Year for Maintenace Window to be created
.PARAMETER StartMonth
    Month for Maintenace Window to be created
.PARAMETER StartDay
    Day for Maintenace Window to be created
.PARAMETER StartHour
    Hour for Maintenace Window to be created
.PARAMETER StartMinute
    Minute for Maintenace Window to be created
.PARAMETER HourDuration
    Defines how many hours the Maintenace Window will last, maximum 24 hours
.PARAMETER MinuteDuration
    Define how many minutes Maintenace Window will last. Total lenght of the Maintenace Window must be at least 5 minutes.
.PARAMETER IsGMT
	Enables the GMT option (Coordinated Universal Time UTC) on the Maintenace Window
.PARAMETER SWType
    Sets the type of Maintainence Windows, default is General. Valid values are General, Updates and OSD

.EXAMPLE
New-CMMaintenanceWindow.ps1 -SiteCode EVL -MaintenanceWindowName "MW Patch Tuesday " -AddMaintenanceWindowNameMonth -CollectionID "EVL00001" -patchTuesday -nextmonth -StartHour 21 -StartMinute 0 -HourDuration 4 -MinuteDuration 0

This will create a Maintenance Window for next month on the same day as Patch Tuesday starting 21:00 and lasting 4 hours.

.EXAMPLE
New-CMMaintenanceWindow.ps1 -SiteCode EVL -MaintenanceWindowName "MW Patch Tuesday " -AddMaintenanceWindowNameMonth -CollectionID "EVL00001" -patchTuesday -adddays 9 -StartYear -StartHour 21 -StartMinute 0 -HourDuration 4 -MinuteDuration 0

This will create a Maintenance Window for every month 2014 on the second Thursday after Patch Tuesday starting 21:00 and lasting 4 hours.


.EXAMPLE 
New-CMMaintenanceWindow.ps1 -SiteCode EVL -MaintenanceWindowName "MW Patch Window 8th April" -CollectionID "EVL00001" -StartYear 2013 -StartMonth 04 -StartDay 08 -StartHour 20 -StartMinute 30 -HourDuration 2 -MinuteDuration 30

This will create a Maintenance Window for 2013-04-08 starting 20.30 and lasting 2 hours and 30 minutes.

.EXAMPLE 
New-CMMaintenanceWindow.ps1 -SiteCode EVL -MaintenanceWindowName "MW Patch Window Today" -CollectionID "EVL00001" -StartHour 20 -StartMinute 30 -HourDuration 2 -MinuteDuration 30

This will create a Maintenance Window for today starting 20.30 and lasting 2 hours and 30 minutes.

.NOTES 
PowerShell Source File -- New-CMMaintenanceWindow.ps1

AUTHOR: 	Mattias Benninge
MODIFIED BY: 
COMPANY: 
DATE: 2013-04-28
VERSION: 04
SCRIPT LANGUAGE: PowerShell
LAST UPDATE: 
v1.1 2013-04-28 Added switch for IsGMT
v1.2 2014-12-19 Rewrote part of the code to solve issues when UTC convertion messed up the time and calculation of patchtuesday.
v1.3 2017-01-19 Added option to specify Maintainence Window typ.

KEYWORDS: PowerShell, SCCM, 
DESCRIPTION: 

KNOWN ISSUES: 

COMMENT: 

.LINK 
http://www.codeplex.com
		
#>
#endregion

[CmdletBinding()]
param(
	[parameter(Mandatory=$true)]
	[string]$SiteCode,
	[parameter(Mandatory=$true)]
	[string]$MaintenanceWindowName,
    [switch]$AddMaintenanceWindowNameMonth,
	[string]$MaintenanceWindowDescription,
	[parameter(Mandatory=$true, ValueFromPipeline=$true)]
	[string]$CollectionID,

	# Will create SW based on PatchTuesday
	[switch]$patchTuesday,
	[switch]$nextmonth, 
	# Will create an offset of days calculated from patch Tuesday, 
	# if this is not done sometimes for example third Thursday of the month will occur before third tuesday.
	[int]$adddays = 0,
	
    # Set values for When service windows will start, if not specified it will start at current time
	# If Patch Tuesday switch is used only $StartYear, $starthour and $startminute will be honored.
    [parameter(ValueFromPipeline=$true)] 
	[int]$StartYear = (Get-Date).Year,
	[int]$StartMonth = "{0:00}" -f (Get-Date).Month,
	[int]$StartDay = "{0:00}" -f (Get-Date).Day,
	[int]$StartHour = "{0:00}" -f (Get-Date).Hour,
    [int]$StartMinute = "{0:00}" -f (Get-Date).Minute,


    # Sets the length of the service window (min length 5 mins, max 24 hours)
    [parameter(Mandatory=$true)]
    [int]$HourDuration = 0,
    [parameter(Mandatory=$true)]
    [int]$MinuteDuration = 0,
	
	# If enabled MW will be created with GMT/UTC option
	[switch]$IsGMT,

    #Specifies the MW Type
    [Parameter(Mandatory=$false,ValueFromPipeline=$true)] 
    [ValidateSet('General','Updates','OSD')]
    [System.String]$swtype = "General"

)

#Converts $swtype (MW Type) into a valid integer
switch ($swtype)
{
    'General' {$swtypeint=1}
    'Updates' {$swtypeint=4}
    'OSD' {$swtypeint=5}
    Default {$swtypeint=1}
}

### Functions Start Here ###
function get-secondTuesdayDate {            
param(
[datetime]$date
)            
    switch ($date.DayOfWeek){            
        "Monday"    {$patchTuesdayDate = $date.AddDays(8); break}             
        "Tuesday"   {$patchTuesdayDate = $date.AddDays(7); break}             
        "Wednesday" {$patchTuesdayDate = $date.AddDays(13); break}             
        "Thursday"  {$patchTuesdayDate = $date.AddDays(12); break}             
        "Friday"    {$patchTuesdayDate = $date.AddDays(11); break}             
        "Saturday"  {$patchTuesdayDate = $date.AddDays(10); break}             
        "Sunday"    {$patchTuesdayDate = $date.AddDays(9); break}
     }            
     $patchDate = $patchTuesdayDate.AddDays($adddays)
     return $patchDate           
}            
            
#Function to convert normal datetime object into DMTFDateTime which is needed by ConfigManager ScheduleToken
Function Convert-NormalDateToConfigMgrDate {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$convertdate
    )

    return [System.Management.ManagementDateTimeconverter]::ToDMTFDateTime($convertdate)
}

Function create-ScheduleToken { 
$class_SMS_ST_NonRecurring = [wmiclass]""
$class_SMS_ST_NonRecurring.psbase.Path ="ROOT\SMS\Site_$($SiteCode):SMS_ST_NonRecurring"

$scheduleToken = $class_SMS_ST_NonRecurring.CreateInstance()   
    if($scheduleToken) 
        {
        $scheduleToken.DayDuration = 0
        $scheduleToken.HourDuration = $HourDuration
        $scheduleToken.IsGMT = $IsGMT.ToBool()
        $scheduleToken.MinuteDuration = $MinuteDuration
        $scheduleToken.StartTime = (Convert-NormalDateToConfigMgrDate $MWstartTime)

        $class_SMS_ScheduleMethods = [wmiclass]""
        $class_SMS_ScheduleMethods.psbase.Path ="ROOT\SMS\Site_$($SiteCode):SMS_ScheduleMethods"
        
        $script:ScheduleString = $class_SMS_ScheduleMethods.WriteToString($scheduleToken)
        [string]$ScheduleString.StringData
        
        } 
}

Function New-CMMaintenanceWindow {
[CmdletBinding()]
param
(
    [datetime]$MWstartTime
)
$CollelectionSettings = Get-WmiObject -class SMS_CollectionSettings -Namespace root\sms\site_$($SiteCode) | Where-Object {$_.CollectionID -eq "$($CollectionID)"}
$CollelectionSettings = [wmi]$CollelectionSettings.__PATH

if ($CollelectionSettings -eq $null) {
$CollelectionSettings = ([WMIClass] ("root\SMS\site_$($SiteCode):SMS_CollectionSettings")).CreateInstance();
$CollelectionSettings.CollectionID = $CollectionID;
$disposable = $CollelectionSettings.Put();
} 

$CollelectionSettings.Get()

$class_SMS_ServiceWindow = [wmiclass]""
$class_SMS_ServiceWindow.psbase.Path ="ROOT\SMS\Site_$($SiteCode):SMS_ServiceWindow"

$SMS_ServiceWindow = $class_SMS_ServiceWindow.CreateInstance()

If ($AddMaintenanceWindowNameMonth)
{
    $monthname = (get-date -Format MMMM ($MWstartTime))
    $yearnumber = ($MWstartTime).Year
    $SMS_ServiceWindow.Name                     = "$($MaintenanceWindowName) $($monthname) $($yearnumber)"
}
else
{
    $SMS_ServiceWindow.Name                     = "$($MaintenanceWindowName)"
}
$SMS_ServiceWindow.Description              = "$($MaintenanceWindowDescription)"
$SMS_ServiceWindow.IsEnabled                = $true
$SMS_ServiceWindow.RecurrenceType           = 1
$SMS_ServiceWindow.ServiceWindowSchedules   = $scheduleString
$SMS_ServiceWindow.ServiceWindowType        = $swtypeint
$SMS_ServiceWindow.StartTime                = "$(Get-Date -Format "yyyyMMddhhmmss.ffffff+***")"

$CollelectionSettings.ServiceWindows += $SMS_ServiceWindow.psobject.baseobject
$CollelectionSettings.Put() |Out-Null

}

function Get-patchTuesdayDate {            
 	if ($nextmonth){            
        $now = Get-Date            
        if ($now.Month -eq 12){
            $dateUTC = Get-Date -Day 1 -Month $($now.addmonths(1)).month -Year $($now.addyears(1)).year
            $date = [datetime]"$($dateUTC)"
            get-secondTuesdayDate $date $adddays
        } 
        else {       
            $dateUTC = Get-Date -Day 1 -Month $($now.Month + 1) -Year $now.Year
            $date = [datetime]"$($dateUTC)"
            get-secondTuesdayDate $date $adddays           
        }
    }            
    else {            
        For ($i = 1; $i -le 12 ; $i++)
        {
            $dateUTC = Get-Date -Day 1 -Month $i -Year $($StartYear) 
            get-secondTuesdayDate $dateUTC $adddays 
        }                
    }            
}
### Functions End Here ###

if($patchTuesday)
{
    [datetime[]]$newdates = Get-patchTuesdayDate
    foreach ($newdate in $newdates)
    {
        [datetime]$MWstartTime = Get-Date -Day $newdate.Day -Month $newdate.Month -Year $newdate.Year -Hour $StartHour -Minute $StartMinute -Second 0 -Millisecond 0
        $schedulestring = create-ScheduleToken $MWstartTime
        try 
            {
                New-CMMaintenanceWindow $MWstartTime
            }
        catch
            {
                If ($AddMaintenanceWindowNameMonth)
                {
                    $monthstring = get-date -Format MMMM ($MWstartTime)
                    Write-Error "There was an error creating the Maintenance Window $($MaintenanceWindowName) $($monthstring) for Collection ID $($CollectionID)."
                }
                else
                {
                    Write-Error "There was an error creating the Maintenance Window $($MaintenanceWindowName) for Collection ID $($CollectionID)."
                }
            }
    }
}
else
{
    [datetime]$MWstartTime = Get-Date -Day $StartDay -Month $StartMonth -Year $StartYear -Hour $StartHour -Minute $StartMinute -Second 0 -Millisecond 0 

    $schedulestring = create-ScheduleToken $MWstartTime

    try 
        {
            New-CMMaintenanceWindow $MWstartTime
        }
    catch
        {
            Write-Error "There was an error creating the Maintenance Window $($MaintenanceWindowName) for Collection ID $($CollectionID)."
        }

}

