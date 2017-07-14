<#
.SYNOPSIS
    Import Organizational Units (OU) defined by their distinguished name from a CSV file, to a specified Discovery Method in ConfigMgr

.DESCRIPTION
    This script imports a list of Organizational Units (OU) defined by their distinguished name from a CSV file, to a specified Discovery Method in ConfigMgr.
    It also handles the options for Recursive discovery and whether to include or exclude groups in the discovery. Existing containers for the specified Discovery Method
    will be preserved, meaning that this script will append the containers specified in the CSV file. If a container (more specifically the distinguished name)
    is already present, it will not be added again.

    NOTE: As of now, this script only supports the Active Directory User Discovery and Active Directory System Discovery components.

    Example of a valid CSV file containing the OU containers that should be added:

    DistinguishedName;Recursive;Group
    OU=Users,OU=Sales,DC=contoso,DC=com;Yes;Excluded
    OU=Users,OU=Finance,DC=contoso,DC=com;No;Included

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER ComponentName
    Select the Discovery Method component that the containers will be added to.

.PARAMETER Path
    Specify a path to the CSV file containing distinguished names of the OU's that will be added.

.PARAMETER ShowProgress
    Show a progressbar displaying the current operation.

.EXAMPLE
    Import a CSV file containing a list of containers that should be added to the Active Directory Discovery Method component, on a Primary Site server called 'CM01':
    .\Import-CMDiscoveryMethodContainers.ps1 -SiteServer CM01 -ComponentName SMS_AD_USER_DISCOVERY_AGENT -Path C:\Temp\UserOUList.csv -Verbose

.NOTES
    FileName:    Import-CMDiscoveryMethodContainers.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2016-04-27
    Updated:     2016-04-27
    Version:     1.0.0
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Select the Discovery Method component that the containers will be added to.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("SMS_AD_USER_DISCOVERY_AGENT", "SMS_AD_SYSTEM_DISCOVERY_AGENT")]
    [string]$ComponentName,

    [parameter(Mandatory=$true, HelpMessage="Specify a path to the CSV file containing distinguished names of the OU's that will be added.")]
    [ValidatePattern("^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+\.(csv)$")]
    [ValidateScript({
	    # Check if path contains any invalid characters
	    if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
		    Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters" ; break
	    }
	    else {
		    # Check if the whole directory path exists
		    if (-not(Test-Path -Path (Split-Path -Path $_) -PathType Container -ErrorAction SilentlyContinue)) {
			    Write-Warning -Message "Unable to locate part of or the whole specified path" ; break
		    }
		    elseif (Test-Path -Path (Split-Path -Path $_) -PathType Container -ErrorAction SilentlyContinue) {
			    return $true
		    }
		    else {
			    Write-Warning -Message "Unhandled error" ; break
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

    # Import and validate container data from CSV
    try {
        Write-Verbose -Message "Importing data from specified CSV: $($Path)"
        $ContainerData = Import-Csv -Path $Path -Delimiter ";" -ErrorAction Stop
        $ContainerDataCount = ($ContainerData | Measure-Object).Count
        if (-join($ContainerData | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) -notlike "DistinguishedNameGroupRecursive") {
            Write-Warning -Message "Unsupported headers found in CSV file" ; exit
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "$($_.Exception.Message). Line: $($_.InvocationInfo.ScriptLineNumber)" ; break
    }

    # Option hash-table
    $OptionTable = @{
        Yes = 0
        No = 1
        Included = 0
        Excluded = 1
    }
}
Process {
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }

    # Determine existing containers for selected Discovery Method
    try {
        $DiscoveryContainerList = New-Object -TypeName System.Collections.ArrayList
        $DiscoveryComponent = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_SCI_Component -ComputerName $SiteServer -Filter "ComponentName like '$($ComponentName)'" -ErrorAction Stop
        $DiscoveryPropListADContainer = $DiscoveryComponent.PropLists | Where-Object { $_.PropertyListName -like "AD Containers" }
        if ($DiscoveryPropListADContainer -ne $null) {
            $DiscoveryContainerList.AddRange(@($DiscoveryPropListADContainer.Values)) | Out-Null   
        }
    }
    catch [System.Exception] {
        Write-Verbose -Message "Unable to determine existing discovery method component properties" ; break
    }

    # Process each container item in CSV file
    foreach ($ContainerItem in $ContainerData) {
        # Append LDAP protocol prefix if not present
        if ($ContainerItem.DistinguishedName -notmatch "LDAP://") {
            Write-Verbose -Message "Amending current item to include LDAP protocol prefix: $($ContainerItem.DistinguishedName)"
            $ContainerItem.DistinguishedName = "LDAP://" + $ContainerItem.DistinguishedName
        }

        # Write progress if specified as an parameter switch
        if ($PSBoundParameters["ShowProgress"]) {
            $ProgressCount++
            Write-Progress -Activity "Importing $($ComponentName) containers" -Id 1 -Status "Current container: $($ContainerItem.DistinguishedName)" -PercentComplete (($ProgressCount / $ContainerDataCount) * 100)
        }

        # Determine containers that should be added to the Discovery component
        if ($ContainerItem.DistinguishedName -notin $DiscoveryContainerList) {
            Write-Verbose -Message "Adding container item: $($ContainerItem.DistinguishedName)"
            $DiscoveryContainerList.AddRange(@($ContainerItem.DistinguishedName, $OptionTable[$ContainerItem.Recursive], $OptionTable[$ContainerItem.Group])) | Out-Null
        }
        else {
            Write-Verbose -Message "Detected duplicate container object: $($ContainerItem.DistinguishedName)"
        }
    }

    # Save PropList to Discovery Method component
    $ErrorActionPreference = "Stop"
    Write-Verbose -Message "Attempting to save changes made to the $($ComponentName) component PropList"
    try {
        $DiscoveryPropListADContainer.Values = $DiscoveryContainerList
        $DiscoveryComponent.PropLists = $DiscoveryPropListADContainer
        $DiscoveryComponent.Put() | Out-Null
        Write-Verbose -Message "Successfully saved changes to $($ComponentName) component"
    }
    catch [System.Exception] {
        Write-Verbose -Message "Unable to save changes made to $($ComponentName) component" ; break
    }

    # Restart SMS_SITE_COMPONENT_MANAGER service to apply the changes
    Write-Verbose -Message "Restarting the SMS_SITE_COMPONENT_MANAGER service"
    try {
        Get-Service -ComputerName $SiteServer -Name "SMS_SITE_COMPONENT_MANAGER" -ErrorAction Stop | Restart-Service -Force -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message "$($_.Exception.Message). Line: $($_.InvocationInfo.ScriptLineNumber)" ; break
    }
}