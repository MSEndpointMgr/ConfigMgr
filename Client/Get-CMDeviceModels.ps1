<#
.SYNOPSIS
    Get all device models present in ConfigMgr

.DESCRIPTION
    This script will get all device models present in ConfigMgr. It requires Hardware Inventory to be enabled and that the devices have reported a full hardware inventory report at least once.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.EXAMPLE
    # Get all device models on a Primary Site server called 'CM01':
    .\Get-CMDeviceModels.ps1 -SiteServer CM01
    
.NOTES
    FileName:    Get-CMDeviceModels.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2015-04-10
    Updated:     2019-03-12

    Version history:
    1.0.0 - (2015-04-10) Script created
    1.0.1 - (2019-03-12) Added manufacturer as a column in the output
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer
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
    # ArrayList to store the models in
    $ModelsArrayList = New-Object -TypeName System.Collections.ArrayList

    # Enumerate through all models
    $ComputerSystems = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_G_System_COMPUTER_SYSTEM -ComputerName $SiteServer | Select-Object -Property Model, Manufacturer
    
    # Add model to ArrayList if not present
    if ($ComputerSystems -ne $null) {
        foreach ($ComputerSystem in $ComputerSystems) {
            if ($ComputerSystem.Model -notin $ModelsArrayList.Model) {
                $PSObject = [PSCustomObject]@{
                    Model = $ComputerSystem.Model
                    Manufacturer = $ComputerSystem.Manufacturer
                }
                $ModelsArrayList.Add($PSObject) | Out-Null
            }
        }
    }
    Write-Output $ModelsArrayList
}