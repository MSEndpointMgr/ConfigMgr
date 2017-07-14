<#
.SYNOPSIS
    Set the maximum run time property of Software Update object in Configuration Manager.

.DESCRIPTION
    This script can update the maximum run time property of Software Update objects in Configuration Manager, matching the specified update types.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER UpdateType
    Define the Software Update types that will quialify for changing the maximum run time property.

.PARAMETER Minutes
    Amount of minutes that the Software Updates maximum run time will be set to.

.PARAMETER DaysAgo
    Filter only for Software Update objects released within specified amount of days.

.EXAMPLE
    .\Set-CMSoftwareUpdateMaximumRuntime.ps1 -SiteServer CM01 -Minutes 60
    .\Set-CMSoftwareUpdateMaximumRuntime.ps1 -SiteServer CM01 -UpdateType "CumulativeUpdate","SecurityOnly" -Minutes 60
    .\Set-CMSoftwareUpdateMaximumRuntime.ps1 -SiteServer CM01 -Minutes 60 -DaysAgo 1

.NOTES
    FileName:    Set-CMSoftwareUpdateMaximumRuntime.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-06-21
    Updated:     2017-06-21
    
    Version history:
    1.0.0 - (2017-06-21) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$false, HelpMessage="Site server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer = "server.domain.com",

    [parameter(Mandatory=$false, HelpMessage="Define the Software Update types that will quialify for changing the maximum run time property.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("CumulativeUpdate", "Update", "SecurityOnly", "Preview")]
    [string[]]$UpdateType = @("CumulativeUpdate", "Update", "SecurityOnly", "Preview"),

    [parameter(Mandatory=$false, HelpMessage="Amount of minutes that the Software Updates maximum run time will be set to.")]
    [ValidateNotNullOrEmpty()]
    [string]$Minutes = "60",

    [parameter(Mandatory=$false, HelpMessage="Filter only for Software Update objects released within specified amount of days.")]
    [ValidateNotNullOrEmpty()]
    [string]$DaysAgo = "1"
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
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine Site Code" ; exit 3
    }

    # Load ConfigMgr module
    try {
        Import-Module -Name (Join-Path -Path (($env:SMS_ADMIN_UI_PATH).Substring(0,$env:SMS_ADMIN_UI_PATH.Length-5)) -ChildPath "\ConfigurationManager.psd1") -Force -ErrorAction Stop -Verbose:$false
        if ((Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue | Measure-Object).Count -ne 1) {
            New-PSDrive -Name $SiteCode -PSProvider "AdminUI.PS.Provider\CMSite" -Root $SiteServer -ErrorAction Stop -Verbose:$false | Out-Null
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "$($_.Exception.Message). Line: $($_.InvocationInfo.ScriptLineNumber)" ; exit 2
    }

    # Determine and set location to the CMSite drive
    try {
        $SiteDrive = $SiteCode + ":"
        $CurrentLocation = $PSScriptRoot
        Set-Location -Path $SiteDrive -ErrorAction Stop -Verbose:$false
    }
    catch [Exception] {
        Write-Warning -Message "$($_.Exception.Message). Line: $($_.InvocationInfo.ScriptLineNumber)" ; exit 4
    }

    # Disable Fast parameter usage check for Lazy properties
    $CMPSSuppressFastNotUsedCheck = $true
}
Process {
    # Functions
    function Write-CMLogEntry {
	    param(
		    [parameter(Mandatory=$true, HelpMessage="Value added to the log file.")]
		    [ValidateNotNullOrEmpty()]
		    [string]$Value,

		    [parameter(Mandatory=$true, HelpMessage="Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		    [ValidateNotNullOrEmpty()]
            [ValidateSet("1", "2", "3")]
		    [string]$Severity,

		    [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
		    [ValidateNotNullOrEmpty()]
		    [string]$FileName = "SUMMaintenance.log"
	    )
	    # Determine log file location
        $LogFilePath = Join-Path -Path "$($env:windir)\Logs" -ChildPath $FileName

        # Construct time stamp for log entry
        $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))

        # Construct date for log entry
        $Date = (Get-Date -Format "MM-dd-yyyy")

        # Construct context for log entry
        $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)

        # Construct final log entry
        $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""SUMMaintenance"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
	
	    # Add value to log file
        try {
	        Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to append log entry to SUMMaintenance.log file. Error message: $($_.Exception.Message)"
        }
    }

    Write-CMLogEntry -Value "Initiating SUM maintenance for amending Software Updates maximum run time values" -Severity 1

    # Create a table for update type search filter
    $FilterTable = @{
        "CumulativeUpdate" = "Cumulative Update for Windows 10|Security Monthly Quality Rollup"
        "Update" = "Update for Windows 10"
        "SecurityOnly" = "Security Only Quality Update"
        "Preview" = "Preview of Monthly Quality Rollup"
    }

    # Construct search filter for Software Updates
    $SearchFilter = [System.String]::Empty
    $UpdateCount = 0

    foreach ($Type in $UpdateType) {
        $UpdateCount++
        if ($UpdateCount -eq $UpdateType.Count) {
            $SearchFilter = -join @($SearchFilter, $FilterTable[$Type], "")
        }
        else {
            $SearchFilter = -join @($SearchFilter, $FilterTable[$Type], "|")
        }
    }
    Write-CMLogEntry -Value "Using Software Updates search filter: $($SearchFilter)" -Severity 1

    # Get filtered Software Updates
    try {
        Write-CMLogEntry -Value "Querying for Software Updates matching search filter and release date within '$($DaysAgo)' days" -Severity 1
        $Updates = Get-CMSoftwareUpdate -Fast -DateRevisedMin (Get-Date).AddDays($DaysAgo) | Where-Object { $_.LocalizedDisplayName -match $SearchFilter } -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Unable to query for Software Updates. Error message: $($_.Exception.Message)" -Severity 3
    }

    # Set maximum runtime for each Software Update
    if ($Updates -ne $null) {
        Write-CMLogEntry -Value "Query returned '$(($Updates | Measure-Object).Count)' objects" -Severity 1

        foreach ($Update in $Updates) {
            try {
                Set-CMSoftwareUpdate -InputObject $Update -MaximumExecutionMins $Minutes -ErrorAction Stop
                Write-CMLogEntry -Value "Successfully updated maximum run time property for Software Update '$($Update.LocalizedDisplayName)' with a new value of '$($Minutes)'" -Severity 1
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value "Unable to set maximum run time for update '$($Update.LocalizedDisplayName)'. Error message: $($_.Exception.Message)" -Severity 3
            }
        }
    }
    else {
        Write-CMLogEntry -Value "Query returned an empty list of Software Updates, bailing out." -Severity 1
    }
}
End {
    Set-Location -Path $CurrentLocation
}