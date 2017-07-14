<#
.SYNOPSIS
    Convert a Software Update CI_ID or CI_UniqueID property into KB and Description
.DESCRIPTION
    Convert a Software Update CI_ID or CI_UniqueID property into KB and Description
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER CIID
    Specify the CI_ID to convert to a Software Update
.PARAMETER CIUniqueID
    Specify the CI_UniqueID to convert to a Software Update
.EXAMPLE
    .\ConvertTo-CMSoftwareUpdate.ps1 -SiteServer CM01 -CIID 16855151
    .\ConvertTo-CMSoftwareUpdate.ps1 -SiteServer CM01 -CIUniqueID 79e81e3e-97f6-4059-8a25-6732f8ec0a94
.NOTES
    Script name: ConvertTo-CMSoftwareUpdate.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-08-21
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, ParameterSetName="CIID", HelpMessage="Site server name with SMS Provider installed")]
    [parameter(ParameterSetName="CIUniqueID")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [ValidateNotNullorEmpty()]
    [string]$SiteServer,
    [parameter(Mandatory=$true, ParameterSetName="CIID", HelpMessage="Specify the CI_ID to convert to a Software Update")]
    [ValidateNotNullorEmpty()]
    [string]$CIID,
    [parameter(Mandatory=$true, ParameterSetName="CIUniqueID", HelpMessage="Specify the CI_UniqueID to convert to a Software Update")]
    [ValidateNotNullorEmpty()]
    [string]$CIUniqueID
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
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message ; break
    }
}
Process {
    try {
        if ($PSBoundParameters["CIID"]) {
            $SoftwareUpdates = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_SoftwareUpdate -Filter "CI_ID like '$($CIID)'" -ErrorAction Stop
        }
        if ($PSBoundParameters["CIUniqueID"]) {
            $SoftwareUpdates = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_SoftwareUpdate -Filter "CI_UniqueID like '$($CIUniqueID)'" -ErrorAction Stop
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message ; break
    }
    if ($SoftwareUpdates -ne $null) {
        foreach ($SoftwareUpdate in $SoftwareUpdates) {
            $PSObject = [PSCustomObject]@{
                ArticleID = "KB" + $SoftwareUpdate.ArticleID
                Description = $SoftwareUpdate.LocalizedDisplayName
            }
            Write-Output $PSObject
        }
    }
    else {
        Write-Warning -Message "No Software Update was found matching the specified search criteria"
    }
}