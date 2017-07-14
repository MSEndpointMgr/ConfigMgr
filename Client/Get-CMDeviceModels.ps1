<#
.SYNOPSIS
    Get all device models present in ConfigMgr 2012
.DESCRIPTION
    This script will get all device models present in ConfigMgr 2012. It requires Hardware Inventory to be enabled and that the devices have reported a full hardware inventory report at least once.
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.EXAMPLE
    .\Get-CMDeviceModels.ps1 -SiteServer CM01
    Get all device models on a Primary Site server called 'CM01':
.NOTES
    Script name: Get-CMDeviceModels.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-04-10
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
    $Models = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_G_System_COMPUTER_SYSTEM | Select-Object -Property Model
    # Add model to ArrayList if not present
    if ($Models -ne $null) {
        foreach ($Model in $Models) {
            if ($Model.Model -notin $ModelsArrayList) {
                $ModelsArrayList.Add($Model.Model) | Out-Null
            }
        }
    }
    # Output the members of the ArrayList
    if ($ModelsArrayList.Count -ge 1) {
        foreach ($ModelItem in $ModelsArrayList) {
            $PSObject = [PSCustomObject]@{
                Model = $ModelItem
            }
            Write-Output $PSObject
        }
    }
}