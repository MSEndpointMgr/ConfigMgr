<#
.SYNOPSIS
    This scripts creates maintenance window collections for servers based on provided criteria. 

.DESCRIPTION
    Use this script to create and move maintenace window collections to a desired location in your configuration manager environment. 
        

.EXAMPLE
    This script uses some parameters here is an example of usage:
    PR1:\> C:\scripts\Create-MaintenanceCollections.Ps1 -LimitingCollectionID "SMS00001" -NumberofDays 5 -FolderPath "PR1:\DeviceCollections\SUM - PatchingCollections\Maintenance Collections"

.NOTES
    FileName:    Create-MaintenanceCollections.PS1
    Author:      Jordan Benzing
    Contact:     @JordanTheItGuy
    Created:     2019-04-09
    Updated:     2019-04-09

    Version 1.0.1 - It works and creates stuff with no parameters and is cardcoded
    Version 1.0.2 - Added the ability to utilize Parameters
    Version 1.0.3 - Added verbosity to show each step as it goes along and some error checking.
    Version 1.0.4 - Updated to use standard helper functions to validate and remediate a connection to CM Provider
                    Updated to remove extraneous verbose information
                    Updated to return you to the original directory you were in when you ran the script
#>


param(
    [parameter(Mandatory = $true)]
    [string]$LimitingCollectionID,
    [parameter(Mandatory = $true)]
    [int]$NumberofDays,
    [Parameter(Mandatory = $true)]
    [string]$FolderPath
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

#Ensure the Configuration Manager Module is loaded if it's not loaded see blog post on how to load it at www.scconfigmgr.com
$StartingLocation = Get-Location
if(!(Test-ConfigMgrAvailable -Remediate:$true -Verbose)){
    Write-Error -Message "Nope that's horribly broken"
    break  
}
#Ensure the folder path you would like to move the collections to exists
Write-Verbose -Message "Now testing if the location to move the collections to exists and is written out properly." -Verbose
if(!(Test-Path -Path $FolderPath)){
    Write-Error -Message "The Path does not exist please re-run the script with a valad path"
    break
}
Write-Verbose "The location to move the collections to EXISTS and IS written out properly." -Verbose
#Set the naming standard for the collection name you MAY change this it's highly reccomended that you do NOT.
$MWName = "MAINT - SERVER - D"
Write-Verbose "The naming standard for your maintenance collections will be $($MWNAME) with the day after patch tuesday and window indication afterwords"
#Set the date counter to 0
$DayCounter = 0
#Create a list to store the collection names in. 
$list = New-Object System.Collections.ArrayList($null)
#Create a CMSchedule object - This sets the refresh on the collections you may change the below line otherwise collections will refresh weekly on saturday.
$Schedule = New-CMSchedule -Start (Get-Date) -DayOfWeek Saturday -RecurCount 1
Do
{
    #Add one to the day counter
    $DayCounter++
    #Create the new string - Collection name plus the count of days after patch tuesday.
    $NewString = $MWName + $DayCounter
    #Store the string into the list
    $List.add($NewString) | Out-Null
}
#Do this until the number of days you would like to have MW's for is reached.
while($DayCounter -ne $NumberofDays)
Write-Verbose "Created Day Names" -Verbose
#Create the Full list object - this will now add in the MW information (6 created per day each one is 4 hours long allowing you to patch anytime of the day)
$FullList = New-Object System.Collections.ArrayList($null)
#For each DAY/COLLECTION in the previous list CREATE 6 maintenance window collection names. 
foreach($Object in $list)
    {
        #Set the window counter back back to 0
        [int32]$WindowCounter = 0
        do 
            {
                #Add one to the window counter
                $WindowCounter++ 
                #Create the new collection name and add the nomenclature of W3 to it. 
                $NewCollection = $Object + "W" + $($WindowCounter.ToString())
                #Compile and store the finalized list name. 
                $FullList.Add($NewCollection) | Out-Null
            }
        #Do this until you reach 6 of them - you can of course change that if you really wanted to... but why? 
        while ($($WindowCounter.ToString()) -ne "6")
    }
#For each collection name in the FULL list of (MAINT - SERVER - D1W1 (example)) - create a collection limited to the specified limit and refresh weekly on Saturday.
Write-Warning -Message "The Action you are about to perfom will create $($FullList.Count) collections do you want to continue?" -WarningAction Inquire
Write-Verbose -Message "Created all MW Collection Names now creating the MW Collections" -Verbose
ForEach($CollectionName in $FullList)
    {
        try{
        #Create the collection
        Write-Verbose -Message "Now creating $($collectionName)" -Verbose
        #Change the below information to change information about the collection. 
        $Object = New-CMCollection -collectionType Device -Name $CollectionName -LimitingCollectionId $LimitingCollectionID -RefreshSchedule $Schedule -RefreshType Periodic
        #Move the collection to its final destination.
        Move-CMObject -FolderPath $FolderPath -InputObject $Object
        Write-Verbose -Message "Successfully created and moved $($collectionName) to its destination" -Verbose
        }
        catch
        {
            Write-Error -Message $_.Exception.Message
        }
    }
set-location -Path $StartingLocation.Path
Write-Output -InputObject $("Completed the script succesfully")
