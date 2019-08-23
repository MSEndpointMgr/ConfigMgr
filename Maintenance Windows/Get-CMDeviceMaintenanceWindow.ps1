<#
.SYNOPSIS
    Get maintenance windows for a given device in ConfigMgr.

.DESCRIPTION
    Get maintenance windows for a given device in ConfigMgr.

.PARAMETER SiteServer
    Site Server where the SMS Provider is installed.

.PARAMETER DeviceName
    Name of the device.

.EXAMPLE
    # Get all maintenance windows for a device named 'CL01':
    .\Get-CMDeviceMaintenanceWindow.ps1 -SiteServer CM01 -DeviceName CL01

.NOTES
    FileName:    Get-CMDeviceMaintenanceWindow.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2019-06-18
    Updated:     2019-06-18

    Version history:
    1.0.0 - (2019-06-18) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site Server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Name of the device.")]
    [ValidateNotNullOrEmpty()]
    [string]$DeviceName
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
        Write-Warning -Message "Access denied"; break
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine site code from specified Configuration Manager site server, specify the site server where the SMS Provider is installed"; break
    }
}
Process {
    try {
        # Retrieve the resource id for the given device name
        $DeviceResourceID = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_R_System -ComputerName $SiteServer -Filter "Name like '$($DeviceName)'" -ErrorAction Stop | Select-Object -ExpandProperty ResourceID

        # Retrieve all device collection membership for the resource id
        $CollectionIDs = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_FullCollectionMembership -ComputerName $SiteServer -Filter "ResourceID like '$($DeviceResourceID)'"

        if ($CollectionIDs -ne $null) {
            # Process each collection item
            foreach ($CollectionID in $CollectionIDs) {
                # Retrieve the collection settings for current collection
                $CollectionSettings = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_CollectionSettings -ComputerName $SiteServer -Filter "CollectionID='$($CollectionID.CollectionID)'"
                foreach ($CollectionSetting in $CollectionSettings) {
                    # Retrieve the full collection setting instance including lazy properties
                    $CollectionSetting.Get()

                    # Process each service window in collection settings
                    foreach ($MaintenanceWindow in $CollectionSetting.ServiceWindows) {
                        # Determine the start time of the service window
                        $StartTime = [Management.ManagementDateTimeConverter]::ToDateTime($MaintenanceWindow.StartTime)
                        
                        # Get the collection name where the current service window is configured
                        $CollectionName = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "CollectionID = '$($CollectionID.CollectionID)'" | Select-Object -ExpandProperty Name

                        # Construct a custom PSObject for output
                        $PSObject = [PSCustomObject]@{
                            "MaintenanceWindowName" = $MaintenanceWindow.Name
                            "Schedule" = $MaintenanceWindow.Description
                            "ReccurenceType" = $MaintenanceWindow.RecurrenceType
                            "CollectionName" = $CollectionName
                            "StartTime" = $StartTime
                        }

                        # Handle output of custom object
                        Write-Output $PSObject
                    }
                }
            }
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine resource id for given device name"; break
    }
}