<#
.SYNOPSIS
    Create a set of usefull Maintenance Collections for ConfigMgr 2012
.DESCRIPTION
    This script will create a set of predefined Maintenance Collections that may be useful to ConfigMgr administrators
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER LimitingCollectionName
    Name of the collection to be used as limiting collection for all maintenance collections
.PARAMETER FolderName
    Name of a Device Collections folder where the collections will be created. If not specified, the collections will be created in the root of Device Collections
.EXAMPLE
    .\Create-CMMaintenanceCollections.ps1 -SiteServer CM01 -LimitingCollectionName "All Systems" -FolderName "Maintenance Collections"
     Create the Maintenance Collections with a limiting collection of 'All Systems' in a folder called 'Maintenance Collections' on a Primary Site server called 'CM01':
.NOTES
    Script name: Create-CMClientVersionCollections.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-03-15
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [ValidateNotNullOrEmpty()]
    [string]$SiteServer,
    [parameter(Mandatory=$true, HelpMessage="Name of the collection to be used as limiting collection for all maintenance collections")]
    [ValidateNotNullOrEmpty()]
    [string]$LimitingCollectionName,
    [parameter(Mandatory=$false, HelpMessage="Name of a Device Collections folder where the collections will be created. If not specified, the collections will be created in the root of Device Collections")]
    [ValidateNotNullOrEmpty()]
    [string]$FolderName
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
        Write-Warning -Message "Unable to determine SiteCode" ; break
    }
    # Validate LimitingCollectionName exists
    if (-not(Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "Name like '$($LimitingCollectionName)'")) {
        Write-Warning -Message "Unable to determine the existence of a collection named '$($LimitingCollectionName)'" ; break
    }
}
Process {
    # Functions
    function New-ScheduleToken {
        param(
            [parameter(Mandatory=$false)]
            [int]$DayDuration = 0,
            [parameter(Mandatory=$false)]
            [int]$DaySpan = 0,
            [parameter(Mandatory=$false)]
            [int]$HourDuration = 0,
            [parameter(Mandatory=$false)]
            [int]$HourSpan = 0,
            [parameter(Mandatory=$false)]
            [bool]$IsGMT = $false,
            [parameter(Mandatory=$false)]
            [int]$MinuteDuration = 0,
            [parameter(Mandatory=$false)]
            [int]$MinuteSpan = 0,
            [parameter(Mandatory=$true)]
            [int]$StartTimeHour = 0,
            [parameter(Mandatory=$true)]
            [int]$StartTimeMin = 0,
            [parameter(Mandatory=$true)]
            [int]$StartTimeSec = 0
        )
        # Create the Schedule Token for the collection
        $StartTime = [System.Management.ManagementDateTimeconverter]::ToDMTFDateTime((Get-Date -Hour $StartTimeHour -Minute $StartTimeMin -Second $StartTimeSec))
        $ScheduleToken = ([WMIClass]"\\$($SiteServer)\root\SMS\Site_$($SiteCode):SMS_ST_RecurInterval").CreateInstance()
        $ScheduleToken.DayDuration = $DayDuration
        $ScheduleToken.DaySpan = $DaySpan
        $ScheduleToken.HourDuration = $HourDuration
        $ScheduleToken.HourSpan = $HourSpan
        $ScheduleToken.IsGMT = $IsGMT
        $ScheduleToken.MinuteDuration = $MinuteDuration
        $ScheduleToken.MinuteSpan = $MinuteSpan
        $ScheduleToken.StartTime = $StartTime
        return $ScheduleToken
    }

    function Get-LimitingCollectionID {
        param(
            [parameter(Mandatory=$true)]
            [string]$LimitingCollection
        )
        # Determine the Limiting Collection ID
        $LimitingCollectionID = Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "Name like '$($LimitingCollectionName)'" | Select-Object -ExpandProperty CollectionID
        return $LimitingCollectionID
    }

    function Create-Collection {
        param(
            [parameter(Mandatory=$true)]
            [string]$CollectionName,
            [parameter(Mandatory=$true)]
            [string]$CollectionQuery,
            [parameter(Mandatory=$true)]
            [string]$QueryRuleName
        )
        # Validate the Collection Query
        $ValidateQuery = Invoke-WmiMethod -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_CollectionRuleQuery -Name ValidateQuery -ArgumentList $CollectionQuery -ComputerName $SiteServer
        # Create a Collection Query rule
        if ($ValidateQuery) {
            $NewRule = ([WMIClass]"\\$($SiteServer)\root\SMS\Site_$($SiteCode):SMS_CollectionRuleQuery").CreateInstance()
            $NewRule.QueryExpression = $CollectionQuery
            $NewRule.RuleName = $QueryRuleName
            # Create the collection
            Write-Verbose -Message "Creating collection: $($CollectionName)"
            $NewDeviceCollection = ([WmiClass]"\\$($SiteServer)\root\SMS\Site_$($SiteCode):SMS_Collection").CreateInstance()
            $NewDeviceCollection.Name = $CollectionName
            $NewDeviceCollection.OwnedByThisSite = $true
            $NewDeviceCollection.CollectionRules += $NewRule
            $NewDeviceCollection.LimitToCollectionID = (Get-LimitingCollectionID -LimitingCollection $LimitingCollectionName)
            $NewDeviceCollection.RefreshSchedule = (New-ScheduleToken -HourSpan 12 -StartTimeHour 7 -StartTimeMin 0 -StartTimeSec 0)
            $NewDeviceCollection.RefreshType = 2
            $NewDeviceCollection.CollectionType = 2
            $NewDeviceCollection.Put() | Out-Null
            # Validate that the WMI instance was created
            if ((Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "Name like '$($CollectionName)'" | Measure-Object).Count -eq 1) {
                Write-Verbose -Message "Successfully created collection '$($CollectionName)'"
            }
            else {
                Write-Warning -Message "Unable to create collection '$($CollectionName)'"
            }
            # Move the collection to the specified folder
            if ($Script:PSBoundParameters["FolderName"]) {
                $CollectionID = Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "Name like '$($CollectionName)' AND CollectionType = 2" | Select-Object -ExpandProperty CollectionID
                [int]$TargetFolder = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_ObjectContainerNode -ComputerName $SiteServer -Filter "ObjectType = 5000 AND Name like '$($FolderName)'" | Select-Object -ExpandProperty ContainerNodeID
                [int]$SourceFolder = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_ObjectContainerItem -ComputerName $SiteServer -Filter "InstanceKey like '$($CollectionID)'" | Select-Object -ExpandProperty ContainerNodeID
                $Parameters = ([WmiClass]"\\$($SiteServer)\root\SMS\Site_$($SiteCode):SMS_ObjectContainerItem").GetMethodParameters("MoveMembers")
                $Parameters.ObjectType = 5000
                $Parameters.ContainerNodeID = $SourceFolder
                $Parameters.TargetContainerNodeID = $TargetFolder
                $Parameters.InstanceKeys = $CollectionID
                $MoveCollectionToFolder = ([WmiClass]"\\$($SiteServer)\root\SMS\Site_$($SiteCode):SMS_ObjectContainerItem").InvokeMethod("MoveMembers", $Parameters, $null)
                if ($MoveCollectionToFolder.ReturnValue -eq 0) {
                    Write-Verbose -Message "Successfully moved collection '$($CollectionName)' to the '$($FolderName)' folder"
                }
            }
            # Request to refresh the collection membership
            $NewDeviceCollection.RequestRefresh() | Out-Null
        }
    }

    # Create the maintenance collections
    $CollectionsTable = @{
        "ConfigMgr 2012 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7711.0000"'
        "ConfigMgr 2012 CU1 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7711.0200"'
        "ConfigMgr 2012 CU2 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7711.0301"'
        "ConfigMgr 2012 SP1 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7804.1000"'
        "ConfigMgr 2012 SP1 CU1 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7804.1202"'
        "ConfigMgr 2012 SP1 CU2 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7804.1300"'
        "ConfigMgr 2012 SP1 CU3 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7804.1400"'
        "ConfigMgr 2012 SP1 CU4 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7804.1500"'
        "ConfigMgr 2012 SP1 CU5 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7804.1600"'
        "ConfigMgr 2012 R2 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7958.1000"'
        "ConfigMgr 2012 R2 KB2905002 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7958.1101"'
        "ConfigMgr 2012 R2 CU1 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7958.1203"'
        "ConfigMgr 2012 R2 CU2 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7958.1303"'
        "ConfigMgr 2012 R2 CU3 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7958.1401"'
        "ConfigMgr 2012 R2 CU4 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7958.1501"'
        "ConfigMgr 2012 R2 CU5 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.7958.1604"'
        "ConfigMgr 2012 R2 SP1 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.8239.1000"'
        "ConfigMgr 2012 R2 SP1 CU1 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.8239.1203"'
		"ConfigMgr 2012 R2 SP1 CU2 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.8239.1301"'
		"ConfigMgr 2012 R2 SP1 CU3 Clients" = 'select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.8239.1403"'
		"ConfigMgr 1511 Clients" = 'select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.8325.1000"'
		"ConfigMgr 1602 Clients" = 'select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.ClientVersion = "5.00.8355.1000"'
    }
    foreach ($Collection in $CollectionsTable.Keys) {
        Create-Collection -CollectionName $Collection -CollectionQuery $CollectionsTable["$Collection"] -QueryRuleName $Collection
    }
}