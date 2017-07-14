<#
.SYNOPSIS
    Get all Applications with a requirement rule for Primary Device
.DESCRIPTION
    This script will get all Applications with a requirement rule for Primary Device
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER ShowProgress
    Show a progressbar displaying the current operation
.EXAMPLE
    .\Get-CMApplicationRequirementRulePrimaryDevice.ps1 -SiteServer CM01 -ShowProgress
    Get all Applications with a requirement rule for Primary Device while showing the progress, on a Primary Site server called 'CM01':
.NOTES
    Script name: Get-CMApplicationRequirementRulePrimaryDevice.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-03-26
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
        Write-Warning -Message "Unable to determine SiteCode" ; break
    }
    # Load assemblies
    try {
        Add-Type -Path (Join-Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName "Microsoft.ConfigurationManagement.ApplicationManagement.dll")
        Add-Type -Path (Join-Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName "Microsoft.ConfigurationManagement.ApplicationManagement.Extender.dll")
        Add-Type -Path (Join-Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName "Microsoft.ConfigurationManagement.ApplicationManagement.MsiInstaller.dll")
    }
    catch [Exception] {
        Write-Warning -Message "Unable to load required assemblies" ; break
    }
}
Process {
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }
    $Applications = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class "SMS_Application" -ComputerName $SiteServer -Filter 'IsLatest = "True"'
    $ApplicationCount = ($Applications | Measure-Object).Count
    foreach ($Application in $Applications) {
        if ($PSBoundParameters["ShowProgress"]) {
            $ProgressCount++
        }
        $LocalizedDisplayName = $Application.LocalizedDisplayName
        $CurrentApplication = [wmi]$Application.__PATH
        $ApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($CurrentApplication.SDMPackageXML,$True)
        foreach ($DeploymentType in $ApplicationXML.DeploymentTypes) {
            if ($PSBoundParameters["ShowProgress"]) {
                Write-Progress -Activity "Enumerating Applications for Primary User requirement rule" -Id 1 -Status "$($ProgressCount) / $($ApplicationCount)" -CurrentOperation "Current application: $($LocalizedDisplayName)" -PercentComplete (($ProgressCount / $ApplicationCount) * 100)
            }
            if (($DeploymentType.Requirements.Expression.Operands.LogicalName -like "PrimaryDevice") -and ($DeploymentType.Requirements.Expression.Operator.OperatorName -like "Equals") -and ($DeploymentType.Requirements.Expression.Operands.Value -eq $true)) {
                $PSObject = [PSCustomObject]@{
                    ApplicationName = $LocalizedDisplayName
                    DeploymentTypeName = $DeploymentType.Title
                    RequirementEnabled = $true
                    LogicalName = $DeploymentType.Requirements.Expression.Operands.LogicalName
                    OperatorName = $DeploymentType.Requirements.Expression.Operator.OperatorName
                    Value = $DeploymentType.Requirements.Expression.Operands.Value
                }
                Write-Output $PSObject
            }
        }
    }
}
End {
    if ($PSBoundParameters["ShowProgress"]) {
        Write-Progress -Activity "Enumerating Applications for Primary User requirement rule" -Id 1 -Completed
    }
}
