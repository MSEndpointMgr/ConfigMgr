<#
.SYNOPSIS
    This script creates Maintenance windows for an entire year

.DESCRIPTION
    Use this to remove all maintenance windows from collections that match certain criteria
        

.EXAMPLE
	The script is static and does not have any functions to use for an example.

.NOTES
    FileName:    New-YearlyMWindow.PS1
    Author:      Jordan Benzing
    Contact:     @JordanTheItGuy
    Created:     2018-12-13
    Updated:     2019-04-08

    1.0.0 - (2018-12-13) Original Written version Mike Hiser/Jordan Benzing
    1.0.1 - (2019-04-08) Updated with custom variables at the start of the script and dynamic discover of the site server
    1.0.2 - (2019-04-09) Updated to dynamically figure out the number of days/Patch ranges to do the offset math
    1.0.3 - (2019-04-09) Updated to include version history
    1.0.4 - (2019-04-09) Updated the ConfigMgr Helper Function remove extra 'verbose' stuff
                         Updated the logic of the running function to remove extra/duplicate checks for the configmgr module
    1.0.5 - (2019-04-09) Updated the script to include a parameter option to specify the year and an offset from patch tuesday.
    1.0.6 - (2019-04-09) Removed the parameter from the MW creation function to utilize the already sent variable with a default of 0 if none is selected.
                         NOTE - Offset is always calculated from the day AFTER patch tuesday 0 = Patch Wednesday
    1.0.7 - (2019-04-09) Added parameter for CollectionName Structure
                        NOTE - DONT CHANGE THIS IF YOU USED THE DEFAULT CREATE-MAINTENANCECOLLECTIONS.PS1 SCRIPT
                        

#>

param(
    [Parameter()]
    [string]$PatchTuesdayOffsetDays = 0,
    [Parameter(Mandatory=$true)]
    $Year,
    [Parameter()]
    $CollectionNameStructure = "MAINT - Server - D*",
    [Parameter()]
    $SiteCode = "$(((Get-WmiObject -namespace "root\sms" -class "__Namespace").Name).substring(8-3))"
)

################################# Variables ################################################
$MWName = "Patching"
$MWDescription = "Patching Window"
$MWDuration = 4
$StartMinute = 0
$MinuteDuration = 0
############################################################################################
#region HelperFunctions
function Get-CMModule
#This application gets the configMgr module
{
    [CmdletBinding()]
    param()
    Try
    {
        Write-Verbose "Attempting to import SCCM Module"
        #Retrieves the fcnction from ConfigMgr installation path. 
        Import-Module (Join-Path $(Split-Path $ENV:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1) -Verbose:$false
        Write-Verbose "Succesfully imported the SCCM Module"
    }
    Catch
    {
        Throw "Failure to import SCCM Cmdlets."
    } 
}

function Test-ConfigMgrAvailable
#Tests if ConfigMgr is availble so that the SMSProvider and configmgr cmdlets can help. 
{
    [CMdletbinding()]
    Param
    (
        [Parameter(Mandatory = $false)]
        [bool]$Remediate
    )
        try
        {
            if((Test-Module -ModuleName ConfigurationManager -Remediate:$true) -eq $false)
            #Checks to see if the Configuration Manager module is loaded or not and then since the remediate flag is set automatically imports it.
            { 
                throw "You have not loaded the configuration manager module please load the appropriate module and try again."
                #Throws this error if even after the remediation or if the remediation fails. 
            }
            write-Verbose "ConfigurationManager Module is loaded"
            Write-Verbose "Checking if current drive is a CMDrive"
            if((Get-location -Verbose:$false).Path -ne (Get-location -PSProvider 'CmSite' -Verbose:$false).Path)
            #Checks if the current location is the - PS provider for the CMSite server. 
            {
                Write-Verbose -Message "The location is NOT currently the CMDrive"
                if($Remediate)
                #If the remediation field is set then it attempts to set the current location of the path to the CMSite server path. 
                    {
                        Write-Verbose -Message "Remediation was requested now attempting to set location to the the CM PSDrive"
                        Set-Location -Path (((Get-PSDrive -PSProvider CMSite -Verbose:$false).Name) + ":") -Verbose:$false
                        Write-Verbose -Message "Succesfully connected to the CMDrive"
                        #Sets the location properly to the PSDrive.
                    }

                else
                {
                    throw "You are not currently connected to a CMSite Provider Please Connect and try again"
                }
            }
            write-Verbose "Succesfully validated connection to a CMProvider"
            return $true
        }
        catch
        {
            $errorMessage = $_.Exception.Message
            write-error -Exception CMPatching -Message $errorMessage
            return $false
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
        Write-Verbose -Message "The module was already loaded return TRUE"
        return $true
    }
    If((Get-Module -Name $ModuleName) -ne $true)
    #Checks if the module is NOT loaded and if it's not loaded then check to see if remediation is requested. 
    {
        Write-Verbose -Message "The Module was not already loaded evaluate if remediation flag was set"
        if($Remediate -eq $true)
        #If the remediation flag is selected then attempt to import the module. 
        {
            try 
            {
                    if($ModuleName -eq "ConfigurationManager")
                    #If the module requested is the Configuration Manager module use the below method to try to import the ConfigMGr Module.
                    {
                        Write-Verbose -Message "Non-Standard module requested run pre-written function"
                        Get-CMModule
                        #Runs the command to get the COnfigMgr module if its needed. 
                        Write-Verbose -Message "Succesfully loaded the module"
                        return $true
                    }
                    else
                    {
                    Write-Verbose -Message "Remediation flag WAS set now attempting to import module $($ModuleName)"
                    Import-Module -Name $ModuleName
                    #Import  the other module as needed - if they have no custom requirements.
                    Write-Verbose -Message "Succesfully improted the module $ModuleName"
                    Return $true
                    }
            }
            catch 
            {
                Write-Error -Message "Failed to import the module $($ModuleName)"
                Set-Location $StartingLocation
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
#endregion HelperFunctions



#region Get-PatchWindow -Window $Arg 
Function Get-PatchWindowTime
{
    [Cmdletbinding()]
    Param
    (
        [Parameter(Mandatory = $True)]
        $Window
    )

    Switch ($Window)  # Determine Window
    {
        # Window 1 00:00 to 04:00
        'W1' {
            $Description = 'Window 1 00:00 to 04:00'
            $StartHour = '0'
        }

        # Window 2 04:00 to 08:00
        'W2' {
            $StartHour = '4'
            $Description = 'Window 2 04:00 to 08:00'
        }

        # Window 3 08:00 to 12:00
        'W3' {
            $StartHour = '8'
            $Description = 'Window 3 08:00 to 12:00'
        }
               
        # Window 4 12:00 to 16:00
        'W4' {
            $StartHour = '12'
            $Description = 'Window 4 12:00 to 16:00'
        }

        # Window 5 16:00 to 20:00
        'W5' {
            $StartHour = '16'
            $Description = 'Window 5 16:00 to 20:00'
        }

        # Window 6 20:00 to 00:00
        'W6' {
            $StartHour = '20'
            $Description = 'Window 6 20:00 to 00:00'
        }

        # If group name match fails, log name, do not create schedule
        Default {
            write-verbose -message "Start Time failed." -Verbose
        }

    } # End switch

    Return $StartHour,$Description
}
#endregion
#region Get-PatchStartDay -DayType $Arg 
Function Get-PatchWindowDate
{
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory = $True)]
        $DayType
    )
    [int]$WinType = 0
    $DaysAdded = $WinType + $DaysAfter
    Return $DaysAdded
}
#endregion

#Gather specific collections for processing with the MW script
Function start-WindowCreation{
    [cmdletbinding()]
    param()

    if(!(Test-ConfigMgrAvailable -Remediate:$true -Verbose)){
        Write-Error -Message "Soemthing went wrong with the helper functions review verbose messages"
        break
    }
    $MWCollections = Get-CMDeviceCollection -Name $CollectionNameStructure | Select-Object name,collectionid
    Set-Location -Path $(Split-Path $script:MyInvocation.MyCommand.Path)
    Foreach ($Collection in $MWCollections) {
        $MWString = $Collection.Name.Split(" - ")[($($Collection.Name.Split(" - ")).length)-1]
        $CharPosition = New-Object System.Collections.ArrayList($null)
        foreach($char in [char[]]$MWString){
        if($Char -match "[a-z]"){
            $CharPosition.Add($MWString.IndexOf($Char)) | Out-Null
            }
        }
        $TotalDaysAdded = $MWString.Substring($($CharPosition[0] +1), $($CharPosition[1] - 1))
        $TotalDaysAdded = [int]$TotalDaysAdded + [int]$PatchTuesdayOffsetDays
        $Window = $MWString.Substring($($CharPosition[1]))
        # Function call to determine patch window only
        $WindowInfo = Get-PatchWindowTime -Window $Window
        $StartHour = $WindowInfo[0]
        $MWDescription = $Day + " " + $WindowInfo[1]
        Write-Verbose -Message "$($Collection.Name) `
            Start Hour : $StartHour `
            End Hour   : $([int]$StartHour + [int]$MWDuration)
            Days to add after Patch Tuesday: $TotalDaysAdded" -Verbose
        Write-Verbose -Message "Creating maintenance windows for collection $($collection.name.ToUpper())" -Verbose
        #write-host ".\createmw.ps1 -sitecode $Sitecode -MaintenanceWindowName `"$MWNameDetail`" -CollectionID $($Collection.collectionid) -HourDuration $MWDuration -MinuteDuration $MinuteDuration -swtype Updates -PatchTuesday -AddDays $TotalDaysAdded -StartYear $Year -StartMinute $StartMinute -AddMaintenanceWindowNameMonth -MaintenanceWindowDescription `"$MWDescription`""
        Invoke-Expression ".\createmw.ps1 -sitecode $Sitecode -MaintenanceWindowName `"$MWName`" -CollectionID $($Collection.collectionid) -HourDuration $MWDuration -MinuteDuration $MinuteDuration -swtype Updates -PatchTuesday -AddDays $TotalDaysAdded -StartYear $Year -StartHour 0 -StartMinute $StartMinute -AddMaintenanceWindowNameMonth -MaintenanceWindowDescription `"$MWDescription`""
    }
}

start-WindowCreation -Verbose
