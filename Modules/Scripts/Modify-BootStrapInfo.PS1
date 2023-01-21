<#
.SYNOPSIS
    This script is for finding a specific piece of information in an INI file that is used for MDT and replacing it. An example of this would be if you need to update 
    the domain join account in all boot files in all deployment shares or update the password in all of the boot files in all deployment shares.

.DESCRIPTION
    This script is intended to be used specifically for finding any uses of a specific term in an INI file for the MDT Bootstrap and to modify it. This script is used at
    your own risk.

.EXAMPLE
    Only Gets info using search base C:\DeploymentShare 

    .\Modify-BootStrapInfo.ps1 -SearchBase C:\DeploymentShare -SearchTerm UserID=Administrator -GetInfo:$true -UpdateInfo:$false

.PARAMETER GetInfo
    This is a required switch true false switch
        $TRUE - Runs the GET-BOOTSTRAPCONTENT function to retreive information based on search criteria and find all INI's meeting the specified criteria.
        $FALSE - Prevents the 'Get-BootstrapContent function from running to retrevie the location of all INI's meeting the specified criteria
.PARAMETER UpdateInfo
    This is a required true false switch
        $TRUE - runs the set-bootstrapcontent function to exchange/update information based on meeting the specified INI criteria
        $FALSE - Prevents the Set-bootstrapcontent function from running to exchange/update information based on meeting the specified INI criteria

.PARAMETER SearchBase
    This is a non-required string. If it is not set it will begin looking from the current running directroy to find all INI files that match the specified criteria
    if set it will use that path to begin the search. This parameter is recommended to reduce run times. 

.PARAMETER SearchTerm
    This is a required string. If it is not set it will be asked for. This is what is used to look to see if the file contains this. This is an EXACT match using the contains
    method. If there is no exact match it will not return a result.
    EXAMPLE - "Administrator" =/= "UserID=Administrator"

.PARAMETER ReplaceTerm
    This is not required to run the script but will become required if you attempt to run the Set-BootStrapContent function called by making UpdateInfo $true.

.NOTES
    FileName:    Modify-BootStrapInfo.ps1
    Author:      Jordan Benzing
    Contact:     @JordanTheItGuy
    Created:     2018-09-06
    Updated:     2018-09-06

    Version history:
    1.0.0 - (2018-09-06) Script created
#>

[CmdletBinding()]
Param(
    [parameter(Mandatory = $true)]
    [switch]$GetInfo,
    [parameter(Mandatory = $true)]
    [switch]$UpdateInfo,
    [parameter(Mandatory = $false)]
    [string]$SearchBase,
    [Parameter(Mandatory = $true)]
    [string]$SearchTerm
)

#Requires -RunAsAdministrator

function Get-BootStrapContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SearchBase,
        [Parameter(Mandatory = $true)]
        [string]$SearchTerm
    )
    Begin {
        $FileArray = @()
    }
    Process {
        #Begin function to search for INI files that meet the criteria. 
        Write-Verbose -Message "Now Building file list to search through - ignoring and suppressing any INI with access denied"
        $Filelist = Get-ChildItem -Path $SearchBase -Filter *.ini -Recurse -ErrorAction SilentlyContinue

        #Get the list of all files starting from the specified directory with the .INI file extension.
        foreach ($File in $Filelist) {
            #For each file in the list of .INI files perform the following action. - If later adding a progress bar breakout here
            $FileName = $File.Name
            Write-Verbose -Message "Retreiving content for $Filename"
            $Content = Get-Content -Path $File.FullName -ErrorAction SilentlyContinue
            #Get the content of the file currently being evaluated - if you cannot get the content silently continue - this is done due to permission errors may
            #Add more gracefull error handling later on
            if ($Content) {
                #Checks if there was any content within the INI file - originally found that some INI files retrieved had no content 
                #If you remove this check it will error on the contains method because you cannot call contains on a null string.
                if ($Content.ToLower().Contains($SearchTerm.ToLower())) {
                    #Evaluates if the content from the INI file contains the search terms if it does enters the loop.
                    $item = New-Object -TypeName psobject
                    $item | Add-Member -Type NoteProperty -Name FileName -Value $FileName
                    $item | Add-Member -Type NoteProperty -Name FileLocation -Value $File.FullName
                    $FileArray += $item
                    #Generates a PSObject with the information to remove the object and then stores it in an array
                }
            }
        }
        $FileArray | Format-Table -AutoSize
    }
}

function Set-BootStrapContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchBase,
        [Parameter(Mandatory = $true)]
        [string]$SearchTerm,
        [Parameter(Mandatory = $true)]
        [string]$ReplaceTerm
    )
    Begin { }
    Process {
        #Begin function to search for INI files that meet the criteria that we will make changes to. 
        $Filelist = Get-ChildItem -Path $SearchBase -Filter *.ini -Recurse -ErrorAction SilentlyContinue

        #Get the list of all files starting from the specified directory with the .INI file extension.
        foreach ($File in $Filelist) {
            #For each file in the list of .INI files perform the following action. - If later adding a progress bar breakout here
            $Content = Get-Content -Path $file.FullName -ErrorAction SilentlyContinue
            #Get the content of the file currently being evaluated - if you cannot get the content silently continue - this is done due to permission errors may
            #Add more gracefull error handling later on
            if ($Content) {
                #Checks if there was any content within the INI file - originally found that some INI files retrieved had no content 
                #If you remove this check it will error on the contains method because you cannot call contains on a null string.
                #If the content contains the search term then enter the loop to perform the replacement.
                    if ($Content.ToLower().Contains($SearchTerm.ToLower())) {
                    #Replaces the content in the file and sets it. 
                    $Content -replace $SearchTerm , $ReplaceTerm | Set-Content $File.FullName
                    #Writes to host what it changed. 
                    Write-Host "Replaced $SearchTerm in the file $File.FullName with $ReplaceTerm"
                }
            }
        }
    }
}

if ($GetInfo) {
    #If the GetINfo Flag was set to true - then it will run through this code block
    Get-BootStrapContent -SearchBase $SearchBase -SearchTerm $SearchTerm
}

if ($UpdateInfo) {
    #If UpdateInfo was set to true - then run through this code block
    Set-BootStrapContent -SearchBase $SearchBase -SearchTerm $SearchTerm
}
