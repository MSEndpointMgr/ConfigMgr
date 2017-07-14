<#
.SYNOPSIS
    Update content for Deployment Types
.DESCRIPTION
    This script will update content for each Deployment Type on an Application that has a distribution failure of state 7
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.EXAMPLE
    .\Invoke-CMDeploymentTypeContentUpdate.ps1 -SiteServer MOASSCCM03 -Verbose
.NOTES
    Script name: Invoke-CMDeploymentTypeContentUpdate.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2014-11-17
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,
    [parameter(Mandatory=$false, HelpMessage="Show a progressbar displaying the current operation")]
    [switch]$ShowProgress
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose -Message "Determining SiteCode for Site Server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Debug -Message "SiteCode: $($SiteCode)"
            }
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine SiteCode" ; break
    }
    # Load ConfigMgr module
    try {
        Import-Module -Name ConfigurationManager -ErrorAction Stop -Verbose:$false
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message ; break
    }
    # Get current location
    $CurrentLocation = $PSScriptRoot
}
Process {
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }
    # Get all Applications
    $AppHashTable = New-Object -TypeName System.Collections.Hashtable
    Write-Verbose -Message "Reading all Applications"
    $Applications = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_ApplicationLatest -Filter "isExpired = 'False'"
    foreach ($Application in $Applications) {
        $Application.Get()
        if ($Application.PackageID -ne "") {
            $AppHashTable.Add($Application.PackageID, $Application.ModelName)
        }
    }
    Write-Verbose -Message "Querying for packages in a failed distribution state"
    $DistributionFailures = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_PackageStatusDistPointsSummarizer -Filter "State = '7'"
    if ($DistributionFailures -ne $null) {
        foreach ($ContentFailure in $DistributionFailures) {
            if ($AppHashTable["$($ContentFailure.PackageID)"]) {
                Write-Verbose -Message "Found Application with PackageID '$($ContentFailure.PackageID)', will attempt to update content"
                $ApplicationModelName = $AppHashTable["$($ContentFailure.PackageID)"]
                $ApplicationName = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_ApplicationLatest -Filter "ModelName = '$($ApplicationModelName)'" | Select-Object -ExpandProperty LocalizedDisplayName
                $DeploymentTypes = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_DeploymentType -Filter "(AppModelName = '$($ApplicationModelName)') AND (isLatest = 'True')"
                foreach ($DeploymentType in $DeploymentTypes) {
                    $SiteDrive = $SiteCode + ":"
                    Set-Location -Path $SiteDrive -Verbose:$false
                    $DeploymentTypeName = $DeploymentType | Select-Object -ExpandProperty LocalizedDisplayName
                    if ($PSCmdlet.ShouldProcess($DeploymentTypeName, "Update Content")) {
                        Update-CMDistributionPoint -DeploymentTypeName $DeploymentTypeName -ApplicationName $ApplicationName -Verbose:$false
                        Write-Verbose -Message "Successfully updated content for DeploymentType '$($DeploymentTypeName)' on Application '$($ApplicationName)'"
                    }
                }
                Set-Location -Path $CurrentLocation -Verbose:$false
            }
        }
    }
    else {
        Write-Output -InputObject "There where no unsuccessful content distributions found"
    }
    Set-Location -Path $CurrentLocation -Verbose:$false
}