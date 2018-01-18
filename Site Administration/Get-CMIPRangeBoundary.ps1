<#
.SYNOPSIS
    Check if a specific IP address can be matched for a boundary in ConfigMgr.

.DESCRIPTION
    Check if a specific IP address can be matched for a boundary in ConfigMgr.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER IPAddress
    IP address e.g. 192.168.1.15.

.EXAMPLE
    .\Get-CMIPAddressBoundary.ps1 -SiteServer CM01 -IPAddress 192.168.1.15

.NOTES
    FileName:    Get-CMIPAddressBoundary.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2014-04-15
    Updated:     2017-12-07
    
    Version history:
    1.0.0 - (2014-04-15) Script created
    1.0.1 - (2017-12-07) Complete re-write of the script and added helper function to determine bit converted integer value
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site Server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="IP address e.g. 192.168.1.15.")]
    [ValidateNotNullOrEmpty()]
    [string]$IPAddress
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
    # Functions
    function Get-IPAddressInteger {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$IPAddress
        )
        Process {
            # Convert IP address to integer
            $AddressBytes = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
            [Array]::Reverse($AddressBytes)
            $IPAddressInteger = [System.BitConverter]::ToUInt32($AddressBytes, 0)

            return $IPAddressInteger
        }
    }

    # Get all boundaries
    $Boundaries = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Boundary -ComputerName $SiteServer -Filter "BoundaryType = 3"
    if (($Boundaries -ne $null) -and ($Boundaries | Measure-Object).Count -ge 1) {
        foreach ($Boundary in $Boundaries) {
            # Get IP address integer
            $IPAddressInteger = Get-IPAddressInteger -IPAddress $IPAddress

            # Get boundary range start integer
            $IPAddressStartInteger = Get-IPAddressInteger -IPAddress ($Boundary.Value.Split("-")[0])

            # Get bounday range end integer
            $IPAddressEndInteger = Get-IPAddressInteger -IPAddress ($Boundary.Value.Split("-")[1])

            # Perform check if IP address is within boundary
            if (($IPAddressStartInteger -le $IPAddressInteger) -and ($IPAddressInteger -le $IPAddressEndInteger)) {
                $PSCustomObject = [PSCustomObject]@{
                    DisplayName = $Boundary.DisplayName
                    BoundaryRange = $Boundary.Value
                    GroupCount = $Boundary.GroupCount
                }
                Write-Output -InputObject $PSCustomObject
            }
        }
    }
    else {
        Write-Warning -Message "Unable to detect any IP-range boundary objects"
    }
}