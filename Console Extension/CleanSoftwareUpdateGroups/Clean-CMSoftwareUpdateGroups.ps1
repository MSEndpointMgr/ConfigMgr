<#
.SYNOPSIS
    Perform a clean up of expired and/or supersded Software Updates in all Software Update Groups
.DESCRIPTION
    Use this script if you need to perform a clean up of expired and/or superseded Software Updates from all Software Upgrade Groups in ConfigMgr
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER Option
    Select an option to clean either ExpiredOnly, SupersededOnly or ExpiredSuperseded Software Updates from each Software Update Group
.PARAMETER RemoveContent
    Remove the content for those Software Updates that will be removed from a Software Upgrade Group
.PARAMETER ShowProgress
    Show a progressbar displaying the current operation
.EXAMPLE
    Clean Software Update Groups from expired Software Updates, while showing the current progress and removing downloaded content, on a Primary Site server called 'CM01':
    .\Clean-CMSoftwareUpdateGroups.ps1 -SiteServer CM01 -Option ExpiredOnly -RemoveContent -ShowProgress

    Clean Software Update Groups from superseded Software Updates, while showing the current progress, on a Primary Site server called 'CM01':
    .\Clean-CMSoftwareUpdateGroups.ps1 -SiteServer CM01 -Option SupersededOnly -ShowProgress

    Clean Software Update Groups from expired and supersded Software Updates with verbose output, on a Primary Site server called 'CM01':
    .\Clean-CMSoftwareUpdateGroups.ps1 -SiteServer CM01 -Option ExpiredSuperseded -Verbose
    
.NOTES
    Name:        Clean-CMSoftwareUpdateGroups.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2015-12-17
    Version:     2.1
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [ValidateNotNullOrEmpty()]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Select an option to clean either ExpiredOnly, SupersededOnly or ExpiredSuperseded Software Updates from each Software Update Group")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("ExpiredOnly","SupersededOnly","ExpiredSuperseded")]
    [string]$Option,

    [parameter(Mandatory=$false, HelpMessage="Remove the content for those Software Updates that will be removed from a Software Upgrade Group")]
    [ValidateNotNullOrEmpty()]
    [switch]$RemoveContent,

    [parameter(Mandatory=$false, HelpMessage="Show a progressbar displaying the current operation")]
    [ValidateNotNullOrEmpty()]
    [switch]$ShowProgress
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose "Determining Site Code for Site server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Verbose -Message "Site Code: $($SiteCode)"
            }
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine Site Code" ; break
    }
    # Temporarily set ErrorActionPreference
    $ErrorActionPreference = "Stop"
    # Set ProgressCount
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }
}
Process {
    try {
        $StartTime = [Diagnostics.Stopwatch]::StartNew()
        $SUGResults = (Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_AuthorizationList -ComputerName $SiteServer -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($SUGResults -ge 1) {
            # Get list of removable Software Updates
            switch ($Option) {
                "ExpiredOnly" {
                    $Query = "SELECT SU.CI_ID FROM SMS_SoftwareUpdate AS SU JOIN SMS_CIRelation AS CIR ON SU.CI_ID = CIR.ToCIID WHERE CIR.RelationType = 1 AND SU.IsExpired = 1 AND SU.IsSuperseded = 0"
                }
                "SupersededOnly" {
                    $Query = "SELECT SU.CI_ID FROM SMS_SoftwareUpdate AS SU JOIN SMS_CIRelation AS CIR ON SU.CI_ID = CIR.ToCIID WHERE CIR.RelationType = 1 AND SU.IsExpired = 0 AND SU.IsSuperseded = 1"
                }
                "ExpiredSuperseded" {
                    $Query = "SELECT SU.CI_ID FROM SMS_SoftwareUpdate AS SU JOIN SMS_CIRelation AS CIR ON SU.CI_ID = CIR.ToCIID WHERE CIR.RelationType = 1 AND (SU.IsExpired = 1 OR SU.IsSuperseded = 1)"
                }
            }
            try {
                $RemovableUpdates = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Query $Query -ComputerName $SiteServer -ErrorAction Stop
                $RemovableUpdatesList = New-Object -TypeName System.Collections.ArrayList
                foreach ($RemovableUpdate in $RemovableUpdates) {
                    $RemovableUpdatesList.Add($RemovableUpdate.CI_ID) | Out-Null
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to determine removable Software Updates from selected option"
            }
            # Enumerate each Software Update Group
            $AuthorizationLists = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_AuthorizationList -ComputerName $SiteServer -ErrorAction Stop
            foreach ($AuthorizationList in $AuthorizationLists) {
                Write-Verbose -Message "Start processing '$($AuthorizationList.LocalizedDisplayName)'"
                if ($PSBoundParameters["ShowProgress"]) {
                    $ProgressCount++
                }
                Write-Progress -Activity "Processing Software Updates Groups" -Id 1 -Status "$($ProgressCount) / $($SUGResults)" -CurrentOperation "Current Software Update Group: '$($AuthorizationList.LocalizedDisplayName)'" -PercentComplete (($ProgressCount / $SUGResults) * 100)
                $AuthorizationList = [wmi]"$($AuthorizationList.__PATH)"
                $UpdatesCount = $AuthorizationList.Updates.Count
                $UpdatesList = New-Object -TypeName System.Collections.ArrayList
                $RemovedUpdatesList = New-Object -TypeName System.Collections.ArrayList
                # Enumerate each Software Update in current Software Update Group if eligible for removal
                foreach ($Update in ($AuthorizationList.Updates)) {
                    if ($Update -notin $RemovableUpdatesList) {
                        $UpdatesList.Add($Update) | Out-Null
                    }
                    else {
                        $RemovedUpdatesList.Add($Update) | Out-Null
                    }
                }
                # Update Software Update Group updates if count of objects in UpdatesList is less than before
                if ($UpdatesCount -gt $UpdatesList.Count) {
                    try {
                        if ($PSCmdlet.ShouldProcess("$($AuthorizationList.LocalizedDisplayName)","Clean '$($UpdatesCount - ($UpdatesList.Count))' updates")) {
                            if ($UpdatesList.Count -ge 1) {
                                $AuthorizationList.Updates = $UpdatesList
                                $AuthorizationList.Put() | Out-Null
                                Write-Verbose -Message "Successfully cleaned up $($UpdatesCount - ($UpdatesList.Count)) updates from '$($AuthorizationList.LocalizedDisplayName)'"
                            }
                            else {
                                $AuthorizationList.Updates = @()
                                $AuthorizationList.Put() | Out-Null
                                Write-Verbose -Message "Successfully cleaned up all updates from '$($AuthorizationList.LocalizedDisplayName)'"
                            }
                        }
                        # Remove content for each CI_ID in the RemovedUpdatesList array
                        if ($PSBoundParameters["RemoveContent"]) {
                            try {
                                $DeploymentPackageList = New-Object -TypeName System.Collections.ArrayList
                                foreach ($CI_ID in $RemovedUpdatesList) {
                                    Write-Verbose -Message "Collecting content data for CI_ID: $($CI_ID)"
                                    $ContentQuery = "SELECT SMS_PackageToContent.ContentID,SMS_PackageToContent.PackageID from SMS_PackageToContent JOIN SMS_CIToContent ON SMS_CIToContent.ContentID = SMS_PackageToContent.ContentID WHERE SMS_CIToContent.CI_ID IN ($($CI_ID))"
                                    $ContentData = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Query $ContentQuery -ComputerName $SiteServer -ErrorAction Stop
                                    Write-Verbose -Message "Found '$(($ContentData | Measure-Object).Count)' objects"
                                    foreach ($Content in $ContentData) {
                                        $ContentID = $Content | Select-Object -ExpandProperty ContentID
                                        $PackageID = $Content | Select-Object -ExpandProperty PackageID
                                        $DeploymentPackage = [wmi]"\\$($SiteServer)\root\SMS\site_$($SiteCode):SMS_SoftwareUpdatesPackage.PackageID='$($PackageID)'"
                                        if ($DeploymentPackage.PackageID -notin $DeploymentPackageList) {
                                            $DeploymentPackageList.Add($DeploymentPackage.PackageID) | Out-Null
                                        }
                                        if ($PSCmdlet.ShouldProcess("$($PackageID)","Remove ContentID '$($ContentID)'")) {
                                            Write-Verbose -Message "Attempting to remove ContentID '$($ContentID)' from PackageID '$($PackageID)'"
                                            $ReturnValue = $DeploymentPackage.RemoveContent($ContentID, $false)
                                            if ($ReturnValue.ReturnValue -eq 0) {
                                                Write-Verbose -Message "Successfully removed ContentID '$($ContentID)' from PackageID '$($PackageID)'"
                                            }
                                        }
                                    }
                                }
                            }
                            catch [Exception] {
                                Write-Warning -Message "An error occured when attempting to remove ContentID '$($ContentID)' from '$($PackageID)'"
                            }
                        }
                    }
                    catch [Exception] {
                        Write-Warning -Message "Unable to save changes to '$($AuthorizationList.LocalizedDisplayName)'" ; break
                    }
                }
                else {
                    Write-Verbose -Message "No changes detected, will not update '$($AuthorizationList.LocalizedDisplayName)'"
                }
                # Refresh content source for all Deployment Packages in the DeploymentPackageList array
                if (($DeploymentPackageList.Count -ge 1) -and ($PSBoundParameters["RemoveContent"])) {
                    foreach ($DPackageID in $DeploymentPackageList) {
                        if ($PSCmdlet.ShouldProcess("$($DPackageID)","Refresh content source")) {
                            $DPackage = [wmi]"\\$($SiteServer)\root\SMS\site_$($SiteCode):SMS_SoftwareUpdatesPackage.PackageID='$($DPackageID)'"
                            Write-Verbose -Message "Attempting to refresh content source for Deployment Package '$($DPackage.Name)'"
                            $ReturnValue = $DPackage.RefreshPkgSource()
                            if ($ReturnValue.ReturnValue -eq 0) {
                                Write-Verbose -Message "Successfully refreshed content source for Deployment Package '$($DPackage.Name)'"
                            }
                        }
                    }
                }
            }
        }
        else {
            Write-Warning -Message "Unable to locate any Software Update Groups"
        }
    }
    catch [Exception] {
        Write-Error -Message $_.Exception.Message
    }
}
End {
    # Temporarily set ErrorActionPreference
    $ErrorActionPreference = "Continue"
    # Complete write progress activity    
    if ($PSBoundParameters["ShowProgress"]) {
        Write-Progress -Activity "Processing Software Update Groups" -Completed -ErrorAction SilentlyContinue
    }
    # Output script exection time
    $StartTime.Stop()
    Write-Verbose -Message "Script execution: $($StartTime.Elapsed.Minutes) min and $($StartTime.Elapsed.Seconds) seconds"
}