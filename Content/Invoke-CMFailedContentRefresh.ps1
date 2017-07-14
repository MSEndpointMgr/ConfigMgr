<#
.SYNOPSIS

.DESCRIPTION

.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER ShowProgress
    Show a progressbar displaying the current operation
.EXAMPLE
    
.NOTES
    Script name: <script name>.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2014-11-17
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
}
Process {
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }
    # Main code part goes here
    Write-Verbose -Message "Querying for packages in a failed distribution state"
    $DistributionFailures = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_PackageStatusDistPointsSummarizer -Filter "(State = '1') OR (State = '2') OR (State = '3') OR (State = '7') OR (State = '8')"
    if ($DistributionFailures -ne $null) {
        foreach ($ContentFailure in $DistributionFailures) {
            Write-Verbose -Message "Found package '$($ContentFailure.PackageID)', will attempt to refresh"
            $DistributionPoints = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_DistributionPoint -Filter "(SiteCode = '$($ContentFailure.SiteCode)') AND (PackageID = '$($ContentFailure.PackageID)')"
            if ($DistributionPoints -ne $null) {
                foreach ($DistributionPoint in $DistributionPoints) {
                    if ($DistributionPoint.ServerNALPath -eq $ContentFailure.ServerNALPath) {
                        $DistributionPoint.RefreshNow = $true
                        $DistributionPoint.Put() | Out-Null
                        Write-Verbose -Message "Successfully refreshed package '$($ContentFailure.PackageID)'"
                    }
                }
            }
            else {
                Write-Output -InputObject "No Distribution Points found for package '$($ContentFailure.PackageID)'"
            }
        }
    }
    else {
        Write-Output -InputObject "There where no unsuccessful content distributions found"
    }
}

