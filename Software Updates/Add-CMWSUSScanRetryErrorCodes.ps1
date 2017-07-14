<#
.SYNOPSIS
    Add an error code to the WSUS Scan Retry Error Codes list that will instruct a ConfigMgr 2012 client to switch Software Update Point
.DESCRIPTION
    Use this script to add an error code to the WSUS Scan Retry Error Codes list that will instruct a ConfigMgr 2012 client to switch Software Update Point once the threshold of failed scans has been reached
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER ErrorCode
    Specify the error code to add as hexadecimal, e.g. 0x80072ee2
.EXAMPLE
    .\Add-CMWSUSScanRetryErrorCodes.ps1 -SiteServer CM01 -ErrorCode 0x80072ee2
    Add the error code '0x80072ee2' to the WSUS Scan Retry Error Codes list on a Primary Site server called 'CM01':
.NOTES
    Script name: Add-CMWSUSScanRetryErrorCodes.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-04-07
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true,HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,
    [parameter(Mandatory=$true,HelpMessage="Specify the error code to add as hexadecimal, e.g. 0x80072ee2")]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1,10)]
    [ValidatePattern("^0{1}[xX]{1}[0-9a-fA-F]{8}$")]
    [string]$ErrorCode
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
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access to WMI on target '$($SiteServer)' was denied" ; break
    }
    catch [Exception] {
        Write-Warning -Message "Unable to determine SiteCode" ; break
    }
    # Convert hexadecimal error code to decimal
    try {
        $RetryCodeUInt = [System.Convert]::ToUInt32($ErrorCode, 16) -as [string]
        Write-Verbose -Message "Converted error code '$($ErrorCode)' to '$($RetryCodeUInt)'"
    }
    catch [Exception] {
        Write-Warning -Message "Unable to convert error code '$($ErrorCode)' to decimal" ; break
    }
    # Define ErrorActionPreference
    $ErrorActionPreference = "Stop"
}
Process {
    # Get all WSUS Components
    $WSUSComponents = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_SCI_Component -ComputerName $SiteServer -Filter "ComponentName like 'SMS_WSUS_CONFIGURATION_MANAGER'"
    if ($WSUSComponents -ne $null) {
        foreach ($WSUSObject in $WSUSComponents) {
            $WSUSObjectProps = $WSUSObject.Props
            foreach ($WSUSObjectProp in $WSUSObjectProps) {
                # Get the WSUS Scan Retry Error Codes object
                if ($WSUSObjectProp.PropertyName -like "WSUS Scan Retry Error Codes") {
                    if ($WSUSObjectProp.Value2 -notmatch $RetryCodeUInt) {
                        $UpdatedRetryCodes = $WSUSObjectProp.Value2.Replace("}","") + ", $($RetryCodeUInt)"
                        $UpdatedRetryCodes = $UpdatedRetryCodes.Insert($UpdatedRetryCodes.Length, "}")
                        $WSUSObjectProp.Value2 = $UpdatedRetryCodes
                        # Update WMI object with new Props object
                        if ($PSCmdlet.ShouldProcess($WSUSObject.ItemName, "Update Scan Retry Codes")) {
                            try {
                                $WSUSObject.Props = $WSUSObjectProps
                                $WSUSObject.Put() | Out-Null
                            }
                            catch [Exception] {
                                Write-Warning -Message "An error occured while attempting to update WMI object" ; break
                            }
                        }
                    }
                    else {
                        Write-Warning -Message "Specified error code is already present on object '$($WSUSObject.ItemName)'"
                    }
                }
            }
        }
    }
    else {
        Write-Warning -Message "No WSUS Components was found"
    }
}