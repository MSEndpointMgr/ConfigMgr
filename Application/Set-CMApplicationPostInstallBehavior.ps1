<#
.SYNOPSIS
    Use this script to set the PostInstall behavior for Applications in ConfigMgr 2012
.DESCRIPTION
    Use this script to set the PostInstall behavior for Applications in ConfigMgr 2012
.PARAMETER SiteServer
    (DefaultParameterSet)
    Primary Site server name
.PARAMETER ApplicationName
    (SingleApp)
    Specify a name of an application
.PARAMETER PostInstallBehavior
    (SingleApp, MultipleApps)
    Specify a Post Install Behavior, valid options are:

    BasedOnExitCode
    NoAction
    ForceLogOff
    ForceReboot
    ProgramReboot
.PARAMETER Recurse
    (MultipleApps)
    When specified, the PostInstallBehavior setting will be set on all applications with a DeploymentType of MSI or Script
.EXAMPLE
    Set PostInstallBehavior setting 'NoAction' on an application called 'TestApp1' on a Primary Site server called 'CM01':

    .\Set-CMApplicationPostInstallBehavior.ps1 -SiteServer CM01 -ApplicationName "TestApp1" -PostInstallBehavior NoAction
.EXAMPLE 
    Set PostInstallBehavior setting 'BasedOnExitCode' for all applicable applications on a Primary Site server called 'CM01' and show verbose output:

    .\Set-CMApplicationPostInstallBehavior.ps1 -SiteServer CM01 -PostInstallBehavior NoAction -Recurse -Verbose
.NOTES
    Script name: Set-CMApplicationPostInstallBehavior.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2014-09-30
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Position=0, Mandatory=$true, HelpMessage="Specify Primary Site server")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 2})]
    [string]$SiteServer = "$($env:COMPUTERNAME)",
    [parameter(Position=1, HelpMessage="Specify a specific application name")]
    [parameter(ParameterSetName="SingleApp")]
    [string]$ApplicationName,
    [parameter(Position=2,Mandatory=$true, HelpMessage="Specify the Post Install Behavior setting")]
    [parameter(ParameterSetName="SingleApp")]
    [parameter(ParameterSetName="MultipleApps")]
    [ValidateSet(
    "BasedOnExitCode",
    "NoAction",
    "ForceLogOff",
    "ForceReboot",
    "ProgramReboot"
    )]
    [string]$PostInstallBehavior,
    [parameter(Position=2, HelpMessage="Make changes to all applications")]
    [parameter(ParameterSetName="MultipleApps")]
    [switch]$Recurse
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose "Determining SiteCode for Site Server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer
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
    # Load assemblies
    try {
        [System.Reflection.Assembly]::LoadFrom((Join-Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName "Microsoft.ConfigurationManagement.ApplicationManagement.dll")) | Out-Null
        [System.Reflection.Assembly]::LoadFrom((Join-Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName "Microsoft.ConfigurationManagement.ApplicationManagement.Extender.dll")) | Out-Null
        [System.Reflection.Assembly]::LoadFrom((Join-Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName "Microsoft.ConfigurationManagement.ApplicationManagement.MsiInstaller.dll")) | Out-Null
    }
    catch [Exception] {
        Throw "Unable to load assemblies"
    }
    # Get Application(s)
    try {
        if ($PSBoundParameters["Recurse"].IsPresent) {
            Write-Verbose "Recurse mode selected, retrieving all application objects from WMI"
            $Applications = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_ApplicationLatest -ComputerName $SiteServer
        }
        else {
            Write-Verbose "Specific application specified, retrieving object from WMI"
            $Applications = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_ApplicationLatest -ComputerName $SiteServer -Filter "LocalizedDisplayName like '$($ApplicationName)'"
        }
    }
    catch [Exception] {
        Throw "Unable to get applications"
    }
}
Process {
    # Set PostInstallBehavior on selected applications
    try {
        $Applications | ForEach-Object {
            $Application = [wmi]$_.__PATH
            Write-Verbose "Deserializing SDMPackageXML property for application: '$($Application.LocalizedDisplayName)'"
            $ApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($Application.SDMPackageXML,$True)
            foreach ($DeploymentType in $ApplicationXML.DeploymentTypes) {
                if (($DeploymentType.Installer.Technology -like "MSI") -or ($DeploymentType.Installer.Technology -like "Script")) {
                    if (-not($DeploymentType.Installer.PostInstallBehavior -like "$($PostInstallBehavior)")) {
                        Write-Verbose "Set PostInstallBehavior setting to: '$($PostInstallBehavior)'"
                        if ($PSCmdlet.ShouldProcess("Application: $($Application.LocalizedDisplayName)", "PostInstallBehavior: $($PostInstallBehavior)")) {
                            $DeploymentType.Installer.PostInstallBehavior = "$($PostInstallBehavior)"
                                Write-Verbose "Serializing XML back to String"
                                $UpdatedXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToString($ApplicationXML, $True)
                                $Application.SDMPackageXML = $UpdatedXML
                                Write-Verbose "Saving changes to WMI object"
                                $Application.Put() | Out-Null
                        }
                    }
                    else {
                        Write-Verbose "PostInstallBehavior is already set to '$($PostInstallBehavior)'"
                    }
                }
                else {
                    Write-Verbose "Unsupported DeploymentType technology detected: '$($DeploymentType.Installer.Technology)'"
                }
            }
        }
    }
    catch [Exception] {
        Throw "Unable to set PostInstallBehavior"
    }
}