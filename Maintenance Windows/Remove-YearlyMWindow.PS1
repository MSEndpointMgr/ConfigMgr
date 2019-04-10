<#
.SYNOPSIS
    This script is part of the package to create standard MW Collections and Windows and remove them

.DESCRIPTION
    Use this script to REMOVE Maintenacne windows from the standardized MW collections.
        

.EXAMPLE
    This script uses some parameters here is an example of usage:
    .\Remove-YearlyMYindow.PS1

.NOTES
    FileName:    Remove-YearlyMYindow.PS1
    Author:      Jordan Benzing
    Contact:     @JordanTheItGuy
    Created:     2019-04-09
    Updated:     2019-04-09

    Version 1.0.1 - It works and removes maintenance windows.
    Version 1.0.2 - Added Parameter for Collection Naming Standard so it can be used with OTHER collection structures
                - adjusted some of the verbose statements from the hardcoded original version to be more precise
    Version 1.0.3 (2019-04-09) - Adjusted verbose statement to be more accurate

#>

param(
    [Parameter(Mandatory=$true)]
    [string]$CollectionNamingStandard
)
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

$StartingLocation = Get-Location
if(!(Test-ConfigMgrAvailable -Remediate:$true -Verbose)){
    Write-Error -Message "Nope that's horribly broken"
    break  
}

Write-Verbose -Message "Now getting Collection list" -Verbose
$Collections = Get-CMCollection -Name $CollectionNamingStandard
Write-Verbose -Message "Succesfully retrieved Collections" -Verbose
Write-Verbose -Message "Now cleaning Maintenance Windows pardon our dust..." -Verbose
foreach($Collection in $Collections)
    {
        Write-Verbose -Message "Retrieving maintenance windows from $($Collection.Name)" -Verbose
        $MaintenanceWindows = Get-CMMaintenanceWindow -CollectionName $Collection.Name
        foreach($MaintenanceWindow in $MaintenanceWindows)
            {
                Write-Verbose "Removing Maintenance window $($MaintenanceWindow.Name) from collection $($Collection.Name)" -Verbose
                Remove-CMMaintenanceWindow -CollectionName $Collection.Name -MaintenanceWindowName $MaintenanceWindow.Name -Force
                Write-Verbose "SUCCESFULLY Removed Maintenance window $($MaintenanceWindow.Name) from collection $($Collection.Name)" -Verbose
            }
    }
Set-Location -Path $StartingLocation.Path