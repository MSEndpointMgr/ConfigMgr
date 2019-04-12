<#
.SYNOPSIS
    This script creates the AD Groups and the collection membership query rules for the blog post released at SCCofnigMgr.com

.DESCRIPTION
    Use this script hand in hand with the other Maintenace Scripts provided at SCConfigMgr.com to help better plan and manage your patching in the long term
        

.EXAMPLE
    .\New-MWADGroupsCollectionRules.ps1 -OUPath "OU=GROUPS,OU=MANAGED,DC=PROBRES,DC=ORG" -GroupType DomainLocal
    Example of specifying the group type

.Example
    .\New-MWADGroupsCollectionRules.ps1 -OUPath "OU=GROUPS,OU=MANAGED,DC=PROBRES,DC=ORG"
    Example of not setting the group type. 

.NOTES
    FileName:    NewMWADGroupsCollectionRules.PS1
    Author:      Jordan Benzing
    Contact:     @JordanTheItGuy
    Created:     2019-4-12
    Updated:     2019-04-12

    Version 1.0.0 - Wrote source script imported functions from other scripts made functional
    Version 1.0.1 - Added comments into the original source code and added in notes above it. 

#>

[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$OUPath,
    [Parameter(HelpMessage = "Specify the group type it is highly reccomended that you use domain local groups and that is the default.")]
    [ValidateSet("DomainLocal","Global","Universal")]
    [string]$GroupType = "DomainLocal",
    [Parameter(HelpMessage = "Specify the collection naming structure if you used something that is NOT the default")]
    [string]$CMColNameStructure = "MAINT - SERVER - D*"
)

begin{
#region helperfunctions

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

function Write-TsxOutPut{
    <#
        .SYNOPSIS 
            This function is designed to allow someone who is first learning PowerShell to make better calls back to the host screen without
            needing to understand all of the ins and outs of Write-Error / Verbose / Warnings. This also allows you to bypass things like write-host completely.
        
        .DESCRIPTION
            This function can be called through out a script to show visual progress to a user of where the script is at when it's running. This is useful as it does not 
            trigger terminating error code messages or true 'warnings' that otherwise might be caused by a .NET write-error or other method. Also allows the user to color co-ordinate messages
            without using the write-host prompt.
        
        .NOTES
                FileName:    Write-TsxOutput.PS1
                Author:      Jordan Benzing
                Contact:     @JordanTheItGuy
                Created:     2019-04-11
                Updated:     2019-04-11
    
                Version 0.0.0 (2019-04-10) - Wrote original function with no comments and no explanation
                Version 1.0.0 (2019-04-11) - Wrote function notes into the script added the help section to explain usage
    
        .LINK
            https://github.com/JordanTheITGuy/ProblemResolution/blob/master/PowerShell/Functions/write-TsxOutput.ps1
        
        .PARAMETER MsgLevel
            This parameter only accepts a set of choices you can use the "Tab Key" to rotate through the options. The options are:
            Warning - Sets the font color to Yellow to indicate it didn't do what you wanted but didnt fail either
            Default - Sets the font color to Cyan - a neutral color that is readable and conveys progress
            Success - Sets the font color to green - You did something you wanted or a function completed succesfully
    
        .PARAMETER Message
            This parameter accepts strings and allows you to pass through strings that are supposed to be displayed in a specific color to convey status. 
    
        .EXAMPLE 
            Write-TsxOutPut -MsgLevel Warning -Message "Something is amiss"
            Example of running the code to generate a warning level message - or maybe it just indicates a tricky part is happening
    
        .EXAMPLE
            Write-TsxOutPut -MsgLevel Default -Message "This is normal execution"    
            Example of normal execution message back to the user. 
            
        .EXAMPLE
            Write-TsxOutPut -MsgLevel Success -Message "You made it"
            Example of success or finalized out put message it's green and happy.
    #>
        [cmdletbinding()]
        Param(
        [Parameter(Mandatory = $true,
        HelpMessage = "You must select one of these options, this is what sets the color of the output message from Yellow, Cyan, or Green.")]
        [validateSet("Warning","Default","Success")]
        [string]$MsgLevel,
        [Parameter(Mandatory = $true,
        HelpMessage = "This parameter accespts a string that should be printed in the color font you would like to use")]
        [string]$Message = $false
        )
        #Start the try block
        try{
            #Capture the original state of the foreground for text in line
            $originState = $Host.UI.RawUI.ForegroundColor
            #Start a switch to evaluate the msg level
            switch ($MsgLevel) {
                "Warning" { 
                    #If the type is warning then set the font to Yellow
                    $Host.UI.RawUI.ForegroundColor = "Yellow"
                    #Write the message using write-output and string concat
                    Write-Output "$($Message)"
                }
                "Default"{
                    #If the type is default or 'running as expected" then set the font color to cyan
                    $Host.UI.RawUI.ForegroundColor = "Cyan"
                    #Write the message using write-output and string concat
                    Write-Output "$($Message)"
                }
                "Success"{
                    #If the type is Success or 'running as expected" then set the font color to cyan
                    $Host.UI.RawUI.ForegroundColor = "Green"
                    #Write the message using write-output and string concat
                    Write-Output "$($Message)"
                }
                #Default should never be triggered as this uses a Validate Set statement
                Default {}
            }
        }
        #In the even that something goes wrong with the write-output such as an object or something other than a string is properly passed through write an error. 
        catch{
            Write-Error -Message "Something went wrong"
        }
        finally{
            #Always set the color back. 
            $Host.UI.RawUI.ForegroundColor = $originState
        }
    }
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

function New-ADGroupQuery{
    [cmdletbinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$GroupName,
        [parameter(Mandatory = $true)]
        [string]$CollectionName
        )
$GroupName = "$((Get-ADForest).Name)\\$GroupName"
$Query = @"
select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.SystemGroupName = "$groupName"
"@
        Add-CMDeviceCollectionQueryMembershiprule -CollectionName $CollectionName -RuleName "All devices that are a member of AD Group $($GroupName)" -QueryExpression $Query
        }

#endregion helperfunctions
}

Process{
    if(Test-Module -ModuleName ActiveDirectory -Remediate:$True)
    #This command checks to see if the ActiveDirectory module is loaded - if it's not then load the module
    {
        try {
            #Validate the OU Path existt
            if(!(Test-Path -Path "AD:\$($OUPath)"))
            {
                #Error in the event on this
                throw "Tested the OU Path and the OU Path doesn't exist"
            }
            #Write the out put with the OU Connection Test
            Write-TsxOutPut -MsgLevel Default -Message "Passed the OU connection test"
            $OriginLocation = Get-Location
            #Now we load the ConfigMgr module
            if(Test-ConfigMgrAvailable -Remediate:$true){
                #Retrieve the CMCollections
                Write-TsxOutPut -MsgLevel Default -Message "Now retrieving the collections"
                $CollectionList = Get-CMCollection -Name $CMColNameStructure | Select-Object Name,CollectionID
                #Now do some evaluation and write back the information about the collections we retrieve to the screen.
                Write-TsxOutPut -MsgLevel Success -Message "Retrieved all of the collections in a list"
                Write-TsxOutPut -MsgLevel Warning -Message "We now need to CREATE a bunch of AD groups please validate the information before we create $($CollectionList.Count) groups"
                Write-TsxOutPut -MsgLevel Warning -Message "The validated OU Path is $($OUPath)"
                Write-TsxOutPut -MsgLevel WARNING -Message "The GROUP TYPE is $($GroupType)"
                #Write a warning about what we are going to do and confirm the action
                Write-Warning -Message "If you continue this WILL create Groups if you do NOT want to create groups please enter H otherwise hit A" -WarningAction Inquire
                #Start the foreach loop to evaluate each collection and then create the information needed for the creation of the AD groups
                foreach($Collection in $CollectionList){
                    Write-TsxOutPut -MsgLevel Default -Message "Now Creating AD Group - $($Collection.Name)"
                    #use this to build the description information indicating the day number and time that the windows starts and ends.
                    $DayMWString = $Collection.Name.Split(" - ")[($($Collection.Name.Split(" - ")).length)-1]
                    $CharPosition = New-Object System.Collections.ArrayList($null)
                    foreach($char in [char[]]$DayMWString){
                    if($Char -match "[a-z]"){
                        $CharPosition.Add($DayMWString.IndexOf($Char)) | Out-Null
                        }
                    }
                    $Window = $DayMWString.Substring($($CharPosition[1]))
                    $WindowInfo = Get-PatchWindowTime -Window $Window
                    #Create the Active Directory Group 
                    New-ADGroup -Name $Collection.Name -GroupScope $GroupType -Description "This Group provides a maintenance window for servers from $($WindowInfo[1])" -Path $OUPath
                    Write-TsxOutPut -MsgLevel Success -Message "Created AD group - $($Collection.Name)"
                    Write-TsxOutPut -MsgLevel Default -Message "Now starting the process of Generating the rule and attaching to the ConfigMgr Collection"
                    #Create the AD group Query name
                    New-ADGroupQuery -GroupName $Collection.Name -CollectionName $Collection.Name
                }
                }
                #Return to the original location away from the CMProvider
                Set-Location -Path $OriginLocation.Path
            }
        catch {
            Write-Error $_.Exception.Message
            break
        }
        
    }
}