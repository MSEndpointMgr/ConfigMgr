<#
.SYNOPSIS
    Create a Deployment Package in Configuration Manager 2012.
.DESCRIPTION
    Use this script if you need to create a Deployment Package in Configuration Manager 2012. 
.PARAMETER SiteServer
    Primary Site server name with SMS Provider installed
.PARAMETER Name
    Name of the Deployment Package
.PARAMETER Description
    Description of the Deployment Package
.PARAMETER SourcePath
    UNC path to the source location where downloaded patches will be stored
.EXAMPLE
    .\New-CMDeploymentPackage.ps1 -SiteServer CM01 -Name "Critical and Security Patches" -SourcePath "\\CAS01\Source$\SUM\ADRs\CS" -Description "Contains Critical and Security patches"
    Create a Deployment Package called 'Critical and Security Patches', specifying a source path and description on a Primary Site server called 'CM01':
.NOTES
    Script name: New-CMDeploymentPackage.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2014-11-05
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true,HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,
    [parameter(Mandatory=$true,HelpMessage="Name of the Deployment Package")]
    [string]$Name,
    [parameter(Mandatory=$false,HelpMessage="Description of the Deployment Package")]
    [string]$Description,
    [parameter(Mandatory=$true,HelpMessage="UNC path to the source location where downloaded patches will be stored")]
    [string]$SourcePath
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
    function Get-DuplicateInfo {
        $IsDuplicatePkg = $false
        $EnumDeploymentPackages = Get-CimInstance -CimSession $CimSession -Namespace "root\SMS\site_$($SiteCode)" -ClassName SMS_SoftwareUpdatesPackage -ErrorAction SilentlyContinue -Verbose:$false
        foreach ($Pkgs in $EnumDeploymentPackages) {
            if ($Pkgs.PkgSourcePath -like "$($SourcePath)") {
                $IsDuplicatePkg = $true
            }
        }
        return $IsDuplicatePkg
    }
    function Remove-CimSessions {
        foreach ($Session in $(Get-CimSession -ComputerName $SiteServer -ErrorAction SilentlyContinue -Verbose:$false)) {
            if ($Session.TestConnection()) {
                Write-Verbose -Message "Closing CimSession against '$($Session.ComputerName)'"
                Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue -Verbose:$false
            }
        }
    }
    try {
        Write-Verbose -Message "Establishing a Cim session against '$($SiteServer)'"
        $CimSession = New-CimSession -ComputerName $SiteServer -Verbose:$false
        # Check if there's an existing Deployment Package with the same name
        if ((Get-CimInstance -CimSession $CimSession -Namespace "root\SMS\site_$($SiteCode)" -ClassName SMS_SoftwareUpdatesPackage -Filter "Name like '$($Name)'" -ErrorAction SilentlyContinue -Verbose:$false | Measure-Object).Count -eq 0) {
            # Check if there's an existing Deployment Package with the same source path
            if ((Get-DuplicateInfo) -eq $false) {
                $CimProperties = @{
                    "Name" = "$($Name)"
                    "PkgSourceFlag" = 2
                    "PkgSourcePath" = "$($SourcePath)"
                }
                if ($PSBoundParameters["Description"]) {
                    $CimProperties.Add("Description",$Description)
                }
                $CMDeploymentPackage = New-CimInstance -CimSession $CimSession -Namespace "root\SMS\site_$($SiteCode)" -ClassName SMS_SoftwareUpdatesPackage -Property $CimProperties -Verbose:$false -ErrorAction Stop
                $PSObject = [PSCustomObject]@{
                    "Name" = $CMDeploymentPackage.Name
                    "Description" = $CMDeploymentPackage.Description
                    "PackageID" = $CMDeploymentPackage.PackageID
                    "PkgSourcePath" = $CMDeploymentPackage.PkgSourcePath
                }
                if (-not($PSBoundParameters["WhatIf"])) {
                    Write-Output $PSObject
                }
            }
            else {
                Write-Warning -Message "A Deployment Package with the specified source path already exists"
            }
        }
        else {
            Write-Warning -Message "A Deployment Package with the name '$($Name)' already exists"
        }
    }
    catch [Exception] {
        Remove-CimSessions
        Throw $_.Exception.Message
    }
}
End {
    # Remove active Cim session established to $SiteServer
    Remove-CimSessions
}