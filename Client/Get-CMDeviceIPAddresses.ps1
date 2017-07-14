<#
.SYNOPSIS
    List all IP addresses for each device in a collection
.DESCRIPTION
    Get a formatted list of each IP address for all devices in a collection in ConfigMgr
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.EXAMPLE
    .\Get-CMDeviceIPAddresses.ps1 -SiteServer CM01 -CollectionName "All Inactive Systems"
.NOTES
    Script name: Get-CMDeviceIPAddresses.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-12-14
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true,HelpMessage="Site Server where SQL Server Reporting Services are installed")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1})]
    [ValidateNotNullOrEmpty()]
    [string]$SiteServer,
    [parameter(Mandatory=$true,HelpMessage="Specify a collection")]
    [ValidateNotNullOrEmpty()]
    [string]$CollectionName
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
}
Process {
    $CollectionID = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "Name like '$($CollectionName)'" | Select-Object -ExpandProperty CollectionID
    $CollectionMembers = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_FullCollectionMembership -ComputerName $SiteServer -Filter "CollectionID like '$($CollectionID)'" | Select-Object -Property Name
    foreach ($CollectionMember in $CollectionMembers) {
        $DeviceInfo = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_R_System -ComputerName $SiteServer -Filter "Name like '$($CollectionMember.Name)'" | Select-Object -Property Name, IPAddresses
        if ($DeviceInfo.IPAddresses.Count -ge 2) {
            $IPCount = 1
            foreach ($IPAddress in $DeviceInfo.IPAddresses) {
                if ($IPCount -eq 1) {
                    $PSObject = [PSCustomObject]@{
                        Name = $DeviceInfo.Name
                        IPAddresses = $IPAddress
                    }
                }
                else {
                    $PSObject = [PSCustomObject]@{
                        Name = ""
                        IPAddresses = $IPAddress
                    }
                }
                Write-Output -InputObject $PSObject
                $IPCount++
            }
        }
        else {
            $PSObject = [PSCustomObject]@{
                Name = $DeviceInfo.Name
                IPAddresses = $DeviceInfo | Select-Object -ExpandProperty IPAddresses
            }
            Write-Output -InputObject $PSObject
        }
    } 
} 
