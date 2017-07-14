<#
.SYNOPSIS
    Perform a clean up of software updates that are a member of certain Software Update Group
.DESCRIPTION
    Use this script if you need to perform a clean up of expired or superseded Software Updates that are members of a certain Software Upgrade Group in ConfigMgr 2012
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER SUGName
    Name of the Software Upgrade Group
.PARAMETER ExpiredOnly
    Only remove expired Software Updates. This includes updates that are both expired and superseded. It does, however, exclude updates that are superseded but not expired
.PARAMETER RemoveContent
    Remove the content for those Software Updates that will be removed from a Software Upgrade Group
.PARAMETER ShowProgress
    Show a progressbar displaying the current operation
.EXAMPLE
    .\Clean-CMSoftwareUpdateGroup.ps1 -SiteServer CM01 -SUGName "Critical and Security Patches - 2014-11" -ShowProgress
    Clean a Software Update Group called 'Critical and Security Patches - 2014-11' from expired and superseded Software Updates, while showing the current progress, on a Primary Site server called 'CM01':
.NOTES
    Script name: Clean-CMSoftwareUpdateGroup.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2014-11-17
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true,HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,
    [parameter(Mandatory=$true,HelpMessage="Name of the Software Update Group")]
    [string]$SUGName,
    [parameter(Mandatory=$false,HelpMessage="Only remove expired Software Updates. This includes updates that are both expired and superseded. It does, however, exclude updates that are superseded but not expired")]
    [switch]$ExpiredOnly,
    [parameter(Mandatory=$false,HelpMessage="Remove the content for those Software Updates that will be removed from a Software Upgrade Group")]
    [switch]$RemoveContent,
    [parameter(Mandatory=$false,HelpMessage="Show a progressbar displaying the current operation")]
    [switch]$ShowProgress
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose "Determining SiteCode for Site Server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Debug "SiteCode: $($SiteCode)"
            }
        }
    }
    catch [Exception] {
        Throw "Unable to determine SiteCode"
    }
}
Process {
    try {
        # Enable support for wildcard search
        if (($SUGName.StartsWith("*")) -and ($SUGName.EndsWith("*"))) {
            Write-Verbose -Message "Query: SELECT * FROM SMS_AuthorizationList WHERE LocalizedDisplayName like '%$($SUGName.Replace('*',''))%'"
            $WmiFilter = "LocalizedDisplayName like '%$($SUGName)%'"
        }
        elseif ($SUGName.StartsWith("*")) {
            Write-Verbose -Message "Query: SELECT * FROM SMS_AuthorizationList WHERE LocalizedDisplayName like '%$($SUGName.Replace('*',''))'"
            $WmiFilter = "LocalizedDisplayName like '%$($SUGName)'"
        }
        elseif ($SUGName.EndsWith("*")) {
            Write-Verbose -Message "Query: SELECT * FROM SMS_AuthorizationList WHERE LocalizedDisplayName like '$($SUGName.Replace('*',''))%'"
            $WmiFilter = "LocalizedDisplayName like '$($SUGName)%'"
        }
        else {
            Write-Verbose -Message "Query: SELECT * FROM SMS_AuthorizationList WHERE LocalizedDisplayName like '$($SUGName)'"
            $WmiFilter = "LocalizedDisplayName like '$($SUGName)'"
        }
        if ($SUGName -match "\*") {
            $SUGName = $SUGName.Replace("*","")
            $WmiFilter = $WmiFilter.Replace("*","")
        }
        $SUGResults = (Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_AuthorizationList -ComputerName $SiteServer -Filter "$($WmiFilter)" -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($SUGResults -eq 1) {
            $AuthorizationList = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_AuthorizationList -ComputerName $SiteServer -Filter "$($WmiFilter)" -ErrorAction Stop
            $AuthorizationList = [wmi]"$($AuthorizationList.__PATH)"
            $UpdatesCount = $AuthorizationList.Updates.Count
            $UpdatesList = New-Object -TypeName System.Collections.ArrayList
            $RemovedUpdatesList = New-Object -TypeName System.Collections.ArrayList
            if ($PSBoundParameters["ShowProgress"]) {
                $ProgressCount = 0
            }
            foreach ($Update in ($AuthorizationList.Updates)) {
                $CIID = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_SoftwareUpdate -ComputerName $SiteServer -Filter "CI_ID = '$($Update)'" -ErrorAction Stop
                if ($PSBoundParameters["ShowProgress"]) {
                    $ProgressCount++
                    Write-Progress -Activity "Processing Software Updates in '$($SUGName)'" -Id 1 -Status "$($ProgressCount) / $($UpdatesCount)" -CurrentOperation "$($CIID.LocalizedDisplayName)" -PercentComplete (($ProgressCount / $UpdatesCount) * 100)
                }
                if ($CIID.IsExpired -eq $true) {
                    Write-Verbose -Message "Update '$($CIID.LocalizedDisplayName)' was expired and will be removed from '$($AuthorizationList.LocalizedDisplayName)'"
                    if ($CIID.CI_ID -notin $RemovedUpdatesList) {
                        $RemovedUpdatesList.Add($CIID.CI_ID) | Out-Null
                    }
                }
                elseif (($CIID.IsSuperseded -eq $true) -and (-not($PSBoundParameters["ExpiredOnly"]))) {
                    Write-Verbose -Message "Update '$($CIID.LocalizedDisplayName)' was superseded and will be removed from '$($AuthorizationList.LocalizedDisplayName)'"
                    if ($CIID.CI_ID -notin $RemovedUpdatesList) {
                        $RemovedUpdatesList.Add($CIID.CI_ID) | Out-Null
                    }
                }
                else {
                    if ($CIID.CI_ID -notin $UpdatesList) {
                        $UpdatesList.Add($CIID.CI_ID) | Out-Null
                    }
                }
            }
            # Process the list of Updates added to the ArrayList only if the count is less what's in the actualy Software Update Group
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
                                $ContentData = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Query "SELECT SMS_PackageToContent.ContentID,SMS_PackageToContent.PackageID from SMS_PackageToContent JOIN SMS_CIToContent on SMS_CIToContent.ContentID = SMS_PackageToContent.ContentID where SMS_CIToContent.CI_ID in ($($CI_ID))" -ComputerName $SiteServer -ErrorAction Stop
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
                            # Refresh content source for all Deployment Packages in the DeploymentPackageList array
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
        }
        elseif ($SUGResults -ge 1) {
            Write-Warning -Message "Specified Software Update Group name returned '$($SUGResults)' results, please be more specific"
        }
        else {
            Write-Warning -Message "Unable to locate a Software Update Group named '$($SUGName)'"
        }
    }
    catch [Exception] {
        Throw $_.Exception.Message
    }
}
End {
    if ($PSBoundParameters["ShowProgress"]) {
        Write-Progress -Activity "Enumerating Software Updates" -Completed -ErrorAction SilentlyContinue
    }
}