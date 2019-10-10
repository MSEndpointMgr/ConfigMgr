<#
.SYNOPSIS
    Create a set of limiting device collections for Configuration Manager.

.DESCRIPTION
    This script creates a set of limiting device collections for Configuration Manager.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER FolderName
    Define a Device Collection folder name where the collections will be moved to.

.PARAMETER LimitingCollectionName
    Name of a collection that will be used as Limiting Collection.

.EXAMPLE
    .\Create-CMLimitingDeviceCollections.ps1 -SiteServer CM01 -FolderName "Limiting Collections"

.NOTES
    FileName:    Create-CMLimitingDeviceCollections.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-06-09
    Updated:     2017-06-09
    
    Version history:
    1.0.0 - (2017-06-09) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$false, HelpMessage="Define a Device Collection folder name where the collections will be moved to.")]
    [ValidateNotNullOrEmpty()]
    [string]$FolderName,

    [parameter(Mandatory=$false, HelpMessage="Name of a collection that will be used as Limiting Collection.")]
    [ValidateNotNullOrEmpty()]
    [string]$LimitingCollectionName = "All Systems"    
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

    # Load ConfigMgr module
    try {
        $SiteDrive = $SiteCode + ":"
        Import-Module -Name ConfigurationManager -ErrorAction Stop -Verbose:$false
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        try {
            Import-Module -Name (Join-Path -Path (($env:SMS_ADMIN_UI_PATH).Substring(0,$env:SMS_ADMIN_UI_PATH.Length-5)) -ChildPath "\ConfigurationManager.psd1") -Force -ErrorAction Stop -Verbose:$false
            if ((Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue | Measure-Object).Count -ne 1) {
                New-PSDrive -Name $SiteCode -PSProvider "AdminUI.PS.Provider\CMSite" -Root $SiteServer -ErrorAction Stop -Verbose:$false | Out-Null
            }
        }
        catch [System.UnauthorizedAccessException] {
            Write-Warning -Message "Access denied" ; break
        }
        catch [System.Exception] {
            Write-Warning -Message "$($_.Exception.Message). Line: $($_.InvocationInfo.ScriptLineNumber)" ; break
        }
    }

    # Determine and set location to the CMSite drive
    $CurrentLocation = $PSScriptRoot
    Set-Location -Path $SiteDrive -Verbose:$false

    # Disable Fast parameter usage check for Lazy properties
    $CMPSSuppressFastNotUsedCheck = $true

    # Validate specified folder name exists
    if ($PSBoundParameters["FolderName"]) {
        if (-not(Test-Path -Path (Join-Path -Path $SiteDrive -ChildPath "DeviceCollection\$($FolderName)") -Verbose:$false)) {
            Write-Warning -Message "Unable to locate specified folder name in Device Collections"
            Set-Location -Path $CurrentLocation -Verbose:$false ; exit
        }
    }
}
Process {
# Table of collections
    $CollectionTable = @{
        "LC - All ConfigMgr Clients" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.OperatingSystemNameandVersion like '%Windows%'"
        "LC - All Office 365 Clients" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System inner join SMS_G_System_ADD_REMOVE_PROGRAMS_64 on SMS_G_System_ADD_REMOVE_PROGRAMS_64.ResourceId = SMS_R_System.ResourceId where SMS_R_System.Client is not null  and SMS_G_System_ADD_REMOVE_PROGRAMS_64.DisplayName like 'Microsoft Office 365%'"
        "LC - All Mac OS X Systems" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.OperatingSystemNameandVersion like 'OS X%'"
        "LC - All Laptops" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_SYSTEM_ENCLOSURE on SMS_G_System_SYSTEM_ENCLOSURE.ResourceID = SMS_R_System.ResourceId where SMS_G_System_SYSTEM_ENCLOSURE.ChassisTypes in ( '8', '9', '10', '14' )"
        "LC - All Windows 10 Systems" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.OperatingSystemNameandVersion like '%Workstation 10%' or SMS_R_System.OperatingSystemNameandVersion like '%Windows 10 Enterprise%'"
        "LC - All Windows 8.1 Systems" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.OperatingSystemNameandVersion like '%Workstation 6.3%'"
        "LC - All Windows 7 Systems" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.Client is not null  and SMS_R_System.OperatingSystemNameandVersion like '%Workstation 6.1%'"
        "LC - All Non-Virtual Systems" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.IsVirtualMachine = 'False'"
        "LC - All Virtual Systems" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.IsVirtualMachine = 'True'"
        "LC - All Windows Clients" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.OperatingSystemNameandVersion like '%Workstation%'"
        "LC - All Windows Servers" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where OperatingSystemNameandVersion like '%Server%'"
        "LC - All Non-Virtual Windows Servers" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.ResourceId not in (select SMS_R_SYSTEM.ResourceID from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_R_System.IsVirtualMachine = 'True') and SMS_R_System.Client is not null and SMS_R_System.OperatingSystemNameandVersion like '%Server%'"
        "LC - All Virtual Windows Servers" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.IsVirtualMachine = 'True' and SMS_R_System.OperatingSystemNameandVersion like '%Server%'"
        "LC - All Windows Server 2008" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.OperatingSystemNameandVersion like '%Server 6.0%'"
        "LC - All Windows Server 2008 R2" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.OperatingSystemNameandVersion like '%Server 6.1%'"
        "LC - All Windows Server 2012" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.OperatingSystemNameandVersion like '%Server 6.2%'"
        "LC - All Windows Server 2012 R2" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.OperatingSystemNameandVersion like '%Server 6.3%'"
        "LC - All Windows Server 2016" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.OperatingSystemNameandVersion like '%Server 10%'"
        "LC - All Windows 10 version 1507" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_OPERATING_SYSTEM on SMS_G_System_OPERATING_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_G_System_OPERATING_SYSTEM.BuildNumber = '10240' and SMS_G_System_OPERATING_SYSTEM.Caption like 'Microsoft Windows 10%'"
        "LC - All Windows 10 version 1511" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_OPERATING_SYSTEM on SMS_G_System_OPERATING_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_G_System_OPERATING_SYSTEM.BuildNumber = '10586' and SMS_G_System_OPERATING_SYSTEM.Caption like 'Microsoft Windows 10%'"
        "LC - All Windows 10 version 1607" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_OPERATING_SYSTEM on SMS_G_System_OPERATING_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_G_System_OPERATING_SYSTEM.BuildNumber = '14393' and SMS_G_System_OPERATING_SYSTEM.Caption like 'Microsoft Windows 10%'"
        "LC - All Windows 10 version 1703" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_OPERATING_SYSTEM on SMS_G_System_OPERATING_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_G_System_OPERATING_SYSTEM.BuildNumber = '15063' and SMS_G_System_OPERATING_SYSTEM.Caption like 'Microsoft Windows 10%'"
        "LC - All Windows 10 version 1709" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_OPERATING_SYSTEM on SMS_G_System_OPERATING_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_G_System_OPERATING_SYSTEM.BuildNumber = '16229' and SMS_G_System_OPERATING_SYSTEM.Caption like 'Microsoft Windows 10%'"
        "LC - All Windows 10 version 1803" = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_OPERATING_SYSTEM on SMS_G_System_OPERATING_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_G_System_OPERATING_SYSTEM.BuildNumber = '17134' and SMS_G_System_OPERATING_SYSTEM.Caption like 'Microsoft Windows 10%'"
        "LC - All ConfigMgr Site Systems" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.SystemRoles = 'SMS Site System'"
        "LC - All ConfigMgr Site Servers" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.SystemRoles = 'SMS Site Server'"
        "LC - All ConfigMgr Distribution Points" = "select SMS_R_System.ResourceId, SMS_R_System.ResourceType, SMS_R_System.Name, SMS_R_System.SMSUniqueIdentifier, SMS_R_System.ResourceDomainORWorkgroup, SMS_R_System.Client from  SMS_R_System where SMS_R_System.SystemRoles = 'SMS Distribution Point'"
        "LC - All CMG Connected Systems" = "select SMS_R_SYSTEM.Name from SMS_R_System where SMS_R_System.ResourceId in (select resourceid from SMS_CollectionMemberClientBaselineStatus where SMS_CollectionMemberClientBaselineStatus.CNAccessMP like '%.cloudapp.net/%')"
    }

    # Create Windows as a Service operational collections
    foreach ($DeviceCollection in $CollectionTable.Keys) {
        # Create Device Collection
        try {
            Write-Verbose -Message "Creating Device Collection: $($DeviceCollection)"
            $DeviceCollectionRefreshSchedule = New-CMSchedule -Start (Get-Date) -RecurInterval Days -RecurCount 1 -Verbose:$false -ErrorAction Stop
            New-CMDeviceCollection -LimitingCollectionName $LimitingCollectionName -Name $DeviceCollection -RefreshType Both -RefreshSchedule $DeviceCollectionRefreshSchedule -Verbose:$false -ErrorAction Stop | Out-Null

            # Create device collection query membership rule
            try {
                Write-Verbose -Message "Adding query membership rule for collection: $($DeviceCollection)"
                Add-CMDeviceCollectionQueryMembershipRule -CollectionName $DeviceCollection -RuleName $DeviceCollection -QueryExpression $CollectionTable[$DeviceCollection] -Verbose:$false -ErrorAction Stop | Out-Null

                # Move collection to folder
                if ($PSBoundParameters["FolderName"]) {
                    try {
                        Write-Verbose -Message "Moving device collection to folder: $($FolderName)"
                        $DeviceCollectionObject = Get-CMDeviceCollection -Name $DeviceCollection -Verbose:$false -ErrorAction Stop
                        Move-CMObject -InputObject $DeviceCollectionObject -FolderPath "DeviceCollection\$($FolderName)" -Verbose:$false -ErrorAction Stop
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "Unable to move device collection to folder '$($FolderName)', error message: $($_.Exception.Message)"
                    }
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create device collection query membership rule, error message: $($_.Exception.Message)"
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to create device collection, error message: $($_.Exception.Message)"
        }
    }
}
End {
    Set-Location -Path $CurrentLocation
}