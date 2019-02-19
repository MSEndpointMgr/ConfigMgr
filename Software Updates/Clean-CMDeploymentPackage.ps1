<#
.SYNOPSIS
    Clean up a specific Deployment Package for Software Update content matching specific criteria.

.DESCRIPTION
    This script will perform a clean up operation for a specific Deployment Package. The operation will determine Software Updates
    content provisioned in the package eligible for removal based upon a set of criterias.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER PackageID
    Specify the Package ID for a Deployment Package that will be cleaned up.

.PARAMETER NonDeployedUpdates
    Use this switch to clean Software Updates that are not deployed, from the Deployment Package.

.PARAMETER NonRequiredUpdates
    Use this switch to clean Software Updates that are not required on any systems, from the Deployment Package.

.PARAMETER ShowProgress
    Show a progressbar displaying the current operation.

.EXAMPLE
    .\Clean-CMDeploymentPackage.ps1 -SiteServer "CM01" -PackageID "P0100001" -NonDeployedUpdates -NonRequiredUpdates -ShowProgress -Verbose

.NOTES
    FileName:    Clean-CMDeploymentPackage.ps1.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-08-15
    Updated:     2018-12-06
    
    Version history:
    1.0.0 - (2017-08-15) Script created
    1.0.1 - (2018-12-06) Updated the script logic to support all parameter switches being used together and added a new parameter for superseded updates
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify the Package ID for a Deployment Package that will be cleaned up.")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Z0-9]{3}[A-F0-9]{5}$")]
    [string]$PackageID,

    [parameter(Mandatory=$false, HelpMessage="Use this switch to clean Software Updates that are not deployed, from the Deployment Package.")]
    [switch]$NonDeployedUpdates,

    [parameter(Mandatory=$false, HelpMessage="Use this switch to clean Software Updates that are not required on any systems, from the Deployment Package.")]
    [switch]$NonRequiredUpdates,

    [parameter(Mandatory=$false, HelpMessage="Use this switch to clean Software Updates that are superseded, from the Deployment Package.")]
    [switch]$SupersededUpdates,

    [parameter(Mandatory=$false, HelpMessage="Show a progressbar displaying the current operation.")]
    [switch]$ShowProgress
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose -Message "Determining Site Code for Site server: '$($SiteServer)'"
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
}
Process {
    # Set ProgressCount for ShowProgress
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }

    try {
        # Validate that specified Deployment Package ID exist
        Write-Verbose -Message "Retrieving Deployment Package instance from SMS Provider"
        $DeploymentPackage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_SoftwareUpdatesPackage -ComputerName $SiteServer -Filter "PackageID = '$($PackageID)'" -ErrorAction Stop
        if ($DeploymentPackage -ne $null) {
            # Construct WQL query
            $WQLQuery = "SELECT DISTINCT SU.* FROM SMS_SoftwareUpdate AS SU JOIN SMS_CIToContent AS CTC ON SU.CI_ID = CTC.CI_ID JOIN SMS_PackageToContent AS PTC ON PTC.ContentID=CTC.ContentID WHERE (PTC.PackageID = '$($DeploymentPackage.PackageID)' AND SU.IsContentProvisioned = 1)"
            
            if (($PSBoundParameters.ContainsKey("NonDeployedUpdates")) -or ($PSBoundParameters.ContainsKey("NonRequiredUpdates")) -or ($PSBoundParameters.ContainsKey("SupersededUpdates"))) {
                $WQLQuery = -join @($WQLQuery, " AND (")
            }

            # Append WQL query to include Software Update instances that are not deployed
            if ($PSBoundParameters["NonDeployedUpdates"]) {
                Write-Verbose -Message "Extending the WQL query with non-deployed updates"
                $WQLQuery = -join @($WQLQuery, "SU.IsDeployed = 0 OR ")
            }

            # Append WQL query to include Software Update instances that are not required on any systems
            if ($PSBoundParameters["NonRequiredUpdates"]) {
                Write-Verbose -Message "Extending the WQL query with missing updates"
                $WQLQuery = -join @($WQLQuery, "SU.NumMissing = 0 OR ")
            }

            # Append WQL query to include Software Update instances that are superseded
            if ($PSBoundParameters["SupersededUpdates"]) {
                Write-Verbose -Message "Extending the WQL query with superseded updates"
                $WQLQuery = -join @($WQLQuery, "SU.IsSuperseded = 1 OR ")
            }      
            
            if (($PSBoundParameters.ContainsKey("NonDeployedUpdates")) -or ($PSBoundParameters.ContainsKey("NonRequiredUpdates")) -or ($PSBoundParameters.ContainsKey("SupersededUpdates"))) {
                $WQLQuery = $WQLQuery.Substring(0, $WQLQuery.Length-4)
                $WQLQuery = -join @($WQLQuery, ")")
            }            
            
            # Determine Software Update instances matching non-required and non-deployed criteria
            Write-Verbose -Message "WQL query: $($WQLQuery)"
            $SoftwareUpdates = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -ComputerName $SiteServer -Query $WQLQuery -ErrorAction Stop | Select-Object -Property CI_ID, LocalizedDisplayName

            if ($SoftwareUpdates -ne $null) {
                $SoftwareUpdatesCount = ($SoftwareUpdates | Measure-Object).Count
                foreach ($SoftwareUpdate in $SoftwareUpdates) {
                    # Show progress per content ID
                    if ($PSBoundParameters["ShowProgress"]) {
                        $ProgressCount++
                        Write-Progress -Activity "Cleaning Software Updates in '$($DeploymentPackage.Name)'" -Id 1 -Status "$($ProgressCount) / $($SoftwareUpdatesCount)" -CurrentOperation "Removing content for: $($SoftwareUpdate.LocalizedDisplayName)" -PercentComplete (($ProgressCount / $SoftwareUpdatesCount) * 100)
                    }

                    try {
                        # Determine content data for current Software Update
                        Write-Verbose -Message "Collecting content data for Software Update: $($SoftwareUpdate.LocalizedDisplayName)"
                        $ContentData = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Query "SELECT SMS_PackageToContent.ContentID,SMS_PackageToContent.PackageID from SMS_PackageToContent JOIN SMS_CIToContent on SMS_CIToContent.ContentID = SMS_PackageToContent.ContentID where SMS_CIToContent.CI_ID in ($($SoftwareUpdate.CI_ID))" -ComputerName $SiteServer -ErrorAction Stop
                        Write-Verbose -Message "Found '$(($ContentData | Measure-Object).Count)' content objects"

                        if ($ContentData -ne $null) {
                            foreach ($Content in $ContentData) {
                                # Remove Software Update content data from Deployment Package
                                if ($PSCmdlet.ShouldProcess("$($DeploymentPackage.PackageID)","Remove ContentID '$($Content.ContentID)'")) {
                                    Write-Verbose -Message "Attempting to remove ContentID '$($Content.ContentID)' from PackageID '$($DeploymentPackage.PackageID)'"

                                    $RemoveInvocation = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Path "SMS_SoftwareUpdatesPackage.PackageID='$($DeploymentPackage.PackageID)'" -Name RemoveContent -ArgumentList @($false, $Content.ContentID) -ComputerName $SiteServer -ErrorAction Stop
                                    if ($RemoveInvocation.ReturnValue -eq 0) {
                                        Write-Verbose -Message "Successfully removed ContentID '$($Content.ContentID)' from PackageID '$($DeploymentPackage.PackageID)'"
                                    }
                                }
                            }
                        }
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "Unable to remove Software Update content data from Deployment Package ID. Error message: $($_.Exception.Message)"
                    }
                }

                # Refresh Deployment Package
                if ($PSCmdlet.ShouldProcess("$($DeploymentPackage.PackageID)","Refresh Package")) {
                    Write-Verbose -Message "Attempting to refresh content source for Deployment Package '$($DeploymentPackage.PackageID)'"

                    $RefreshInvocation = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Path "SMS_SoftwareUpdatesPackage.PackageID='$($DeploymentPackage.PackageID)'" -Name RefreshPkgSource -ComputerName $SiteServer -ErrorAction Stop
                    if ($RefreshInvocation.ReturnValue -eq 0) {
                        Write-Verbose -Message "Successfully refreshed Deployment Package '$($DeploymentPackage.PackageID)'"
                    }
                }
            }
            else {
                Write-Warning -Message "Unable to find Software Updates matching the search criteria"   
            }
        }
        else {
            Write-Warning -Message "Unable to detect a Deployment Package with given Package ID"
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine Software Update items eligible for removal from given Deployment Package ID. Error message: $($_.Exception.Message)"
    }
}
End {
    if ($PSBoundParameters["ShowProgress"]) {
        Write-Progress -Activity "Cleaning Software Updates in '$($DeploymentPackage.Name)'" -Completed -ErrorAction SilentlyContinue
    }
}