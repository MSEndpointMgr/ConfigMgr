<#
.SYNOPSIS
    List all Applications in ConfigMgr 2012 that have one or more dependencies configured
.DESCRIPTION
    This script will enumerate through all the Applications in ConfigMgr 2012 and output a custom object for those applications
    that have a dependency configured for any of the DeploymentTypes
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER ShowProgress
    Show a progressbar displaying the current operation
.EXAMPLE
    List Applications with dependencies on a Primary Site server called 'CM01':
    .\Get-CMApplicationWithDependency.ps1 -SiteServer -ShowProgress
.NOTES
    Script name: Get-CMApplicationWithDependency.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-09-23
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
    # Load ConfigMgr application assemblies
    try {
        Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.dll") -ErrorAction Stop
        Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.Extender.dll") -ErrorAction Stop
        Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.MsiInstaller.dll") -ErrorAction Stop
    }
    catch [System.UnauthorizedAccessException] {
	    Write-Warning -Message "Access was denied when attempting to load ApplicationManagement dll's" ; break
    }
    catch [System.Exception] {
	    Write-Warning -Message "Unable to load required ApplicationManagement dll's. Make sure that you're running this tool on system where the ConfigMgr console is installed and that you're running the tool elevated" ; break
    }
}
Process {
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }
    try {
        $Applications = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class "SMS_ApplicationLatest" -ComputerName $SiteServer -ErrorAction Stop
        $ApplicationCount = ($Applications | Measure-Object).Count
        foreach ($Application in $Applications) {
            if ($PSBoundParameters["ShowProgress"]) {
                $ProgressCount++
                Write-Progress -Activity "Enumerating Applications for dependencies" -Status "Application $($ProgressCount) / $($ApplicationCount)" -Id 1 -PercentComplete (($ProgressCount / $ApplicationCount) * 100)
            }
            $ApplicationName = $Application.LocalizedDisplayName
            # Get Application object including Lazy properties
            $Application.Get()
            # Deserialize SDMPakageXML property from string
            $ApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($Application.SDMPackageXML, $true)
            foreach ($DeploymentType in $ApplicationXML.DeploymentTypes) {
                if ([int]$DeploymentType.Dependencies.Count -ge 1) {
                    $PSObject = [PSCustomObject]@{
                        ApplicationName = $ApplicationName
                        DeploymentTypeName = $DeploymentType.Title
                        DependencyCount = $DeploymentType.Dependencies.Count
                        DependencyGroupName = $DeploymentType.Dependencies.Name
                        DependentApplication = $DeploymentType.Dependencies.Expression.Operands | ForEach-Object {
                            Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class "SMS_ApplicationLatest" -ComputerName $SiteServer -Filter "CI_UniqueID like '$($_.ApplicationAuthoringScopeId)%$($_.ApplicationLogicalName)%'" | Select-Object -ExpandProperty LocalizedDisplayName
                        }
                        EnforceDesiredState = $DeploymentType.Dependencies.Expression.Operands.EnforceDesiredState
                    }
                    Write-Output -InputObject $PSObject
                }
            }
        }
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message ; break
    }
}
End {
    if ($PSBoundParameters["ShowProgress"]) {
        Write-Progress -Activity "Enumerating Applications for dependencies" -Id 1 -Completed
    }
}