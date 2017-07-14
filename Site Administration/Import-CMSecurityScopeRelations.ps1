<#
.SYNOPSIS
    Import secured object relations (Security Scope) in ConfigMgr from a XML file.

.DESCRIPTION
    This script will import a list containing secured objects per Security Scope to a XML file, exported from the Export-CMSecurityScopeRelations.ps1 script.
    Use the exported XML file to import and re-assign the Security Scope per object.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER Path
    Specify a valid path to an exported XML file containing the Security Scope data.

.PARAMETER ShowProgress
    Show a progressbar displaying the current operation.

.EXAMPLE
    .\Import-CMSecurityScopeRelations.ps1 -SiteServer CM01 -Path C:\Export\SecurityScopes.xml -ShowProgress

.NOTES
    FileName:    Import-CMSecurityScopeRelations.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2016-12-06
    Updated:     2016-12-06
    
    Version history:
    1.0.0 - (2016-12-06) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify a valid path to an exported XML file containing the Security Scope data.")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
    [ValidateScript({
        if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters"
        }
        else {
            if ([System.IO.Path]::GetExtension((Split-Path -Path $_ -Leaf)) -like ".xml") {
                return $true
            }
            else {
                Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains unsupported file extension. Supported extensions are '.xml'"
            }
        }
    })]
    [string]$Path,

    [parameter(Mandatory=$false, HelpMessage="Show a progressbar displaying the current operation.")]
    [switch]$ShowProgress
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

    # Construct ObjectTypeID table
    $ObjectTypeTable = @{
        2 = @{
            "Class" = "SMS_Package"
            "ID" = "PackageID"
            "Name" = "Name"
        }
        6 = @{
            "Class" = "SMS_Site"
            "ID" = "SiteCode"
            "Name" = "SiteName"
        }
        7 = @{
            "Class" = "SMS_Query"
            "ID" = "QueryID"
            "Name" = "Name"
        }
        9 = @{
            "Class" = "SMS_MeteredProductRule"
            "ID" = "RuleID"
            "Name" = "ProductName"
        }
        14 = @{
            "Class" = "SMS_OperatingSystemInstallPackage"
            "ID" = "PackageID"
            "Name" = "Name"
        }
        17 = @{
            "Class" = "SMS_StateMigration"
            "ID" = "MigrationID"
            "Name" = "SourceName"
        }
        18 = @{
            "Class" = "SMS_ImagePackage"
            "ID" = "PackageID"
            "Name" = "Name"
        }
        19 = @{
            "Class" = "SMS_BootImagePackage"
            "ID" = "PackageID"
            "Name" = "Name"
        }
        20 = @{
            "Class" = "SMS_TaskSequencePackage"
            "ID" = "PackageID"
            "Name" = "Name"
        }
        23 = @{
            "Class" = "SMS_DriverPackage"
            "ID" = "PackageID"
            "Name" = "Name"
        }
        24 = @{
            "Class" = "SMS_SoftwareUpdatesPackage"
            "ID" = "PackageID"
            "Name" = "Name"
        }
        25 = @{
            "Class" = "SMS_Driver"
            "ID" = "CI_ID"
            "Name" = "LocalizedDisplayName"
        }
        28 = @{
            "Class" = "SMS_Admin"
            "ID" = "AdminID"
            "Name" = "DisplayName"
        }
        31 = @{
            "Class" = "SMS_Application"
            "ID" = "ModelName"
            "Name" = "LocalizedDisplayName"
        }
        32 = @{
            "Class" = "SMS_GlobalCondition"
            "ID" = "CI_ID"
            "Name" = "LocalizedDisplayName"
        }
        33 = @{
            "Class" = "SMS_UserMachineRelationship"
            "ID" = "ResourceID"
            "Name" = "ResourceName"
        }
        34 = @{
            "Class" = "SMS_AuthorizationList"
            "ID" = "ModelName" # Needs verification
            "Name" = "LocalizedDisplayName"
        }
        36 = @{
            "Class" = "SMS_DeviceEnrollmentProfile"
            "ID" = "CertCIUniqueID" # Needs verification
            "Name" = "Name"
        }
        37 = @{
            "Class" = "SMS_SoftwareUpdate"
            "ID" = "CI_ID"
            "Name" = "LocalizedDisplayName"
        }
        38 = @{
            "Class" = "SMS_ClientSettings"
            "ID" = "SettingsID"
            "Name" = "Name"
        }
        42 = @{
            "Class" = "SMS_DistributionPointInfo"
            "ID" = "NALPath" # Needs verification
            "Name" = "Name"
        }
        43 = @{
            "Class" = "SMS_DistributionPointGroup"
            "ID" = "GroupID"
            "Name" = "Name"
        }
        45 = @{
            "Class" = "SMS_Boundary"
            "ID" = "BoundaryID"
            "Name" = "DisplayName"
        }
        46 = @{
            "Class" = "SMS_BoundaryGroup"
            "ID" = "GroupID"
            "Name" = "Name"
        }
        47 = @{
            "Class" = "SMS_AntimalwareSettings"
            "ID" = "SettingsID"
            "Name" = "Name"
        }
        48 = @{
            "Class" = "SMS_FirewallPolicy"
            "ID" = "CI_ID" # Needs verification
            "Name" = "LocalizedDisplayName"
        }
        50 = @{
            "Class" = "SMS_Subscription"
            "ID" = "ID"
            "Name" = "Name"
        }
        201 = @{
            "Class" = "SMS_Advertisement"
            "ID" = "AdvertisementID"
            "Name" = "AdvertisementName"
        }
    }
}
Process {
    # Set ProgressCount for ShowProgress
    if ($PSBoundParameters["ShowProgress"]) {
        $ParentProgressCount = 0
        $ChildProgressCount = 0
    }

    # Get XML file and construct XML document
    [xml]$XMLData = Get-Content -Path $Path

    # Validate XML file
    if ($XMLData.ConfigurationManager.Description -like "Export of Security Scope object relations") {
        Write-Verbose -Message "Successfully validated XML document"
    }
    else {
        Write-Warning -Message "Invalid XML document loaded" ; break
    }

    # Determine Security Scope count
    $SecurityScopesCount = $XMLData.ConfigurationManager.ChildNodes.Count

    # Import secured object relations
    foreach ($SecurityScope in ($XMLData.ConfigurationManager.ChildNodes)) {
        if ($PSBoundParameters["ShowProgress"]) {
            $ParentProgressCount++
            Write-Progress -Activity "Processing Security Scopes" -Id 1 -Status "$($ParentProgressCount) / $($SecurityScopesCount)" -CurrentOperation "Current Security Scope: $($SecurityScope.CategoryName)" -PercentComplete (($ParentProgressCount / $SecurityScopesCount) * 100)
        }

        # Determine Security Scope ID from name
        $SecurityScopeID = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_SecuredCategory -ComputerName $SiteServer -Filter "CategoryName = '$($SecurityScope.CategoryName)'" | Select-Object -ExpandProperty CategoryID
        if ($SecurityScopeID -ne $null) {
            if ($PSBoundParameters["ShowProgress"]) {
                $ChildProgressCount = 0
            }

            # Determine relation count
            $RelationsCount = $SecurityScope.ChildNodes.Count

            foreach ($Relation in $SecurityScope.ChildNodes) {
                if ($PSBoundParameters["ShowProgress"]) {
                    $ChildProgressCount++
                    Write-Progress -Activity "Processing Security Scope relations" -Id 2 -ParentId 1 -Status "$($ChildProgressCount) / $($RelationsCount)" -CurrentOperation "Current Security Scope: $($Relation.ObjectKey)" -PercentComplete (($ChildProgressCount / $RelationsCount) * 100)
                }

                # Construct WQL query
                $WQLQuery = "SELECT * FROM $($ObjectTypeTable.Item([int]($Relation.ObjectTypeID)).Item("Class")) WHERE $($ObjectTypeTable.Item([int]($Relation.ObjectTypeID)).Item("ID")) = '$($Relation.ObjectKey)'"
                
                # Validate that object exists
                $RelationObject = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Query $WQLQuery -ComputerName $SiteServer
                if ($RelationObject -ne $null) {
                    # Determine object name
                    $RelationObjectName = $RelationObject | Select-Object -ExpandProperty "$($ObjectTypeTable.Item([int]($Relation.ObjectTypeID)).Item("Name"))"
                    Write-Verbose -Message "Successfully found object '$($RelationObjectName)'"

                    # Assign Security Scope to object
                    try {
                        $Result = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Name AddMemberShips -Class SMS_SecuredCategoryMemberShip -ArgumentList ([array]$SecurityScopeID, [array]$Relation.ObjectKey, [array]$Relation.ObjectTypeID)                    
                        if ($Result.ReturnValue -eq 0) {
                            # Output object to pipline
                            $PSObject = [PSCustomObject]@{
                                SecurityScope = $SecurityScope.CategoryName
                                Name = $RelationObjectName
                                ObjectKey = $Relation.ObjectKey
                                ObjectTypeID = $Relation.ObjectTypeID
                                ObjectClass = $ObjectTypeTable.Item([int]($Relation.ObjectTypeID)).Item("Class")
                                Success = $true
                            }
                            Write-Output -InputObject $PSObject
                        }
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "An error occured while assigning security scope for object '$($RelationObjectName)'. Error message: $($_.Exception.Message)"
                    }
                }
                else {
                    Write-Warning -Message "Query $($WQLQuery) returned 0 results"
                }
            }
        }
        else {
            Write-Warning -Message "Unable to locate a Security Scope with category name: $($SecurityScope.CategoryName)"
        }
    }
}