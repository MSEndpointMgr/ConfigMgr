<#
.SYNOPSIS
    List all Disabled Programs of Packages in ConfigMgr 2012
.DESCRIPTION
    Use this script to list all of the disabled Programs for each Package in ConfigMgr 2012. This script will also give you the option to enable those Programs.
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER Enable
    Specify this switch only if you wish to enable the disable Programs. Don't specify it if you wish to only list the disabled Programs.
.EXAMPLE
    .\Get-CMDisabledPrograms.ps1 -SiteServer CM01 -Verbose
    Lists all disabled Programs and their Package Name association on a Primary Site server called 'CM01':
.NOTES
    Script name: Get-CMDisabledPrograms.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-03-10
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateNotNullOrEmpty()]
    [string]$SiteServer,
    [parameter(Mandatory=$false, HelpMessage="Enable disabled programs")]
    [switch]$Enable
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose "Determining SiteCode for Site Server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop -Verbose:$false
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
    # Set SiteDrive variable
    $SiteDrive = $SiteCode + ":"
    # Get current location
    $CurrentLocation = $PSScriptRoot
    # Import ConfigMgr PowerShell module
    Import-Module (Join-Path -Path (($env:SMS_ADMIN_UI_PATH).Substring(0,$env:SMS_ADMIN_UI_PATH.Length-5)) -ChildPath "\ConfigurationManager.psd1" -Verbose:$false) -Force -Verbose:$false
    if ((Get-PSDrive $SiteCode -ErrorAction SilentlyContinue | Measure-Object).Count -ne 1) {
        New-PSDrive -Name $SiteCode -PSProvider "AdminUI.PS.Provider\CMSite" -Root $SiteServer -Verbose:$false
    }
}
Process {
    # Change location to the Site Drive
    Set-Location $SiteDrive -Verbose:$false
    # Get all Programs
    $Programs = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Program -ComputerName $SiteServer -Verbose:$false
    if ($Programs -ne $null) {
        foreach ($Program in $Programs) {
            if ($Program.ProgramFlags -eq ($Program.ProgramFlags -bor "0x00001000")) {
                $PSObject = [PSCustomObject]@{
                    "PackageName" = $Program.PackageName
                    "ProgramName" = $Program.ProgramName
                }
                if ($PSBoundParameters["Enable"]) {
                    Write-Verbose -Message "Enabling program '$($Program.ProgramName)' for package '$($Program.PackageName)'"
                    try {
                        Get-CMProgram -ProgramName $Program.ProgramName -PackageId $Program.PackageID -Verbose:$false | Enable-CMProgram -Verbose:$false -ErrorAction Stop
                    }
                    catch {
                        Write-Warning -Message "Unable to enable program '$($Program.ProgramName)' for package '$($Program.PackageName)'"
                    }
                }
                else {
                    Write-Output $PSObject
                }
            }
        }
    }
    else {
        Write-Warning -Message "No Programs found"
    }
}
End {
    Set-Location -Path $CurrentLocation
}