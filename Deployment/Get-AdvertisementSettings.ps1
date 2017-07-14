<#
.SYNOPSIS
    Use this script to decode the numbered AdvertFlags and RemoteClientFlags properties of an Advertisement to see what settings is enabled.
.DESCRIPTION
    Use this script to decode the numbered AdvertFlags and RemoteClientFlags properties of an Advertisement to see what settings is enabled.
.PARAMETER SiteServer
    (DefaultParameterSet)
    Primary Site server name
.PARAMETER Property
    (DefaultParameterSet)
    Specify what WMI instance property to use, valid options are:

    AdvertFlags
    RemoteClientFlags
.PARAMETER AdvertFlag
    (AdvertFlags)
    Specify a setting to look for, valid options are:

    IMMEDIATE
    ONSYSTEMSTARTUP
    ONUSERLOGON
    ONUSERLOGOFF
    WINDOWS_CE
    DONOT_FALLBACK
    ENABLE_TS_FROM_CD_AND_PXE
    OVERRIDE_SERVICE_WINDOWS
    REBOOT_OUTSIDE_OF_SERVICE_WINDOWS
    WAKE_ON_LAN_ENABLED
    SHOW_PROGRESS
    NO_DISPLAY
    ONSLOWNET
.PARAMETER RemoteClientFlag
    (RemoteClientFlags)
    Specify a setting to look for, valid options are:

    RUN_FROM_LOCAL_DISPPOINT
    DOWNLOAD_FROM_LOCAL_DISPPOINT
    DONT_RUN_NO_LOCAL_DISPPOINT
    DOWNLOAD_FROM_REMOTE_DISPPOINT
    RUN_FROM_REMOTE_DISPPOINT
    DOWNLOAD_ON_DEMAND_FROM_LOCAL_DP
    DOWNLOAD_ON_DEMAND_FROM_REMOTE_DP
    BALLOON_REMINDERS_REQUIRED
    RERUN_ALWAYS
    RERUN_NEVER
    RERUN_IF_FAILED
    RERUN_IF_SUCCEEDED
    PERSIST_ON_WRITE_FILTER_DEVICES
    ENABLE_PEER_CACHING
    DONT_FALLBACK
    DP_ALLOW_METERED_NETWORK
.EXAMPLE
    List all Deployments where the RemoteClientFlags property is configured for RERUN_IF_FAILED on a Primary Site server called 'CM01':

    .\Get-AdvertisementSettings.ps1 -SiteServer CM01 -Property RemoteClientFlags -RemoteClientFlag RERUN_IF_FAILED
.NOTES
    Script name: Get-AdvertisementSettings.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2014-09-22
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Position=0, Mandatory=$true, HelpMessage="Specify Primary Site server")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 2})]
    [string]$SiteServer = "$($env:COMPUTERNAME)",
    [parameter(Position=1,Mandatory=$true, HelpMessage="Specify the Advertisement instance property to search for")]
    [ValidateSet("AdvertFlags","RemoteClientFlags")]
    [string]$Property,
    [parameter(Position=2, HelpMessage="Specify flag setting")]
    [parameter(ParameterSetName="AdvertFlags")]
    [ValidateSet(
    "IMMEDIATE",
    "ONSYSTEMSTARTUP",
    "ONUSERLOGON",
    "ONUSERLOGOFF",
    "WINDOWS_CE",
    "DONOT_FALLBACK",
    "ENABLE_TS_FROM_CD_AND_PXE",
    "OVERRIDE_SERVICE_WINDOWS",
    "REBOOT_OUTSIDE_OF_SERVICE_WINDOWS",
    "WAKE_ON_LAN_ENABLED",
    "SHOW_PROGRESS",
    "NO_DISPLAY",
    "ONSLOWNET"
    )]
    [string]$AdvertFlag,
    [parameter(Position=2, HelpMessage="Specify flag setting")]
    [parameter(ParameterSetName="RemoteClientFlags")]
    [ValidateSet(
    "RUN_FROM_LOCAL_DISPPOINT",
    "DOWNLOAD_FROM_LOCAL_DISPPOINT",
    "DONT_RUN_NO_LOCAL_DISPPOINT",
    "DOWNLOAD_FROM_REMOTE_DISPPOINT",
    "RUN_FROM_REMOTE_DISPPOINT",
    "DOWNLOAD_ON_DEMAND_FROM_LOCAL_DP",
    "DOWNLOAD_ON_DEMAND_FROM_REMOTE_DP",
    "BALLOON_REMINDERS_REQUIRED",
    "RERUN_ALWAYS",
    "RERUN_NEVER",
    "RERUN_IF_FAILED",
    "RERUN_IF_SUCCEEDED",
    "PERSIST_ON_WRITE_FILTER_DEVICES",
    "ENABLE_PEER_CACHING",
    "DONT_FALLBACK",
    "DP_ALLOW_METERED_NETWORK"
    )]
    [string]$RemoteClientFlag
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
    # Get all Advertisements available
    try {
        Write-Verbose "Retrieving Advertisement instances"
        $Advertisements = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Advertisement -ComputerName $SiteServer | Select-Object -Property AdvertisementName, AdvertFlags, RemoteClientFlags, PackageID, ProgramName
    }
    catch [Exception] {
        Throw $_.Exception.Message
    }
    # Determine AdvertFlags bitwise value
    if ($PSBoundParameters["Property"] -like "AdvertFlags") {
        switch ($AdvertFlag) {
            "IMMEDIATE" { $Bitwise = "0x00000020" }
            "ONSYSTEMSTARTUP" { $Bitwise = "0x00000100" }
            "ONUSERLOGON" { $Bitwise = "0x00000200" }
            "ONUSERLOGOFF" { $Bitwise = "0x00000400" }
            "WINDOWS_CE" { $Bitwise = "0x00008000" }
            "DONOT_FALLBACK" { $Bitwise = "0x00020000" }
            "ENABLE_TS_FROM_CD_AND_PXE" { $Bitwise = "0x00040000" }
            "OVERRIDE_SERVICE_WINDOWS" { $Bitwise = "0x00100000" }
            "REBOOT_OUTSIDE_OF_SERVICE_WINDOWS" { $Bitwise = "0x00200000" }
            "WAKE_ON_LAN_ENABLED" { $Bitwise = "0x00400000" }
            "SHOW_PROGRESS" { $Bitwise = "0x00800000" }
            "NO_DISPLAY" { $Bitwise = "0x02000000" }
            "ONSLOWNET" { $Bitwise = "0x04000000" }
        }
    }
    # Determine RemoteClientFlags bitwise value
    if ($PSBoundParameters["Property"] -like "RemoteClientFlags") {
        switch ($RemoteClientFlag) {
            "RUN_FROM_LOCAL_DISPPOINT" { $Bitwise = "0x00000008" }
            "DOWNLOAD_FROM_LOCAL_DISPPOINT" { $Bitwise = "0x00000010" }
            "DONT_RUN_NO_LOCAL_DISPPOINT" { $Bitwise = "0x00000020" }
            "DOWNLOAD_FROM_REMOTE_DISPPOINT" { $Bitwise = "0x00000040" }
            "RUN_FROM_REMOTE_DISPPOINT" { $Bitwise = "0x00000080" }
            "DOWNLOAD_ON_DEMAND_FROM_LOCAL_DP" { $Bitwise = "0x00000100" }
            "DOWNLOAD_ON_DEMAND_FROM_REMOTE_DP" { $Bitwise = "0x00000200" }
            "BALLOON_REMINDERS_REQUIRED" { $Bitwise = "0x00000400" }
            "RERUN_ALWAYS" { $Bitwise = "0x00000800" }
            "RERUN_NEVER" { $Bitwise = "0x00001000" }
            "RERUN_IF_FAILED" { $Bitwise = "0x00002000" }
            "RERUN_IF_SUCCEEDED" { $Bitwise = "0x00004000" }
            "PERSIST_ON_WRITE_FILTER_DEVICES" { $Bitwise = "0x00008000" }
            "ENABLE_PEER_CACHING" { $Bitwise = "0x00010000" }
            "DONT_FALLBACK" { $Bitwise = "0x00020000" }
            "DP_ALLOW_METERED_NETWORK" { $Bitwise = "0x00040000" }
        }
    }
}
Process {
    try {
        foreach ($Advertisement in $Advertisements) {
            if ($Advertisement.$Property -eq ($Advertisement.$Property -bor "$($Bitwise)")) {
                if ($Advertisement.ProgramName -eq "*") {
                    $TaskSequenceName = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Filter "PackageID like '$($Advertisement.PackageID)'" | Select-Object -ExpandProperty Name
                    $PSObject = New-Object -TypeName PSObject
                    $PSObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $TaskSequenceName
                    $PSObject | Add-Member -MemberType NoteProperty -Name "AdvertisementName" -Value $Advertisement.AdvertisementName
                    $PSObject | Add-Member -MemberType NoteProperty -Name "PackageID" -Value $Advertisement.PackageID
                    $PSObject | Add-Member -MemberType NoteProperty -Name "FlagEnabled" -Value "$($Advertisement.$Property -eq ($Advertisement.$Property -bor "$($Bitwise)"))"
                    $PSObject | Add-Member -MemberType NoteProperty -Name "Type" -Value "Task Sequence"
                    $PSObject
                }
                else {
                    $PackageName = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Package -ComputerName $SiteServer -Filter "PackageID like '$($Advertisement.PackageID)'" | Select-Object -ExpandProperty Name
                    $PSObject = New-Object -TypeName PSObject
                    $PSObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $PackageName
                    $PSObject | Add-Member -MemberType NoteProperty -Name "AdvertisementName" -Value $Advertisement.AdvertisementName
                    $PSObject | Add-Member -MemberType NoteProperty -Name "PackageID" -Value $Advertisement.PackageID
                    $PSObject | Add-Member -MemberType NoteProperty -Name "FlagEnabled" -Value "$($Advertisement.$Property -eq ($Advertisement.$Property -bor "$($Bitwise)"))"
                    $PSObject | Add-Member -MemberType NoteProperty -Name "Type" -Value "Package"
                    $PSObject
                }
            }
        }
    }
    catch [Exception] {
        Write-Error $_.Exception.Message
    }
}
