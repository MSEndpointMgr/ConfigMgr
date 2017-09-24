<#
.SYNOPSIS
    Set service state for a Cloud Management Gateway resource in Configuration Manager.

.DESCRIPTION
    This script can either start or stop a Cloud Management Gateway resource in Configuration Manager.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER ShowProgress
    Show a progressbar displaying the current operation.

.EXAMPLE
    # Start the Cloud Management Gateway with a cloud service name of 'ContosoCMG.cloudapp.net':
    .\Set-CMCloudMAnagementGatewayState.ps1 -CloudServiceName 'ContosoCMG.cloudapp.net' -ServiceState Start -Verbose

    # Stop the Cloud Management Gateway with a cloud service name of 'ContosoCMG.cloudapp.net':
    .\Set-CMCloudMAnagementGatewayState.ps1 -CloudServiceName 'ContosoCMG.cloudapp.net' -ServiceState Stop -Verbose

.NOTES
    FileName:    Set-CMCloudManagementGatewayState.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-09-24
    Updated:     2017-09-24
    
    Version history:
    1.0.0 - (2017-09-24) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify the Cloud Management Gateway service name, e,g, contosocmg.cloudapp.net.")]
    [ValidateNotNullOrEmpty()]
    [string]$CloudServiceName,    

    [parameter(Mandatory=$true, HelpMessage="Specify the Cloud Management Gateway service state.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Start", "Stop")]
    [string]$ServiceState
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
    catch {
        Write-Warning -Message "Unable to determine Site Code" ; break
    }

    # Load ConfigMgr module
    try {
        $SiteDrive = $SiteCode + ":"
        Import-Module -Name ConfigurationManager -ErrorAction Stop -Verbose:$false
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch {
        try {
            Import-Module -Name (Join-Path -Path (($env:SMS_ADMIN_UI_PATH).Substring(0,$env:SMS_ADMIN_UI_PATH.Length-5)) -ChildPath "\ConfigurationManager.psd1") -Force -ErrorAction Stop -Verbose:$false
            if ((Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue | Measure-Object).Count -ne 1) {
                New-PSDrive -Name $SiteCode -PSProvider "AdminUI.PS.Provider\CMSite" -Root $SiteServer -ErrorAction Stop -Verbose:$false | Out-Null
            }
        }
        catch [System.UnauthorizedAccessException] {
            Write-Warning -Message "Access denied" ; break
        }
        catch {
            Write-Warning -Message "$($_.Exception.Message). Line: $($_.InvocationInfo.ScriptLineNumber)" ; break
        }
    }

    # Determine and set location to the CMSite drive
    $CurrentLocation = $PSScriptRoot
    Set-Location -Path $SiteDrive -ErrorAction Stop -Verbose:$false

    # Disable Fast parameter usage check for Lazy properties
    $CMPSSuppressFastNotUsedCheck = $true

    # Construct table of Cloud Management Gateway states
    $StateTable = @{
        99 = "Deleting"
        6 = "Stopped"
        5 = "Stopping"
        4 = "Deployment starting"
        1 = "Provisioning"
        0 = "Running"
    }
}
Process {
    # Get Cloud Management Gateway resource object
    try {
        Write-Verbose -Message "Attempting to retrieve Cloud Management Gateway resource with service name '$($CloudServiceName)'"
        $CloudManagementGateway = Get-CMCloudManagementGateway -Name $CloudServiceName -ErrorAction Stop -Verbose:$false
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to retrieve Cloud Management Gateway resource. Error message: $($_.Exception.Message)"
    }

    if ($CloudManagementGateway -ne $null) {
        try {
            switch ($ServiceState) {
                "Start" {
                    if ($CloudManagementGateway.State -eq 6) {
                        Write-Verbose -Message "Attempting to start Cloud Management Gateway resource '$($CloudServiceName)'"
                        $Invocation = Start-CMCloudManagementGateway -InputObject $CloudManagementGateway -ErrorAction Stop -Verbose:$false
                    }
                    else {
                        Write-Verbose -Message "Cloud Management Gateway is currently in the '$($StateTable[[int]$CloudManagementGateway.State])', will not attempt to start resource"
                    }
                }
                "Stop" {
                    if ($CloudManagementGateway.State -eq 0) {
                        Write-Verbose -Message "Attempting to stop Cloud Management Gateway resource '$($CloudServiceName)'"
                        $Invocation = Stop-CMCloudManagementGateway -InputObject $CloudManagementGateway -ErrorAction Stop -Verbose:$false
                    }
                    else {
                        Write-Verbose -Message "Cloud Management Gateway is currently in the '$($StateTable[[int]$CloudManagementGateway.State])', will not attempt to start resource"
                    }
                }
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to retrieve Cloud Management Gateway resource. Error message: $($_.Exception.Message)" ; break
        }
    }
    else {
        Write-Warning -Message "Unable to retrieve Cloud Management Gateway resource, please enter a valid Cloud Service Name"
    }
}
End {
    Set-Location -Path $CurrentLocation
}